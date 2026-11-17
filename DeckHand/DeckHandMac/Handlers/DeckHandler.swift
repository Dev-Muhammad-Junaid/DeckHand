//
//  DeckHandler.swift
//  DeckHandMac
//
//  Domain: chips and deck. Menu-shortcut import, and tracked action runs
//  answered with a receipt. Owned by the deck lane (the iOS interaction lane
//  until the deck work starts).
//

import Foundation
import LoomKit

@MainActor
final class DeckHandler: DomainHandler {
    private let injector = InputInjector.shared
    private let launcher = AppLauncher.shared
    /// Set by `MacHandlers`. A run is dispatched as the message its action
    /// stands for, through the other domains' handlers.
    weak var router: ControlRouter<LoomConnectionHandle>?

    func handle(_ message: DeckMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case let .requestAppMenuShortcuts(bundleID):
            Task { await self.sendMenuShortcuts(bundleID: bundleID, to: connection) }

        case let .run(requestID, action):
            let outcome = outcome(for: action)
            // `action.message` is never a run, so this goes one level deep.
            await router?.route(action.message, from: connection)
            // Sent once the command is handed to injection. Slow commands
            // (appShortcut, dialog presses) finish in their own tasks, so
            // this confirms the Mac got it, not what the app did with it.
            try? await connection.send(.deck(.receipt(requestID: requestID, outcome: outcome)))

        case .appMenuShortcutsResponse, .receipt:
            break // Mac → remote only
        }
    }

    /// Decided before the action is dispatched: a dialog press is queued in
    /// its own task, and a stale one is dropped there, so it mustn't read as
    /// confirmed on the remote.
    private func outcome(for action: Action) -> ActionOutcome {
        guard injector.isAccessibilityGranted else {
            return .refused(reason: .accessibilityMissing)
        }
        if case let .contextAction(id) = action, !ContextObserver.shared.hasAction(id: id) {
            return .refused(reason: .staleContext)
        }
        return .delivered
    }

    private func sendMenuShortcuts(bundleID: String, to handle: LoomConnectionHandle) async {
        let shortcuts = await MenuShortcutDiscovery.discover(bundleID: bundleID, launcher: launcher)
        try? await handle.send(.deck(.appMenuShortcutsResponse(bundleID: bundleID, shortcuts: shortcuts)))
    }
}
