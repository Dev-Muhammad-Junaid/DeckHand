//
//  LiveTextSync.swift
//  DeckHandiOS – Keyboard
//
//  Live text sync, Phase 1 (protocol 17, `RD-live-sync-and-caret.md` §3):
//  the iPad's model between the Mac's `textState` / `textEditResult` and
//  the Type panel's Live field. The rules are Core's `TextSyncReconciler`
//  (local echo, one edit in flight, MAC WINS, composition hold, echo
//  suppression); this object runs its effects: it sends edits and
//  selections through the `TrackpadSender`, shows the Mac's text in the
//  field (`LiveTextDisplay`), plays the refused haptic and keeps the badge
//  current.
//
//  One per session (`ControlSessionModel.liveText`). It only has text
//  while the Live field is open and on screen: the panel asks with
//  `ControlSessionModel.setLiveTextWanted(_:)`, which sends
//  `watchFocus(on:wantsText:)`.
//

import Foundation
import Observation

/// The field that shows synced text (`LiveTypingTextView`).
@MainActor
protocol LiveTextDisplay: AnyObject {
    /// Show the Mac's text with this caret or selection (relative to
    /// `text`). Not an edit: nothing goes back to the Mac.
    func showSynced(text: String, selection: TextRange)
    /// The field can't be read any more: back to the blind buffer.
    func becameBlind()
}

@MainActor
@Observable
final class LiveTextSync {
    /// What the badge says (dot-matrix, top-trailing in the field).
    private(set) var badge: SyncBadge = .blind
    /// The field shows the Mac's text.
    private(set) var isSynced = false
    /// Why it can't, in plain words (`nil` while synced or unknown).
    private(set) var reasonLine: String?

    @ObservationIgnored private var reconciler = TextSyncReconciler()
    @ObservationIgnored weak var display: LiveTextDisplay?
    @ObservationIgnored var sender: TrackpadSender?
    /// Asks before an edit that types Return goes out (the Type panel's
    /// Return guard, VQ-036); runs `send` now when not needed.
    @ObservationIgnored var confirmReturn: ((_ send: @escaping () -> Void) -> Void)?
    @ObservationIgnored private var badgeRefresh: Task<Void, Never>?

    init() {}

    /// The reconciler's view of the field, for the text view.
    var text: String { reconciler.text }
    var selection: TextRange { reconciler.selection }

    // MARK: From the Mac

    func receive(_ state: FocusedTextState) {
        run(reconciler.receive(state, now: Self.now()))
    }

    func receive(_ result: TextEditResult) {
        run(reconciler.receive(result, now: Self.now()))
    }

    // MARK: From the field

    func localChange(text: String, selection: TextRange, composing: Bool) {
        run(reconciler.localChange(text: text, selection: selection, composing: composing, now: Self.now()))
    }

    func localSelection(_ selection: TextRange) {
        run(reconciler.localSelection(selection, now: Self.now()))
    }

    /// Watching stopped (Live closed, the panel hidden, disconnected).
    func reset() {
        reconciler.reset()
        display?.becameBlind()
        refreshBadge()
    }

    // MARK: Effects

    private func run(_ effects: [TextSyncReconciler.Effect]) {
        for effect in effects {
            switch effect {
            case let .sendEdit(edit):
                let sender = sender
                let send = { Task { await sender?.sendTextEdit(edit) } }
                if edit.replacement.contains("\n"), let confirmReturn {
                    confirmReturn { _ = send() }
                } else {
                    _ = send()
                }
            case let .sendSelect(selection):
                let sender = sender
                Task { await sender?.sendTextSelect(selection) }
            case let .show(text, selection):
                display?.showSynced(text: text, selection: selection)
            case .becameBlind:
                display?.becameBlind()
            case .conflict:
                GestureHaptic.double.trigger()
            }
        }
        refreshBadge()
    }

    private func refreshBadge() {
        let now = Self.now()
        let next = reconciler.badge(now: now)
        if badge != next { badge = next }
        if isSynced != reconciler.isSynced { isSynced = reconciler.isSynced }
        let reason = reconciler.isSynced ? nil : reconciler.reasonLine
        if reasonLine != reason { reasonLine = reason }
        badgeRefresh?.cancel()
        if let deadline = reconciler.badgeDeadline(now: now) {
            badgeRefresh = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0.01, deadline - now)))
                guard !Task.isCancelled else { return }
                self?.refreshBadge()
            }
        }
    }

    private static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
