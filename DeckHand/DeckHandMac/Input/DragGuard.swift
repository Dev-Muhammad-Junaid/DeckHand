//
//  DragGuard.swift
//  DeckHandMac
//
//  Which remote holds which mouse button down (click-drag), and the
//  safety release: a button goes up when its remote disconnects, or when
//  the remote hasn't refreshed it for `DragPolicy.hostReleaseAfter` (a
//  remote repeats `input.mouseDown` while it holds the button). The rules
//  are Core's `HeldButtonWatchdog`; this file posts the events.
//

import Foundation

@MainActor
final class DragGuard {
    static let shared = DragGuard()

    private var watchdog = HeldButtonWatchdog<UUID>()
    private var sweepTask: Task<Void, Never>?
    private let injector = InputInjector.shared

    private init() {}

    func mouseDown(_ button: MouseButton, from id: UUID) {
        let isNew = watchdog.pressed(button, by: id, at: Self.now)
        if isNew, !injector.heldButtons.contains(button) {
            injector.mouseDown(button: button)
        }
        startSweepIfNeeded()
    }

    func mouseUp(_ button: MouseButton, from id: UUID) {
        guard watchdog.released(button, by: id) else { return }
        releaseIfUnheld(button)
    }

    /// The remote left: release everything it held.
    func connectionRemoved(id: UUID) {
        let buttons = watchdog.releaseAll(for: id)
        guard !buttons.isEmpty else { return }
        DeckHandLog.input.info("Drag: released \(buttons.count, privacy: .public) held button(s) of a remote that left")
        for button in buttons { releaseIfUnheld(button) }
    }

    private func releaseIfUnheld(_ button: MouseButton) {
        // Another remote may still hold the same button.
        guard !watchdog.isHeld(button) else { return }
        injector.mouseUp(button: button)
    }

    private func startSweepIfNeeded() {
        guard sweepTask == nil else { return }
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.sweep() { return }
            }
        }
    }

    /// Releases expired buttons. Returns `true` (and ends the sweep) when
    /// nothing is held any more.
    private func sweep() -> Bool {
        for held in watchdog.expired(at: Self.now) {
            DeckHandLog.input.info("Drag: released the \(held.button.rawValue, privacy: .public) button; its remote stopped refreshing it")
            releaseIfUnheld(held.button)
        }
        guard !watchdog.anyHeld else { return false }
        sweepTask = nil
        return true
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Connection end for the iOS interaction lane's Mac services. Called
/// from `MacSystemSession.connectionRemoved` (one announced line in
/// `LockGate.swift`), so `ControlReceiver` needs no edit.
@MainActor
enum InteractionSession {
    static func connectionRemoved(id: UUID) {
        DragGuard.shared.connectionRemoved(id: id)
        MacClipboardSync.shared.removeConnection(id: id)
        if MacLockMonitor.shared.connectionHandles.isEmpty {
            // Nobody left to have typed it.
            TypingQueue.shared.cancelAll()
        }
    }
}
