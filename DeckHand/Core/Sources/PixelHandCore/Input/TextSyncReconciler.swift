//
//  TextSyncReconciler.swift
//  PixelHandCore
//
//  The iPad's half of live text sync (protocol 17, `RD-live-sync-and-caret.md`
//  §1.2 "Conflicts: the Mac is the source of truth"). Pure, so every rule
//  is tested here; `LiveTypingField` feeds it and shows what it says.
//
//  - The field shows the Mac's window of text with the caret at the Mac's
//    selection.
//  - Everything that goes to the Mac from the synced field goes through
//    **one ordered queue** here: anchored edits, caret moves (`textSelect`)
//    and raw input for the Mac's caret (Accept ⇥, the key row, the
//    joystick, hardware arrows; `TextSyncRawInput`). Build 29 bug 9: keys
//    and caret moves went straight out beside the edits and overtook them.
//  - A local change shows at once (local echo) and goes out as one anchored
//    `TextEditRequest` (range of revision N → replacement). One edit is in
//    flight at a time; changes made meanwhile wait and go as one edit
//    after it is answered.
//  - While an edit is in flight the Mac's intermediate states (it types
//    the replacement a key at a time) update the base but never the field.
//  - When the edit is answered and nothing waits, the Mac's text is shown
//    if it differs (its autocorrect, an accepted suggestion). If it equals
//    the field (the echo of our own edit) the caret doesn't move; a caret
//    the person put elsewhere meanwhile goes out as a `textSelect`.
//  - Changes that waited are merged with what the Mac did meanwhile when
//    the two don't touch; otherwise the Mac wins.
//  - Raw input waits behind the edits typed before it; the text it was
//    pressed after goes first, then the caret where the field had it, then
//    the keys. Until the Mac's state shows what the keys did (a "raw
//    flight"), text typed meanwhile waits and is merged after the keys'
//    effect, as typed after them.
//  - `conflict`: the field shows the Mac's text and caret, and the badge
//    says MAC WINS for 1.4 s. The unsent queue is dropped.
//  - While an input method composes (marked text) nothing goes out and the
//    Mac's updates are held, so a Mac update never yanks the composition.
//  - A caret moved here (tap, the space-bar trackpad, selection handles)
//    goes out as `textSelect`; the Mac's states that still show the old
//    selection are ignored for `selectGrace`. A selection callback that
//    comes with a text change (UIKit reports the caret before the text)
//    is not a caret move: the change carries it.
//  - Timeouts run from `tick(now:)` (the host schedules it at
//    `nextDeadline(now:)`), not only when a state happens to arrive.
//

import Foundation

/// The sync badge in the field's top-trailing corner (dot-matrix).
public enum SyncBadge: String, Sendable, Hashable, CaseIterable {
    /// Live: the field shows the Mac's text. Mint pixel.
    case sync
    /// An edit is in flight. Glow pixel.
    case sending
    /// The Mac's text replaced the iPad's (a conflict), for 1.4 s. Amber.
    case macWins
    /// The field can't be read; typing is blind, as before. Dim.
    case blind

    /// The dot-matrix label.
    public var label: String {
        switch self {
        case .sync: "SYNC"
        case .sending: "SENDING"
        case .macWins: "MAC WINS"
        case .blind: "BLIND"
        }
    }

    /// What VoiceOver says.
    public var spokenLabel: String {
        switch self {
        case .sync: "In sync with the Mac"
        case .sending: "Sending to the Mac"
        case .macWins: "The Mac's text won"
        case .blind: "Typing blind: the Mac's text isn't shown"
        }
    }
}

/// Input for the Mac's caret that isn't a range edit: a key chord (Tab,
/// arrows, Return from the key row, ⌘ chords) or text typed at the caret
/// (the numpad). In a synced field it goes through the reconciler's queue,
/// behind the edits before it.
public enum TextSyncRawInput: Equatable, Sendable {
    case keys([String])
    case text(String)
}

/// A short note under the synced field when something didn't go as typed.
public enum TextSyncNote: Equatable, Sendable {
    /// The Mac couldn't put its caret where the edit was (its selection
    /// can't be set and its caret isn't known): nothing was typed.
    case caretNotPlaced
    /// The Mac didn't answer an edit in time: the field shows its text.
    case noAnswer

    public var line: String {
        switch self {
        case .caretNotPlaced: "The Mac couldn't move its caret there, so nothing was typed"
        case .noAnswer: "The Mac didn't answer: showing its text"
        }
    }
}

