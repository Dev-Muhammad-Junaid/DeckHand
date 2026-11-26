//
//  TextSyncPolicy.swift
//  PixelHandCore
//
//  Live text sync, the Mac's rules (protocol 17,
//  `Product/Design/RD-live-sync-and-caret.md` §1.1, §1.3, §3 Phase 1),
//  kept pure so they're tested here:
//
//  - which fields may be read at all (`readability`): never while locked,
//    never a password field or under secure event input, never web or
//    Electron content (Phase 2 opt-in), never a terminal's scrollback;
//  - the window of text around the caret (`window`), which stays put
//    until the caret comes within `slideMargin` of an edge;
//  - pacing observer notifications to 30 a second (`TextSyncPacer`:
//    leading edge, at most one per 33 ms, one trailing);
//  - field tokens and revisions (`TextRevisionTracker`);
//  - moving the caret with arrow keys where Accessibility can't set the
//    selection (`arrowChords`), and coalescing `caretMove`.
//

import Foundation

public enum TextSyncPolicy {
    /// Most UTF-16 units sent around the caret (OT-13's window).
    public static let windowLength = FocusReading.maxTextLength
    /// The window slides when the caret comes this close to one of its
    /// edges (and the field goes on past that edge).
    public static let slideMargin = 150
    /// Largest replacement in one `textEdit` (UTF-8 bytes).
    public static let maxReplacementBytes = TypingPolicy.maxMessageBytes
    /// Replacements longer than this (characters) are typed as Unicode
    /// strings, 20 units an event, not key by key: a long paste takes a
    /// fraction of a second instead of several.
    public static let fastTypingThreshold = 200
    /// Notifications are coalesced to this rate (seconds between sends).
    public static let notificationInterval = 1.0 / 30.0
    /// A text area this long without `AXInsertionPointLineNumber` is taken
    /// for a terminal's scrollback.
    public static let terminalLikeLength = 100_000
    /// Most arrow presses one selection or `caretMove` may cost.
    public static let maxArrowPresses = 2_000
    /// Most presses in one `caretMove`.
    public static let maxCaretMoveCount: UInt8 = 60

