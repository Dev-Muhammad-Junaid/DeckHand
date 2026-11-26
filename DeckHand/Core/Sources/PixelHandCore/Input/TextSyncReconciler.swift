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
//  - `conflict`: the field shows the Mac's text and the badge says MAC
//    WINS for 1.4 s.
//  - While an input method composes (marked text) nothing goes out and the
//    Mac's updates are held, so a Mac update never yanks the composition.
//  - A caret moved here (tap, the space-bar trackpad, selection handles)
//    goes out as `textSelect`; the Mac's states that still show the old
//    selection are ignored for `selectGrace`.
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

public struct TextSyncReconciler: Sendable {
    /// What the field must do.
    public enum Effect: Equatable, Sendable {
        case sendEdit(TextEditRequest)
        case sendSelect(TextSelectRequest)
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

    private struct Flight: Sendable {
        var request: UInt32
        /// The field's text when it went (what the Mac should end up with).
        var expected: String
        var windowStart: Int
        var sentAt: Double
        /// The answer came before the state for its revision.
        var answeredRevision: UInt32?
        var outcome: TextEditOutcome?
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
    private var heldState: FocusedTextState?
    private var pendingSelect: (range: TextRange, at: Double)?
    private var macWinsUntil = -Double.infinity
    private var nextRequest: UInt32 = 1

    public init() {}

    /// The field shows the Mac's text (not the blind buffer).
    public var isSynced: Bool {
        guard let mac else { return false }
        return mac.readable.isReadable && mac.window != nil
    }

    /// An edit waits for its answer.
    public var isSending: Bool { flight != nil }

    /// Why the field can't sync, when it can't.
    public var reasonLine: String? {
        guard let mac else { return nil }
        return mac.readable.reasonLine
    }

    public func badge(now: Double) -> SyncBadge {
        guard isSynced else { return .blind }
        if now < macWinsUntil { return .macWins }
        return flight != nil ? .sending : .sync
    }

    /// When the badge changes on its own (MAC WINS ends), so the view can
    /// refresh then.
    public func badgeDeadline(now: Double) -> Double? {
        now < macWinsUntil ? macWinsUntil : nil
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
            macWinsUntil = now + Self.macWinsDuration
            return adoptMac() + [.conflict]
        case .refused:
            flight = nil
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
        var effects: [Effect] = []
        if flight == nil {
            effects += sendNext(now: now)
        }
        if wasComposing, let held = heldState {
            heldState = nil
            effects += apply(held, now: now)
        }
        return effects
    }

    /// The person moved the caret or selection (a tap, the space-bar
    /// trackpad, selection handles).
    public mutating func localSelection(_ newSelection: TextRange, now: Double) -> [Effect] {
        selection = newSelection
        guard isSynced, !composing, flight == nil, let mac, let window = mac.window,
              text == window.value, window.start == windowStart else { return [] }
        let absolute = newSelection.shifted(by: windowStart)
        guard absolute != mac.selection else {
            pendingSelect = nil
            return []
        }
        pendingSelect = (absolute, now)
        return [.sendSelect(TextSelectRequest(field: mac.field, baseRevision: mac.revision, range: absolute))]
    }

    /// Watching stopped or the field closed: forget everything.
    public mutating func reset() {
        self = TextSyncReconciler()
    }

    // MARK: Rules

    private mutating func apply(_ state: FocusedTextState, now: Double) -> [Effect] {
        let previous = mac
        mac = state
        guard state.readable.isReadable, let window = state.window else {
            flight = nil
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
            pendingSelect = nil
            return adoptMac()
        }
        if var current = flight {
            if now - current.sentAt > Self.inFlightTimeout {
                flight = nil
                return adoptMac()
            }
            if let answered = current.answeredRevision, state.revision >= answered {
                current.answeredRevision = nil
                flight = current
                return settle(now: now)
            }
            return [] // keep the local echo while the Mac types
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
                return reconcileSelection(now: now)
            }
            return adoptMac()
        }
        // Changes waited. Merge them with what the Mac did meanwhile when
        // the two don't touch.
        guard window.start == current.windowStart else {
            macWinsUntil = now + Self.macWinsDuration
            return adoptMac() + [.conflict]
        }
        let macChange = TextEdit.between(current.expected, macText)
        let localChange = TextEdit.between(current.expected, text)
        if macChange.isEmpty {
            return sendNext(now: now)
        }
        guard let merged = Self.merge(base: current.expected, macChange, localChange) else {
            macWinsUntil = now + Self.macWinsDuration
            return adoptMac() + [.conflict]
        }
        let shift = localChange.range.start >= macChange.range.end
            ? macChange.replacement.utf16.count - macChange.range.length : 0
        text = merged
        selection = selection.shifted(by: shift)
        return [.show(text: text, selection: selection)] + sendNext(now: now)
    }

    /// After an echo: a caret the person moved meanwhile goes to the Mac.
    private mutating func reconcileSelection(now: Double) -> [Effect] {
        guard let mac else { return [] }
        let absolute = selection.shifted(by: windowStart)
        guard absolute != mac.selection else { return [] }
        pendingSelect = (absolute, now)
        return [.sendSelect(TextSelectRequest(field: mac.field, baseRevision: mac.revision, range: absolute))]
    }

    /// Sends the field's difference from the Mac's text as one edit.
    private mutating func sendNext(now: Double) -> [Effect] {
        guard let mac, let window = mac.window, window.start == windowStart else { return [] }
        guard text != window.value else { return reconcileSelection(now: now) }
        var edit = TextEdit.between(window.value, text)
        var expected = text
        if edit.replacement.utf8.count > TextSyncPolicy.maxReplacementBytes {
            // Too long for one message: send the first part; the rest goes
            // as the next edit once this one is answered.
            let part = TextChunker.chunks(edit.replacement, maxBytes: TextSyncPolicy.maxReplacementBytes).first ?? ""
            edit.replacement = part
            expected = edit.applied(to: window.value) ?? text
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
    /// Two insertions at the same point count as touching.
    static func merge(base: String, _ a: TextEdit, _ b: TextEdit) -> String? {
        let (first, second) = a.range.start <= b.range.start ? (a, b) : (b, a)
        guard first.range.end < second.range.start else { return nil }
        guard let afterSecond = second.applied(to: base) else { return nil }
        return first.applied(to: afterSecond)
    }
}