public struct TextSyncReconciler: Sendable {
    /// What the field must do.
    public enum Effect: Equatable, Sendable {
        case sendEdit(TextEditRequest)
        case sendSelect(TextSelectRequest)
        /// Keys or text for the Mac's caret, in order after the effects
        /// before it.
        case sendRaw(TextSyncRawInput)
        /// Show `text` with `selection` (relative to `text`).
        case show(text: String, selection: TextRange)
        /// The field can't be read any more: go back to the blind buffer.
        case becameBlind
        /// A conflict: play the refused haptic.
        case conflict
    }

    /// How long MAC WINS shows.
    public static let macWinsDuration = 1.4
    /// An edit not answered in this long is given up; the Mac's text shows.
    public static let inFlightTimeout = 3.0
    /// How long the Mac's states may still show the old selection after a
    /// `textSelect`.
    public static let selectGrace = 0.5
    /// Raw input is taken as done at the first Mac state this long after
    /// the last of it went…
    public static let rawQuiet = 0.15
    /// …or this long after it went, with no state (a key that changed
    /// nothing, like ← at the start).
    public static let rawTimeout = 0.6
    /// How long a note shows.
    public static let noteDuration = 4.0

    private struct Flight: Sendable {
        var request: UInt32
        /// The field's text the edit makes (what the Mac should end up with).
        var expected: String
        var windowStart: Int
        var sentAt: Double
        /// The answer came before the state for its revision.
        var answeredRevision: UInt32?
        var outcome: TextEditOutcome?
    }

    /// Raw input went; the Mac's state will show what it did.
    private struct RawFlight: Sendable {
        /// The Mac's text when it went (updated as the Mac's states show
        /// while nothing is typed here).
        var base: String
        var windowStart: Int
        var lastSentAt: Double
        /// The person moved the caret here meanwhile.
        var caretMoved = false
    }

    private struct QueuedRaw: Sendable {
        var input: TextSyncRawInput
        /// The field when it was pressed: the text before it goes first.
        var textBefore: String
        var selectionBefore: TextRange
        /// `baseEpoch` then; a snapshot from another base isn't used.
        var epoch: Int
    }

    /// The Mac's last state.
    public private(set) var mac: FocusedTextState?
    /// What the field shows (the Mac's window, plus local echo).
    public private(set) var text = ""
    /// The field's caret or selection, relative to `text`.
    public private(set) var selection = TextRange.caret(0)
    /// `text`'s offset in the Mac's field.
    public private(set) var windowStart = 0
    public private(set) var composing = false

    private var flight: Flight?
    private var raw: RawFlight?
    private var queue: [QueuedRaw] = []
    /// Bumped whenever the field's text changes for a reason other than
    /// the person (the Mac's text adopted or merged).
    private var baseEpoch = 0
    private var heldState: FocusedTextState?
    private var pendingSelect: (range: TextRange, at: Double)?
    private var macWinsUntil = -Double.infinity
    private var shownNote: (note: TextSyncNote, until: Double)?
    private var nextRequest: UInt32 = 1

    public init() {}

    /// The field shows the Mac's text (not the blind buffer).
    public var isSynced: Bool {
        guard let mac else { return false }
        return mac.readable.isReadable && mac.window != nil
    }

    /// An edit waits for its answer.
    public var isSending: Bool { flight != nil }

    /// Raw input waiting behind an edit.
    public var queuedRawCount: Int { queue.count }

    /// Why the field can't sync, when it can't.
    public var reasonLine: String? {
        guard let mac else { return nil }
        return mac.readable.reasonLine
    }

    public func badge(now: Double) -> SyncBadge {
        guard isSynced else { return .blind }
        if now < macWinsUntil { return .macWins }
        return flight != nil || !queue.isEmpty ? .sending : .sync
    }

    /// The note to show under the field now, if any.
    public func note(now: Double) -> TextSyncNote? {
        guard let shownNote, now < shownNote.until else { return nil }
        return shownNote.note
    }

    /// When the badge changes on its own (MAC WINS ends), so the view can
    /// refresh then.
    public func badgeDeadline(now: Double) -> Double? {
        now < macWinsUntil ? macWinsUntil : nil
    }

    /// The next time `tick(now:)` has something to do: a timeout, the end
    /// of MAC WINS or of a note.
    public func nextDeadline(now: Double) -> Double? {
        var times: [Double] = []
        if let flight { times.append(flight.sentAt + Self.inFlightTimeout) }
        if let raw { times.append(raw.lastSentAt + Self.rawTimeout) }
        if now < macWinsUntil { times.append(macWinsUntil) }
        if let shownNote, now < shownNote.until { times.append(shownNote.until) }
        return times.min()
    }

    // MARK: From the Mac