    /// Terminals: keys only, never text (`RD` §1.1, "terminals are keys
    /// only"). App-side list; Loom knows nothing of it.
    public static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "org.alacritty",
        "co.zeit.hyper",
    ]

    /// Chromium browsers: their text needs `AXEnhancedUserInterface`,
    /// which Pixel Hand never sets.
    public static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "com.operasoftware.Opera",
    ]

    // MARK: Readability

    /// Whether the focused element's text may be read, and if not why.
    /// Checked before any value is read. Secure input wins over
    /// everything but the lock.
    public static func readability(
        lock: MacLockState,
        secureInput: Bool,
        hasFocus: Bool,
        axRole: String?,
        axSubrole: String?,
        inWebContent: Bool,
        appName: String?,
        bundleID: String?,
        characterCount: Int?,
        hasInsertionPointLine: Bool
    ) -> TextReadability {
        if lock.isLocked { return .locked }
        if secureInput { return .secure }
        guard hasFocus else { return .noField }
        if FocusReading.isSecure(axRole: axRole, axSubrole: axSubrole) { return .secure }
        if let bundleID, terminalBundleIDs.contains(bundleID) { return .terminal }
        let role = FocusReading.role(axRole: axRole, axSubrole: axSubrole)
        let app = appName ?? "this app"
        if inWebContent || role == .webArea {
            if let bundleID, chromiumBundleIDs.contains(bundleID) { return .unsupported(app: app) }
            return .webOff(app: app)
        }
        switch role {
        case .textField, .comboBox:
            return .yes
        case .textArea:
            if let characterCount, characterCount > terminalLikeLength, !hasInsertionPointLine {
                return .terminal
            }
            return .yes
        case .webArea, .other:
            return .noField
        }
    }

    // MARK: The window

    /// The window to read from a field of `fieldLength` units for
    /// `selection`: the whole field when it fits; else `windowLength`
    /// units, kept at `previousStart` while the selection stays at least
    /// `slideMargin` from both edges (or the edge is the field's own), and
    /// recentred (a third before the caret) when it doesn't.
    public static func window(fieldLength: Int, selection: TextRange, previousStart: Int?) -> TextRange {
        let length = max(0, fieldLength)
        guard length > windowLength else { return TextRange(start: 0, length: length) }
        let selStart = min(max(0, selection.start), length)
        let selEnd = min(max(selStart, selection.end), length)
        if let previousStart {
            let start = min(max(0, previousStart), length - windowLength)
            let end = start + windowLength
            let roomBefore = start == 0 || selStart - start >= slideMargin
            let roomAfter = end == length || end - selEnd >= slideMargin
            if selStart >= start, selEnd <= end, roomBefore, roomAfter {
                return TextRange(start: start, length: windowLength)
            }
        }
        let recentred = FocusReading.textWindow(count: length, selectionStart: selStart, limit: windowLength)
        return TextRange(start: recentred.location, length: recentred.length)
    }

    // MARK: Caret by arrow keys

    /// The arrow chords that move a caret or selection `from` to `to`
    /// (absolute) through `window` (the field's text from
    /// `windowStart`), for fields whose selection Accessibility can't
    /// set. A selection collapses with ← first, then ←/→ per character,
    /// then ⇧→ per selected character. `nil` when a position is outside
    /// the window, cuts a character, or would take more than
    /// `maxArrowPresses`.
    public static func arrowChords(window: String, windowStart: Int, from: TextRange, to: TextRange) -> [[String]]? {
        let windowLength = window.utf16.count
        func relative(_ offset: Int) -> Int? {
            let r = offset - windowStart
            return r >= 0 && r <= windowLength ? r : nil
        }
        guard let fromStart = relative(from.start), let fromEnd = relative(from.end),
              let toStart = relative(to.start), let toEnd = relative(to.end),
              TextUnits.isCharacterBoundary(fromEnd, in: window) else { return nil }
        var chords: [[String]] = []
        if fromEnd > fromStart { chords.append(["left"]) }
        let caret = fromStart
        if toStart > caret {
            guard let n = TextUnits.characterCount(TextRange(start: caret, length: toStart - caret), in: window) else { return nil }
            chords += Array(repeating: ["right"], count: n)
        } else if toStart < caret {
            guard let n = TextUnits.characterCount(TextRange(start: toStart, length: caret - toStart), in: window) else { return nil }
            chords += Array(repeating: ["left"], count: n)
        }
        if toEnd > toStart {
            guard let n = TextUnits.characterCount(TextRange(start: toStart, length: toEnd - toStart), in: window) else { return nil }
            chords += Array(repeating: ["shift", "right"], count: n)
        }
        guard chords.count <= maxArrowPresses else { return nil }
        return chords
    }

    /// `caretMove` as chords, its count clamped to 1…`maxCaretMoveCount`.
    public static func chords(for move: CaretMove) -> [[String]] {
        let count = Int(min(max(move.count, 1), maxCaretMoveCount))
        return Array(repeating: move.chord, count: count)
    }

    /// Whether a `caretMove` may run: never under secure input (it would
    /// move through a password), never while locked.
    public static func allowsCaretMove(secureInput: Bool, lock: MacLockState) -> Bool {
        !secureInput && !lock.isLocked
    }
}

/// Paces observer notifications: the first goes at once (leading edge),
/// then at most one every `interval` while they keep coming, plus one
/// trailing after the last. Keystroke-rate changes never queue up.
public struct TextSyncPacer: Sendable, Equatable {
    public enum Action: Equatable, Sendable {
        /// Read and send now.
        case sendNow
        /// Schedule `fire` at this time.
        case sendAt(Double)
        /// A send is already scheduled.
        case wait
    }

    public var interval: Double
    public private(set) var lastSend: Double?
    public private(set) var trailingPending = false

    public init(interval: Double = TextSyncPolicy.notificationInterval) {
        self.interval = interval
    }

    /// A notification arrived at `now`.
    public mutating func note(now: Double) -> Action {
        if trailingPending { return .wait }
        if let lastSend, now - lastSend < interval {
            trailingPending = true
            return .sendAt(lastSend + interval)
        }
        lastSend = now
        return .sendNow
    }

    /// The scheduled time came: whether to send (a trailing update).
    public mutating func fire(now: Double) -> Bool {
        guard trailingPending else { return false }
        trailingPending = false
        lastSend = now
        return true
    }

    /// Forget everything (a new field or watching stopped).
    public mutating func reset() {
        lastSend = nil
        trailingPending = false
    }
}

