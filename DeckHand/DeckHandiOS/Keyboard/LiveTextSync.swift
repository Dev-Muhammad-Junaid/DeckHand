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
//  Everything for the Mac goes out through one ordered outbox (edits,
//  selections, keys), never as separate tasks that could overtake each
//  other (build 29 bug 9). Keys pressed in synced Live (Accept ⇥, the key
//  row, the joystick, hardware arrows) come here too (`sendRaw`), so they
//  wait behind the edit typed before them.
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
    /// A short note under the field when an edit didn't land as typed
    /// ("The Mac couldn't move its caret there, so nothing was typed").
    private(set) var note: String?

    @ObservationIgnored private var reconciler = TextSyncReconciler()
    @ObservationIgnored weak var display: LiveTextDisplay?
    @ObservationIgnored var sender: TrackpadSender?
    /// Asks before an edit that types Return goes out (the Type panel's
    /// Return guard, VQ-036); runs `send` now when not needed.
    @ObservationIgnored var confirmReturn: ((_ send: @escaping () -> Void) -> Void)?
    @ObservationIgnored private var badgeRefresh: Task<Void, Never>?
    /// One ordered queue to the Mac.
    private enum Outgoing {
        case edit(TextEditRequest)
        case select(TextSelectRequest)
        case raw(TextSyncRawInput)
    }
    @ObservationIgnored private var outbox: [Outgoing] = []
    @ObservationIgnored private var draining = false

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

    /// The caret moved in the field. `fieldText` is the field's text now:
    /// a caret that comes with a text change isn't a caret move.
    func localSelection(_ selection: TextRange, fieldText: String) {
        run(reconciler.localSelection(selection, fieldText: fieldText, now: Self.now()))
    }

    /// Keys or text for the Mac's caret. Synced: behind the edits typed
    /// before them. Blind: at once, as before.
    func sendRaw(_ input: TextSyncRawInput) {
        run(reconciler.localRaw(input, now: Self.now()))
    }

    /// Watching stopped (Live closed, the panel hidden, disconnected).
    func reset() {
        reconciler.reset()
        outbox.removeAll()
        display?.becameBlind()
        refreshBadge()
    }

    // MARK: Effects

    private func run(_ effects: [TextSyncReconciler.Effect]) {
        for effect in effects {
            switch effect {
            case let .sendEdit(edit):
                if edit.replacement.contains("\n"), let confirmReturn {
                    confirmReturn { [weak self] in self?.enqueue(.edit(edit)) }
                } else {
                    enqueue(.edit(edit))
                }
            case let .sendSelect(selection):
                enqueue(.select(selection))
            case let .sendRaw(input):
                // The Type panel already guarded a Return key press.
                enqueue(.raw(input))
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

    /// Sends in order: each message waits for the one before it.
    private func enqueue(_ item: Outgoing) {
        outbox.append(item)
        guard !draining else { return }
        draining = true
        Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        while !outbox.isEmpty {
            let item = outbox.removeFirst()
            guard let sender else { continue }
            switch item {
            case let .edit(edit): await sender.sendTextEdit(edit)
            case let .select(selection): await sender.sendTextSelect(selection)
            case let .raw(.keys(chord)): await sender.sendShortcut(chord)
            case let .raw(.text(text)): await sender.typeText(text)
            }
        }
        draining = false
    }

    /// Badge, reason and note; and the next timeout (an unanswered edit,
    /// keys the Mac showed nothing for, the end of MAC WINS or a note)
    /// runs the reconciler's tick.
    private func refreshBadge() {
        let now = Self.now()
        let next = reconciler.badge(now: now)
        if badge != next { badge = next }
        if isSynced != reconciler.isSynced { isSynced = reconciler.isSynced }
        let reason = reconciler.isSynced ? nil : reconciler.reasonLine
        if reasonLine != reason { reasonLine = reason }
        let line = reconciler.note(now: now)?.line
        if note != line { note = line }
        badgeRefresh?.cancel()
        if let deadline = reconciler.nextDeadline(now: now) {
            badgeRefresh = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0.01, deadline - now + 0.005)))
                guard !Task.isCancelled, let self else { return }
                self.run(self.reconciler.tick(now: Self.now()))
            }
        }
    }

    private static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