    /// A `system.textState`.
    public mutating func receive(_ state: FocusedTextState, now: Double) -> [Effect] {
        if composing {
            heldState = state
            return []
        }
        return apply(state, now: now)
    }

    /// A `system.textEditResult`.
    public mutating func receive(_ result: TextEditResult, now: Double) -> [Effect] {
        guard var current = flight, current.request == result.request else { return [] }
        switch result.outcome {
        case .applied, .rebased:
            if let mac, mac.field == result.field, mac.revision >= result.revision {
                return settle(now: now)
            }
            // The state for that revision hasn't come yet: settle on it.
            current.answeredRevision = result.revision
            current.outcome = result.outcome
            flight = current
            return []
        case .conflict:
            flight = nil
            queue.removeAll()
            macWinsUntil = now + Self.macWinsDuration
            return adoptMac() + [.conflict]
        case let .refused(reason):
            flight = nil
            queue.removeAll()
            if reason == .notEditable, let mac, mac.readable.isReadable, mac.canEdit {
                // Readable and editable, yet refused: the Mac couldn't put
                // its caret there and typed nothing rather than guess.
                shownNote = (.caretNotPlaced, now + Self.noteDuration)
            }
            return adoptMac()
        }
    }

    // MARK: From the field

    /// The field's text or caret changed by the person (typing, dictation,
    /// autocorrect, paste, an input method). `composing` while marked text
    /// is up.
    public mutating func localChange(text newText: String, selection newSelection: TextRange, composing nowComposing: Bool, now: Double) -> [Effect] {
        let wasComposing = composing
        text = newText
        selection = newSelection
        composing = nowComposing
        guard !nowComposing, isSynced else { return [] }
        var effects = pump(now: now)
        if wasComposing, let held = heldState {
            heldState = nil
            effects += apply(held, now: now)
        }
        return effects
    }

    /// The person moved the caret or selection (a tap, the space-bar
    /// trackpad, selection handles). `fieldText` is the field's text as the
    /// view has it: when it differs from `text`, this is the caret of a
    /// text change not reported yet (UIKit calls the selection delegate
    /// first), and `localChange` will carry it.
    public mutating func localSelection(_ newSelection: TextRange, fieldText: String? = nil, now: Double) -> [Effect] {
        if let fieldText, fieldText != text { return [] }
        selection = newSelection
        if raw != nil { raw?.caretMoved = true }
        guard isSynced, !composing else { return [] }
        return pump(now: now)
    }

    /// Keys or text for the Mac's caret (Accept ⇥, the key row, the
    /// joystick). Not synced: it goes at once, as before.
    public mutating func localRaw(_ input: TextSyncRawInput, now: Double) -> [Effect] {
        guard isSynced else { return [.sendRaw(input)] }
        // While an input method composes, the field holds marked text, not
        // what will be committed: the snapshot isn't used (epoch -1), the
        // committed text goes first.
        queue.append(QueuedRaw(input: input, textBefore: text, selectionBefore: selection, epoch: composing ? -1 : baseEpoch))
        guard !composing else { return [] }
        return pump(now: now)
    }

    /// Time passed: give up an unanswered edit, settle raw input the Mac
    /// showed nothing for.
    public mutating func tick(now: Double) -> [Effect] {
        var effects: [Effect] = []
        if let current = flight, now - current.sentAt > Self.inFlightTimeout {
            flight = nil
            queue.removeAll()
            shownNote = (.noAnswer, now + Self.noteDuration)
            effects += adoptMac()
            effects += pump(now: now)
        }
        if let current = raw, now - current.lastSentAt >= Self.rawTimeout {
            effects += settleRaw(now: now)
        }
        return effects
    }

    /// Watching stopped or the field closed: forget everything.
    public mutating func reset() {
        self = TextSyncReconciler()
    }

    // MARK: Rules

