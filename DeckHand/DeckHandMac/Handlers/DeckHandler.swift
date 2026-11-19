//
//  DeckHandler.swift
//  DeckHandMac
//
//  Domain: chips and deck. Menu-shortcut import, and tracked action runs
//  answered with a receipt. Owned by the deck lane.
//
//  The first six actions run as the domain message they stand for, through
//  the other handlers, and are answered `delivered` at once (as before).
//  The Deck 2 actions run here, one at a time in arrival order:
//
//  - `menuCommand`: `MenuCommandPresser` presses the item through AX;
//  - `macShortcut`: `MacShortcutRunner` runs `shortcuts run`, ≤ 15 s;
//  - `sequence`: each step in order, awaited (an app shortcut waits for its
//    app), with the lock gate asked again before every step, stopping at
//    the first step that fails.
//
//  One receipt per run: the result (`completed` / `failed`) when it is
//  known within `ActionLimits.receiptDeadline`, else `delivered` at the
//  deadline and the run finishes on its own (a late failure is logged).
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
    /// Deck 2 runs, one at a time, so two macros never interleave keys.
    private let runs = SerialTaskQueue()

    func handle(_ message: DeckMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case let .requestAppMenuShortcuts(bundleID):
            Task { await self.sendMenuShortcuts(bundleID: bundleID, to: connection) }

        case let .run(requestID, action):
            if let domainMessage = action.message {
                let outcome = outcome(for: action)
                // `action.message` is never a run, so this goes one level deep.
                await router?.route(domainMessage, from: connection)
                // Sent once the command is handed to injection. Slow commands
                // (appShortcut, dialog presses) finish in their own tasks, so
                // this confirms the Mac got it, not what the app did with it.
                try? await connection.send(.deck(.receipt(requestID: requestID, outcome: outcome)))
            } else {
                startDeck2Run(requestID: requestID, action: action, connection: connection)
            }

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

    // MARK: - Deck 2 runs

    private func startDeck2Run(requestID: String, action: Action, connection: LoomConnectionHandle) {
        let receipt = Receipt(requestID: requestID, connection: connection)
        if action.needsAccessibility, !injector.isAccessibilityGranted {
            Task { await receipt.send(.refused(reason: .accessibilityMissing)) }
            return
        }
        // Whatever happens in the queue, the remote hears by the deadline.
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ActionLimits.receiptDeadline))
            guard !Task.isCancelled else { return }
            await receipt.send(.delivered)
        }
        _ = runs.enqueue { [weak self] in
            guard let self else { return }
            let outcome = await self.perform(action, connection: connection)
            deadline.cancel()
            if !(await receipt.send(outcome)), !outcome.isSuccess {
                DeckHandLog.input.info("Deck run \(action.kindName, privacy: .public) failed after its receipt: \(String(describing: outcome), privacy: .public)")
            }
        }
    }

    /// Runs one action to its end and says how it went.
    private func perform(_ action: Action, connection: LoomConnectionHandle) async -> ActionOutcome {
        switch action {
        case let .menuCommand(bundleID, path):
            let result = await MenuCommandPresser.press(bundleID: bundleID, path: path, launcher: launcher)
            return MenuCommandPresser.outcome(result, path: path)

        case let .macShortcut(name):
            let ending = await MacShortcutRunner.run(name: name)
            return MacShortcutRun.outcome(ending, name: name)

        case let .sequence(steps):
            return await performSequence(steps, connection: connection)

        case let .appShortcut(bundleID, keys):
            // Awaited here (the apps handler does it in a detached task),
            // so the next step starts after the keys went to the app.
            await launcher.activateAndWait(bundleID: bundleID)
            injector.sendShortcut(keys: keys)
            return .completed

        case let .launchApp(bundleID):
            return await launcher.launch(bundleID: bundleID)
                ? .completed
                : .failed(reason: "The app couldn't be opened.")

        case .shortcut, .system, .media:
            // Through the input and system handlers, so a chord stays in
            // order with typed text (`TypingQueue`).
            guard let message = action.message else { return .failed(reason: "Unknown action.") }
            await router?.route(message, from: connection)
            return .completed

        case .contextAction:
            // Validation keeps dialog presses out of sequences; a top-level
            // one never comes here (it has a domain message).
            return .refused(reason: .staleContext)
        }
    }

    private func performSequence(_ steps: [SequenceStep], connection: LoomConnectionHandle) async -> ActionOutcome {
        let total = steps.count
        var ranAny = false
        for (index, step) in steps.enumerated() {
            switch step {
            case let .delay(milliseconds):
                try? await Task.sleep(for: .milliseconds(max(0, milliseconds)))

            case let .run(inner):
                // The Mac may have locked since the run was admitted.
                guard LockPolicy.allows(inner, state: MacLockMonitor.shared.state) else {
                    return ranAny
                        ? .failed(reason: "Stopped at step \(index + 1) of \(total): the Mac is locked.")
                        : .refused(reason: .macLocked)
                }
                if ranAny {
                    try? await Task.sleep(for: .milliseconds(ActionLimits.sequenceStepGapMilliseconds))
                }
                let outcome = await perform(inner, connection: connection)
                ranAny = true
                switch outcome {
                case .completed, .delivered:
                    continue
                case let .failed(reason):
                    return .failed(reason: "Step \(index + 1) of \(total): \(reason)")
                case let .refused(reason):
                    return .failed(reason: "Step \(index + 1) of \(total) was refused (\(reason.rawValue)).")
                }
            }
        }
        return .completed
    }

    /// Sends a run's receipt once, whichever of the result or the deadline
    /// comes first.
    @MainActor
    private final class Receipt {
        let requestID: String
        let connection: LoomConnectionHandle
        private var sent = false

        init(requestID: String, connection: LoomConnectionHandle) {
            self.requestID = requestID
            self.connection = connection
        }

        /// Returns `false` when a receipt had already gone.
        @discardableResult
        func send(_ outcome: ActionOutcome) async -> Bool {
            guard !sent else { return false }
            sent = true
            try? await connection.send(.deck(.receipt(requestID: requestID, outcome: outcome)))
            return true
        }
    }

    // MARK: - Menu import

    private func sendMenuShortcuts(bundleID: String, to handle: LoomConnectionHandle) async {
        let shortcuts = await MenuShortcutDiscovery.discover(bundleID: bundleID, launcher: launcher)
        try? await handle.send(.deck(.appMenuShortcutsResponse(bundleID: bundleID, shortcuts: shortcuts)))
    }
}
