//
//  SystemHandler.swift
//  DeckHandMac
//
//  Domain: system. Mission Control, App Exposé, Show Desktop, Launchpad /
//  Apps, Locate, and moving between Spaces. Owned by the Mac system control
//  lane (S7 symbolic hot keys, S8 display wake and the locked-Mac gate, the
//  Spaces monitor). The locked-Mac gate (`LockGate`) has already let the
//  message through by the time it gets here.
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
            Task { await self.handleSwitchSpace(direction: direction, displayID: displayID, from: connection) }

        case let .watchFocus(on, wantsText):
            // OT-12: the Type panel's loupe; protocol 17: its Live field
            // (`wantsText`). The lock gate let it through; the tracker
            // and `FocusTextSync` withhold everything while locked.
            FocusTracker.shared.watch(on, wantsText: wantsText, connection: connection)

        case .displayState, .lockState, .focusState, .textState, .textEditResult:
            break // Mac → remote only
        }
    }

    /// Moves one Space left or right on `displayID` (the display under the
    /// pointer when `nil`). The Spaces snapshot says first whether there is
    /// a Space that way; a switch past either end, or on a display with one
    /// desktop, is refused without touching the pointer, and the remote
    /// gets a fresh snapshot so its chevrons correct. Without Space data
    /// (private call missing) the Mac tries and watches, as before.
    ///
    /// The switch is the user's own "Move left/right a space" shortcut,
    /// posted as a `CGEvent` (S7), not System Events. The pointer goes to
    /// the target display's menu bar first, so the switch lands on that
    /// display.
    func handleSwitchSpace(direction: SpaceDirection, displayID: UInt32?, from connection: LoomConnectionHandle? = nil) async {
        let target = displayID.map { CGDirectDisplayID($0) }
            ?? injector.displayIDUnderCursor()

        guard let action = HotKeyAction(direction) else { return }
        if action == .missionControl {
            await runSystemMacro(.missionControl)
            return
        }

        let layout = SpacesMonitor.shared.currentLayout()
        let decision = SpaceNavigation.decide(direction, on: layout.display(target))
        if case let .refused(reason) = decision {
            DeckHandLog.input.info("Space switch \(direction.rawValue, privacy: .public) on display \(target, privacy: .public) refused: \(reason.rawValue, privacy: .public)")
            if let connection {
                SpacesMonitor.shared.send(to: connection)
            }
            return
        }

        let pointerBefore = injector.cursorPosition()
        injector.moveCursorToMenuBar(ofDisplay: target)
        try? await Task.sleep(for: .milliseconds(60))

        async let spaceChanged = waitForActiveSpaceChange()
        let posted = await SymbolicHotKeys.shared.perform(action)
        if posted, await spaceChanged {
            injector.moveCursorToCenter(ofDisplay: target)
            CursorLocator.shared.ping()
        } else {
            // Nothing changed (no Space that way after all, or nothing
            // could be posted): put the pointer back instead of yanking it
            // to the centre and flashing Locate for nothing.
            DeckHandLog.input.info("Space switch on display \(target, privacy: .public) changed nothing; pointer restored")
            injector.moveCursor(to: pointerBefore)
            if let connection {
                SpacesMonitor.shared.send(to: connection)
            }
        }
    }

    /// Resolves when Mission Control finishes switching Space, or after a
    /// short timeout if nothing changed. Returns whether the Space changed.
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

    /// Locate is drawn here; everything else goes through the plan in
    /// `SystemActionPlan` (the user's shortcut first, S7).
    func runSystemMacro(_ macro: SystemMacro) async {
        switch macro {
        case .locateCursor:
            CursorLocator.shared.ping()
        case .missionControl, .appExpose, .showDesktop, .launchpad:
            await SystemActionTrigger.shared.run(macro)
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