    private mutating func apply(_ state: FocusedTextState, now: Double) -> [Effect] {
        let previous = mac
        // A state older than the one shown (the same field, a lower
        // revision) is stale: never step back to it.
        if let previous, previous.field == state.field, state.readable.isReadable, previous.readable.isReadable,
           state.revision < previous.revision {
            return []
        }
        mac = state
        guard state.readable.isReadable, let window = state.window else {
            flight = nil
            raw = nil
            queue.removeAll()
            pendingSelect = nil
            let wasSynced = previous.map { $0.readable.isReadable && $0.window != nil } ?? false
            if wasSynced {
                text = ""
                selection = .caret(0)
                windowStart = 0
                return [.becameBlind]
            }
            return []
        }
        let wasSynced = previous.map { $0.readable.isReadable && $0.window != nil } ?? false
        if !wasSynced || previous?.field != state.field {
            flight = nil
            raw = nil
            queue.removeAll()
            pendingSelect = nil
            return adoptMac()
        }
        if var current = flight {
            if now - current.sentAt > Self.inFlightTimeout {
                flight = nil
                queue.removeAll()
                shownNote = (.noAnswer, now + Self.noteDuration)
                return adoptMac() + pump(now: now)
            }
            if let answered = current.answeredRevision, state.revision >= answered {
                current.answeredRevision = nil
                flight = current
                return settle(now: now)
            }
            return [] // keep the local echo while the Mac types
        }
        if var current = raw {
            var effects: [Effect] = []
            if text == current.base, !current.caretMoved {
                // Nothing typed here: show what the keys did as it happens
                // (the joystick moving the caret, a Tab's indent).
                effects += adoptMac()
                current.base = window.value
                current.windowStart = window.start
                raw = current
            }
            if now - current.lastSentAt >= Self.rawQuiet {
                effects += settleRaw(now: now)
            }
            return effects
        }
        if window.value == text, window.start == windowStart {
            // Our own edit's echo, or a selection change.
            let local = selection.shifted(by: windowStart)
            if let pending = pendingSelect {
                if state.selection == pending.range {
                    pendingSelect = nil
                    return []
                }
                if now - pending.at < Self.selectGrace { return [] }
                pendingSelect = nil
            }
            if state.selection != local {
                selection = relative(state.selection, in: window)
                return [.show(text: text, selection: selection)]
            }
            return []
        }
        return adoptMac()
    }

    /// The in-flight edit is done and its state has arrived.
    private mutating func settle(now: Double) -> [Effect] {
        guard let current = flight, let mac, let window = mac.window else {
            flight = nil
            return []
        }
        flight = nil
        let macText = window.value
        if text == current.expected {
            // Nothing waited.
            if macText == text, window.start == windowStart {
                return pump(now: now)
            }
            return adoptMac() + pump(now: now)
        }
        // Changes waited. Merge them with what the Mac did meanwhile when
        // the two don't touch.
        guard window.start == current.windowStart else {
            return macWins(now: now)
        }
        let macChange = TextEdit.between(current.expected, macText)
        if macChange.isEmpty {
            return pump(now: now)
        }
        let localChange = TextEdit.between(current.expected, text)
        guard let merged = Self.merge(base: current.expected, macChange, localChange) else {
            return macWins(now: now)
        }
        return adoptMerged(merged, macChange: macChange, localChange: localChange) + pump(now: now)
    }

    /// Raw input is done (its state came, or it timed out).
    private mutating func settleRaw(now: Double) -> [Effect] {
        guard let current = raw else { return [] }
        raw = nil
        guard let mac, let window = mac.window else { return [] }
        let macText = window.value
        if text == current.base {
            // Nothing typed here meanwhile.
            if macText == text, window.start == windowStart, !current.caretMoved {
                let shown = relative(mac.selection, in: window)
                if shown != selection {
                    selection = shown
                    return [.show(text: text, selection: selection)] + pump(now: now)
                }
                return pump(now: now)
            }
            if current.caretMoved, macText == text, window.start == windowStart {
                return pump(now: now) // the caret moved here goes out
            }
            return adoptMac() + pump(now: now)
        }
        // Text typed here while the keys went: it goes after what the
        // keys did (they were pressed first).
        guard window.start == current.windowStart else {
            return macWins(now: now)
        }
        let macChange = TextEdit.between(current.base, macText)
        if macChange.isEmpty { return pump(now: now) }
        let localChange = TextEdit.between(current.base, text)
        guard let merged = Self.merge(base: current.base, macChange, localChange, macFirstAtSamePoint: true) else {
            return macWins(now: now)
        }
        return adoptMerged(merged, macChange: macChange, localChange: localChange) + pump(now: now)
    }

    private mutating func adoptMerged(_ merged: String, macChange: TextEdit, localChange: TextEdit) -> [Effect] {
        let shift = localChange.range.start >= macChange.range.end
            ? macChange.replacement.utf16.count - macChange.range.length : 0
        text = merged
        selection = selection.shifted(by: shift)
        baseEpoch += 1
        return [.show(text: text, selection: selection)]
    }

    private mutating func macWins(now: Double) -> [Effect] {
        queue.removeAll()
        macWinsUntil = now + Self.macWinsDuration
        return adoptMac() + [.conflict]
    }

