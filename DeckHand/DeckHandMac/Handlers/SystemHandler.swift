//
//  SystemHandler.swift
//  DeckHandMac
//
//  Domain: system. Mission Control, App Exposé, Show Desktop, Launchpad /
//  Apps, Locate, and moving between Spaces. Owned by the Mac system control
//  lane (S7 symbolic hot keys, S8 display wake and the locked-Mac gate, the
//  Spaces monitor).
//

import AppKit
import CoreGraphics
import Foundation
import LoomKit

@MainActor
final class SystemHandler: DomainHandler {
    private let injector = InputInjector.shared

    func handle(_ message: SystemMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case let .run(action):
            Task { await self.runSystemMacro(action) }

        case let .switchSpace(direction, displayID):
            Task { await self.handleSwitchSpace(direction: direction, displayID: displayID) }
        }
    }

    /// Mission Control's "Move left/right a space" is a *symbolic hotkey*,
    /// not an app key equivalent. `CGEvent` HID posts (what `sendShortcut`
    /// uses) never fire those — the same reason App Exposé already goes
    /// through System Events. Control-Left/Right posted as HID also lands
    /// in whatever window we just focused, so both chevrons looked like a
    /// no-op on the same desktop.
    func handleSwitchSpace(direction: SpaceDirection, displayID: UInt32?) async {
        let target = displayID.map { CGDirectDisplayID($0) }
            ?? injector.displayIDUnderCursor()

        let pointerBefore = injector.cursorPosition()
        injector.moveCursorToMenuBar(ofDisplay: target)
        try? await Task.sleep(for: .milliseconds(60))

        switch direction {
        case .previous, .next:
            async let spaceChanged = waitForActiveSpaceChange()
            postSystemSpaceKey(previous: direction == .previous)
            if await spaceChanged {
                injector.moveCursorToCenter(ofDisplay: target)
                CursorLocator.shared.ping()
            } else {
                // No Space to go to (end of the strip, or a display with a
                // single desktop): put the pointer back instead of yanking
                // it to the centre and flashing Locate for nothing.
                DeckHandLog.input.info("Space switch on display \(target, privacy: .public) changed nothing; pointer restored")
                injector.moveCursor(to: pointerBefore)
            }
        case .missionControl:
            await runSystemMacro(.missionControl)
        }
    }

    /// `key code 123` = Left Arrow, `124` = Right Arrow. Control+Arrow is
    /// the default Mission Control binding for adjacent Spaces.
    private func postSystemSpaceKey(previous: Bool) {
        let keyCode = previous ? 123 : 124
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = [
            "-e",
            "tell application \"System Events\" to key code \(keyCode) using control down"
        ]
        try? proc.run()
    }

    /// Resolves when Mission Control finishes switching Space, or after a
    /// short timeout if we were already at the end of the strip. Returns
    /// whether the Space actually changed.
    private func waitForActiveSpaceChange(timeout: Duration = .milliseconds(800)) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = OnceResume(continuation)
            let center = NSWorkspace.shared.notificationCenter
            let token = center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                once.resume(returning: true)
            }
            once.setToken(token)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.resume(returning: false)
            }
        }
    }

    func runSystemMacro(_ macro: SystemMacro) async {
        switch macro {
        case .locateCursor:
            CursorLocator.shared.ping()
        case .missionControl:
            runTool("/usr/bin/open", ["-a", "Mission Control"])
        case .appExpose:
            // App Exposé isn't a standalone app — trigger via AppleScript
            runTool("/usr/bin/osascript", ["-e", "tell application \"System Events\" to key code 125 using control down"])
        case .showDesktop, .launchpad:
            // Neither depends on the user's shortcut settings any more, and
            // neither uses the paths macOS 27 broke. See SystemActionTrigger.
            await SystemActionTrigger.shared.run(macro)
        }
    }

    private func runTool(_ path: String, _ arguments: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        do {
            try proc.run()
        } catch {
            DeckHandLog.input.error("Couldn't run \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Resumes a continuation at most once and drops the matching workspace
/// observer. Shared between the space-change notification and its timeout.
private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var token: NSObjectProtocol?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func setToken(_ token: NSObjectProtocol) {
        lock.lock()
        self.token = token
        lock.unlock()
    }

    func resume(returning value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        let token = self.token
        self.token = nil
        lock.unlock()
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        pending?.resume(returning: value)
    }
}