/// Field tokens and revisions on the Mac. A new focused element (or a
/// return to one after another) gets a new token; every reading that
/// differs from the last in text or selection bumps the revision.
public struct TextRevisionTracker: Sendable, Equatable {
    /// What a reading is compared on.
    public struct Reading: Sendable, Hashable {
        public var readable: TextReadability
        public var window: TextWindow?
        public var length: Int
        public var selection: TextRange
        public var canSetSelection: Bool
        public var canEdit: Bool

        public init(readable: TextReadability, window: TextWindow?, length: Int, selection: TextRange, canSetSelection: Bool, canEdit: Bool) {
            self.readable = readable
            self.window = window
            self.length = length
            self.selection = selection
            self.canSetSelection = canSetSelection
            self.canEdit = canEdit
        }
    }

    public private(set) var token: FieldToken = .none
    public private(set) var revision: UInt32 = 0
    private var elementKey: UInt64?
    private var epoch: UInt32 = 0
    private var last: Reading?

    public init() {}

    /// Feeds a reading of the element `elementKey` (the Mac's hash of the
    /// process and the element; `nil` for no field). Returns the state to
    /// send and whether it changed since the last one.
    public mutating func observe(elementKey: UInt64?, reading: Reading) -> (state: FocusedTextState, changed: Bool) {
        var changed = false
        if elementKey != self.elementKey {
            self.elementKey = elementKey
            epoch &+= 1
            token = elementKey.map { FieldToken(Self.tokenID(key: $0, epoch: epoch)) } ?? .none
            revision = 0
            last = nil
        }
        if reading != last {
            last = reading
            revision &+= 1
            if revision == 0 { revision = 1 }
            changed = true
        }
        let state = FocusedTextState(
            field: token,
            revision: revision,
            readable: reading.readable,
            window: reading.window,
            length: reading.length,
            selection: reading.selection,
            canSetSelection: reading.canSetSelection,
            canEdit: reading.canEdit
        )
        return (state, changed)
    }

    /// Forget the field (watching stopped): the next reading starts a new
    /// token.
    public mutating func reset() {
        elementKey = nil
        token = .none
        revision = 0
        last = nil
    }

    static func tokenID(key: UInt64, epoch: UInt32) -> UInt32 {
        var units: [UInt16] = []
        for shift in stride(from: 0, to: 64, by: 16) { units.append(UInt16(truncatingIfNeeded: key >> UInt64(shift))) }
        units.append(UInt16(truncatingIfNeeded: epoch))
        units.append(UInt16(truncatingIfNeeded: epoch >> 16))
        let id = TextHash.fnv1a(units)
        return id == 0 ? 1 : id
    }
}

/// Log lines for live text sync. The field's text never reaches a log, a
/// diagnostic or a crash report: these name revisions, offsets and sizes
/// only (`TextSyncLogTests` checks every message kind).
public enum TextSyncLog {
    public static func describe(_ state: FocusedTextState) -> String {
        "textState field \(state.field.id) rev \(state.revision) \(reason(state.readable)) len \(state.length) window \(state.window.map { "\($0.start)+\($0.length)" } ?? "none") sel \(state.selection.start)+\(state.selection.length)"
    }

    public static func describe(_ edit: TextEditRequest) -> String {
        "textEdit #\(edit.request) field \(edit.field.id) rev \(edit.baseRevision) range \(edit.range.start)+\(edit.range.length) → \(edit.replacement.utf16.count) units"
    }

    public static func describe(_ select: TextSelectRequest) -> String {
        "textSelect field \(select.field.id) rev \(select.baseRevision) range \(select.range.start)+\(select.range.length)"
    }

    public static func describe(_ result: TextEditResult) -> String {
        "textEditResult #\(result.request) field \(result.field.id) \(outcome(result.outcome)) rev \(result.revision)"
    }

    /// The reason's name; an app name is left out (it isn't text, but it
    /// isn't needed either).
    public static func reason(_ readable: TextReadability) -> String {
        switch readable {
        case .yes: "yes"
        case .secure: "secure"
        case .webOff: "webOff"
        case .unsupported: "unsupported"
        case .terminal: "terminal"
        case .noField: "noField"
        case .locked: "locked"
        }
    }

    static func outcome(_ outcome: TextEditOutcome) -> String {
        switch outcome {
        case .applied: "applied"
        case .rebased: "rebased"
        case .conflict: "conflict"
        case let .refused(reason): "refused(\(reason.rawValue))"
        }
    }
}