    /// Sends what's next, in order: the text typed before the first queued
    /// key, the caret where the field had it, the keys; then any other text
    /// and a moved caret. Nothing while an edit is in flight; while raw
    /// input is out, only more raw input pressed with nothing typed.
    private mutating func pump(now: Double) -> [Effect] {
        guard !composing, isSynced, flight == nil, let mac, let window = mac.window, window.start == windowStart else { return [] }
        if var current = raw {
            guard text == current.base, !current.caretMoved else { return [] }
            var effects: [Effect] = []
            while let first = queue.first, first.epoch != baseEpoch || first.textBefore == current.base {
                queue.removeFirst()
                effects.append(.sendRaw(first.input))
                current.lastSentAt = now
            }
            raw = current
            return effects
        }
        if let first = queue.first {
            let snapshotValid = first.epoch == baseEpoch
            let target = snapshotValid ? first.textBefore : text
            if target != window.value {
                return sendEdit(toward: target, now: now)
            }
            var effects: [Effect] = []
            // The caret where the field had it when the key was pressed.
            let caret = (snapshotValid ? first.selectionBefore : selection).shifted(by: windowStart)
            if caret != mac.selection {
                effects.append(.sendSelect(TextSelectRequest(field: mac.field, baseRevision: mac.revision, range: caret)))
            }
            pendingSelect = nil
            // Every key pressed with the same text before it goes together.
            while let next = queue.first, next.epoch != baseEpoch || next.textBefore == window.value {
                queue.removeFirst()
                effects.append(.sendRaw(next.input))
            }
            raw = RawFlight(base: window.value, windowStart: window.start, lastSentAt: now)
            return effects
        }
        if text != window.value {
            return sendEdit(toward: text, now: now)
        }
        let absolute = selection.shifted(by: windowStart)
        guard absolute != mac.selection, pendingSelect?.range != absolute else { return [] }
        pendingSelect = (absolute, now)
        return [.sendSelect(TextSelectRequest(field: mac.field, baseRevision: mac.revision, range: absolute))]
    }

    /// Sends the difference between the Mac's text and `target` as one
    /// edit.
    private mutating func sendEdit(toward target: String, now: Double) -> [Effect] {
        guard let mac, let window = mac.window, window.start == windowStart else { return [] }
        var edit = TextEdit.between(window.value, target)
        var expected = target
        if edit.replacement.utf8.count > TextSyncPolicy.maxReplacementBytes {
            // Too long for one message: send the first part; the rest goes
            // as the next edit once this one is answered.
            let part = TextChunker.chunks(edit.replacement, maxBytes: TextSyncPolicy.maxReplacementBytes).first ?? ""
            edit.replacement = part
            expected = edit.applied(to: window.value) ?? target
        }
        let units = Array(window.value.utf16)
        guard let context = TextEditContext.make(units: units, range: edit.range) else { return [] }
        let request = TextEditRequest(
            field: mac.field,
            request: nextRequest,
            baseRevision: mac.revision,
            range: edit.range.shifted(by: window.start),
            replacement: edit.replacement,
            context: context
        )
        nextRequest &+= 1
        if nextRequest == 0 { nextRequest = 1 }
        flight = Flight(request: request.request, expected: expected, windowStart: window.start, sentAt: now)
        pendingSelect = nil
        return [.sendEdit(request)]
    }

    /// Show the Mac's text and selection.
    private mutating func adoptMac() -> [Effect] {
        guard let mac, mac.readable.isReadable, let window = mac.window else { return [] }
        if text != window.value || windowStart != window.start { baseEpoch += 1 }
        text = window.value
        windowStart = window.start
        selection = relative(mac.selection, in: window)
        return [.show(text: text, selection: selection)]
    }

    private func relative(_ range: TextRange, in window: TextWindow) -> TextRange {
        let length = window.length
        let start = min(max(0, range.start - window.start), length)
        let end = min(max(start, range.end - window.start), length)
        return TextRange(start: start, length: end - start)
    }

    /// `base` with both edits applied, when they don't overlap or touch.
    /// Two insertions at the same point count as touching, unless
    /// `macFirstAtSamePoint` (the Mac's came from keys pressed before the
    /// local text was typed): then the Mac's goes first.
    static func merge(base: String, _ mac: TextEdit, _ local: TextEdit, macFirstAtSamePoint: Bool = false) -> String? {
        if macFirstAtSamePoint, mac.range.length == 0, local.range.length == 0, mac.range.start == local.range.start {
            return TextUnits.replacing(mac.range, in: base, with: mac.replacement + local.replacement)
        }
        let (first, second) = mac.range.start <= local.range.start ? (mac, local) : (local, mac)
        guard first.range.end < second.range.start else { return nil }
        guard let afterSecond = second.applied(to: base) else { return nil }
        return first.applied(to: afterSecond)
    }
}
