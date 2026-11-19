//
//  SpacesMonitor.swift
//  DeckHandMac
//
//  Builds the displays / Spaces / pointer snapshot (`DisplayLayout`, Core)
//  and sends it to every approved remote as `system.displayState`:
//
//  - when a remote connects;
//  - on `NSWorkspace.activeSpaceDidChangeNotification`;
//  - when displays are added, removed or rearranged;
//  - when the pointer crosses to another display (checked from the input
//    path through `noteCursorActivity()`, at most 10 times a second);
//  - after `SystemHandler` refuses a Space switch, so the remote corrects.
//
//  An identical snapshot isn't sent twice. While the Mac is locked the
//  snapshot goes without Space data (full-screen app names are content).
//
//  Private API (Mac app only, approved in DECISIONS.md 2026-11-17), looked
//  up with `dlsym`: `CGSMainConnectionID` and `CGSCopyManagedDisplaySpaces`
//  (SkyLight). If either is missing the snapshot goes without Space fields
//  (`spacesKnown == false`) and everything else keeps working. Display
//  UUIDs come from `CGDisplayCreateUUIDFromDisplayID` (public, ColorSync).
//

import AppKit
import ColorSync
import CoreGraphics
import Foundation
import LoomKit

@MainActor
final class SpacesMonitor {
    static let shared = SpacesMonitor()

    private var connections: [UUID: LoomConnectionHandle] = [:]
    private var lastSent: DisplayLayout?
    private var lastCursorDisplayID: UInt32?
    private var lastCursorCheck = Date.distantPast
    private var cursorCheckTask: Task<Void, Never>?
    private var broadcastTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Least time between two pointer-display checks.
    private static let cursorCheckInterval: TimeInterval = 0.1
    /// Coalesces bursts (a display reconfiguration posts several).
    private static let broadcastDelay: Duration = .milliseconds(150)

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleBroadcast() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleBroadcast() }
        })
        if SkyLightSpaces.shared == nil {
            DeckHandLog.input.error("Spaces: CGSCopyManagedDisplaySpaces / CGSMainConnectionID not found on this macOS; remotes get displays without desktops")
        }
    }

    // MARK: - Connections

    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {
        connections[id] = handle
        let layout = currentLayout()
        lastCursorDisplayID = layout.cursorDisplayID
        Task { try? await handle.send(.system(.displayState(layout: layout))) }
    }

    func removeConnection(id: UUID) {
        connections.removeValue(forKey: id)
    }

    // MARK: - Triggers

    /// Called for pointer input. Checks, at most every 0.1 s, whether the
    /// pointer is on another display than last time.
    func noteCursorActivity() {
        guard !connections.isEmpty, cursorCheckTask == nil else { return }
        let wait = max(0, Self.cursorCheckInterval - Date().timeIntervalSince(lastCursorCheck))
        cursorCheckTask = Task { [weak self] in
            // Runs after the pending move has been posted.
            try? await Task.sleep(for: .seconds(max(wait, 0.02)))
            guard let self else { return }
            self.cursorCheckTask = nil
            self.lastCursorCheck = Date()
            let display = InputInjector.shared.displayIDUnderCursor()
            guard display != self.lastCursorDisplayID else { return }
            self.lastCursorDisplayID = display
            self.broadcast()
        }
    }

    /// Sends the snapshot to every remote now if it changed.
    func scheduleBroadcast() {
        broadcastTask?.cancel()
        broadcastTask = Task { [weak self] in
            try? await Task.sleep(for: Self.broadcastDelay)
            guard !Task.isCancelled else { return }
            self?.broadcast()
        }
    }

    /// Sends the current snapshot to one remote, even if unchanged (after
    /// a refused switch, so its chevrons correct).
    func send(to handle: LoomConnectionHandle) {
        let layout = currentLayout()
        Task { try? await handle.send(.system(.displayState(layout: layout))) }
    }

    private func broadcast() {
        guard !connections.isEmpty else { return }
        let layout = currentLayout()
        lastCursorDisplayID = layout.cursorDisplayID
        guard layout != lastSent else { return }
        lastSent = layout
        let message = ControlMessage.system(.displayState(layout: layout))
        for handle in connections.values {
            Task { try? await handle.send(message) }
        }
    }

    // MARK: - Snapshot

    /// The layout now. Cheap: one WindowServer call plus `NSScreen`.
    func currentLayout() -> DisplayLayout {
        let mainID = CGMainDisplayID()
        let displays: [DisplayDescriptor] = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let rect = CGDisplayBounds(id)
            return DisplayDescriptor(
                displayID: id,
                name: screen.localizedName.isEmpty ? "Display" : screen.localizedName,
                isMain: id == mainID,
                bounds: DisplayBounds(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height),
                uuid: Self.uuidString(for: id)
            )
        }
        let managed = SkyLightSpaces.shared?.copyManagedDisplaySpaces().flatMap { raw in
            ManagedSpacesParser.parse(raw) { pid in
                NSRunningApplication(processIdentifier: pid)?.localizedName
            }
        }
        let layout = DisplayLayoutBuilder.build(
            displays: displays,
            managed: managed,
            cursorDisplayID: InputInjector.shared.displayIDUnderCursor()
        )
        return LockPolicy.withholdsContext(MacLockMonitor.shared.state) ? layout.withoutSpaces : layout
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

/// The private SkyLight calls for Spaces, looked up once.
private struct SkyLightSpaces: @unchecked Sendable {
    typealias MainConnectionID = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    let mainConnectionID: MainConnectionID
    let copySpaces: CopyManagedDisplaySpaces

    static let shared: SkyLightSpaces? = {
        guard let connection = PrivateSymbol.load("CGSMainConnectionID", as: MainConnectionID.self),
              let copy = PrivateSymbol.load("CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpaces.self)
        else { return nil }
        return SkyLightSpaces(mainConnectionID: connection, copySpaces: copy)
    }()

    /// The raw answer as Foundation values, or `nil`.
    func copyManagedDisplaySpaces() -> [Any]? {
        guard let array = copySpaces(mainConnectionID())?.takeRetainedValue() else { return nil }
        return array as? [Any]
    }
}
