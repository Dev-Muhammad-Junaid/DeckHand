//
//  FocusedTextState.swift
//  PixelHandCore
//
//  Live text sync (protocol 17, `Product/Design/RD-live-sync-and-caret.md`
//  §4): the Mac's focused field as text (a window around the caret, its
//  revision, whether it can be read and edited), and what a remote sends to
//  change it (anchored edits and selections) or move its caret.
//
//  Every offset is in UTF-16 units (`NSRange` style) and **absolute in the
//  field**, not relative to the window, so the Mac can check an edit
//  against the field's current text.
//

import Foundation

/// A range of UTF-16 units: `start` and `length`, absolute in the field.
public struct TextRange: Codable, Sendable, Hashable {
    public var start: Int
    public var length: Int

    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }

    /// A caret (no selection) at `offset`.
    public static func caret(_ offset: Int) -> TextRange { TextRange(start: offset, length: 0) }

    public var end: Int { start + length }
    public var isCaret: Bool { length == 0 }

    /// The same range moved by `delta` units.
    public func shifted(by delta: Int) -> TextRange { TextRange(start: start + delta, length: length) }
}

/// Which field a state, edit or selection belongs to: opaque, made by the
/// Mac from the app's process, the element and a focus epoch, so a remote
/// can't aim an edit at a field that has since lost focus.
public struct FieldToken: Codable, Sendable, Hashable {
    public var id: UInt32

    public init(_ id: UInt32) { self.id = id }

    public init(from decoder: Decoder) throws {
        id = try decoder.singleValueContainer().decode(UInt32.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }

    /// No field (nothing focused, or not readable).
    public static let none = FieldToken(0)
}

/// Whether the Mac can show the focused field's text, and if not, why.
public enum TextReadability: Codable, Sendable, Hashable {
    /// A native, non-secure field on an unlocked Mac: `window` holds text.
    case yes
    /// A password field, or secure event input is on (any app's password
    /// prompt, `sudo` in Terminal). Keys still go; nothing is read, and
    /// edits and selections are refused.
    case secure
    /// Web or Electron content (Phase 2 makes this a per-app opt-in).
    case webOff(app: String)
    /// An app that doesn't share its text (Chromium browsers).
    case unsupported(app: String)
    /// A terminal: keys only, never its scrollback.
    case terminal
    /// No text field has focus.
    case noField
    /// The Mac is locked (`LockPolicy.withholdsFocus`).
    case locked

    public var isReadable: Bool { self == .yes }

    /// The dim line the iPad's field shows when it can't sync, in plain
    /// words. `nil` when readable.
    public var reasonLine: String? {
        switch self {
        case .yes: nil
        case .secure: "Password field: the text stays on the Mac"
        case let .webOff(app): "Web text is off for \(app)"
        case let .unsupported(app): "\(app) doesn't share its text"
        case .terminal: "Terminal: keys only"
        case .noField: "No text field"
        case .locked: "Mac is locked"
        }
    }
}

/// The text the Mac sends: a window of the field around the caret.
public struct TextWindow: Codable, Sendable, Hashable {
    /// The window's offset in the field (UTF-16 units).
    public var start: Int
    /// At most `TextSyncPolicy.windowLength` UTF-16 units of the field.
    public var value: String

    public init(start: Int, value: String) {
        self.start = start
        self.value = value
    }

    public var length: Int { value.utf16.count }
    public var end: Int { start + length }
}

/// `system.textState`: the focused field as text (Mac → remote, while a
/// remote watches with `wantsText`).
public struct FocusedTextState: Codable, Sendable, Hashable {
    public var field: FieldToken
    /// Goes up on every value or selection change the Mac sees for
    /// `field`; starts again at 1 for a new field.
    public var revision: UInt32
    public var readable: TextReadability
    /// `nil` unless `readable == .yes`.
    public var window: TextWindow?
    /// The field's length in UTF-16 units (0 when not readable).
    public var length: Int
    /// The caret or selection, absolute in the field.
    public var selection: TextRange
    /// Accessibility can set the selection (else the Mac uses arrow keys).
    public var canSetSelection: Bool
    /// The Mac takes `textEdit` for this field.
    public var canEdit: Bool

    public init(
        field: FieldToken,
        revision: UInt32,
        readable: TextReadability,
        window: TextWindow?,
        length: Int,
        selection: TextRange,
        canSetSelection: Bool,
        canEdit: Bool
    ) {
        self.field = field
        self.revision = revision
        self.readable = readable
        self.window = window
        self.length = length
        self.selection = selection
        self.canSetSelection = canSetSelection
        self.canEdit = canEdit
    }

    /// A state with no text: `readable` says why.
    public static func unreadable(_ reason: TextReadability, field: FieldToken = .none, revision: UInt32 = 0) -> FocusedTextState {
        FocusedTextState(
            field: field,
            revision: revision,
            readable: reason,
            window: nil,
            length: 0,
            selection: .caret(0),
            canSetSelection: false,
            canEdit: false
        )
    }
}

/// Hashes of the text an edit was based on, so the Mac applies it only
/// where that text still is (`TextEditCheck`).
public struct TextEditContext: Codable, Sendable, Hashable {
    /// FNV-1a of the `beforeLength` units before the range and the units
    /// the edit replaces.
    public var beforeHash: UInt32
    public var beforeLength: Int
    /// FNV-1a of the `afterLength` units after the range.
    public var afterHash: UInt32
    public var afterLength: Int

    public init(beforeHash: UInt32, beforeLength: Int, afterHash: UInt32, afterLength: Int) {
        self.beforeHash = beforeHash
        self.beforeLength = beforeLength
        self.afterHash = afterHash
        self.afterLength = afterLength
    }
}

/// `input.textEdit`: replace `range` of revision `baseRevision` with
/// `replacement`. The Mac selects the range and **types** the replacement;
/// it never sets `AXValue`.
public struct TextEditRequest: Codable, Sendable, Hashable {
    public var field: FieldToken
    /// The remote's own number for this edit, echoed in `TextEditResult`.
    public var request: UInt32
    public var baseRevision: UInt32
    public var range: TextRange
    /// At most `TextSyncPolicy.maxReplacementBytes` UTF-8 bytes.
    public var replacement: String
    public var context: TextEditContext

    public init(field: FieldToken, request: UInt32, baseRevision: UInt32, range: TextRange, replacement: String, context: TextEditContext) {
        self.field = field
        self.request = request
        self.baseRevision = baseRevision
        self.range = range
        self.replacement = replacement
        self.context = context
    }
}

/// `input.textSelect`: put the Mac's caret or selection at `range`.
public struct TextSelectRequest: Codable, Sendable, Hashable {
    public var field: FieldToken
    public var baseRevision: UInt32
    public var range: TextRange

    public init(field: FieldToken, baseRevision: UInt32, range: TextRange) {
        self.field = field
        self.baseRevision = baseRevision
        self.range = range
    }
}

/// Why the Mac refused an edit outright.
public enum TextEditRefusal: String, Codable, Sendable, Hashable, CaseIterable {
    /// A password field or secure event input.
    case secure
    case locked
    /// The field the edit names no longer has focus.
    case fieldChanged
    /// The field can't be read or edited (web, terminal, read-only).
    case notEditable
    /// Out of the field's bounds or past the size cap.
    case invalid
}

public enum TextEditOutcome: Codable, Sendable, Hashable {
    /// Typed where the remote said.
    case applied
    /// The Mac's text moved (someone typed there); the edit was applied
    /// where its context was found.
    case rebased
    /// The text the edit was based on is gone: nothing typed. The Mac's
    /// current state follows (MAC WINS).
    case conflict
    case refused(reason: TextEditRefusal)
}

/// `system.textEditResult`: the answer to one `textEdit` (Mac → remote).
/// The Mac sends its `textState` for the result's revision first.
public struct TextEditResult: Codable, Sendable, Hashable {
    public var field: FieldToken
    public var request: UInt32
    public var outcome: TextEditOutcome
    /// The field's revision after the edit (or now, when not applied).
    public var revision: UInt32

    public init(field: FieldToken, request: UInt32, outcome: TextEditOutcome, revision: UInt32) {
        self.field = field
        self.request = request
        self.outcome = outcome
        self.revision = revision
    }
}

/// `input.caretMove`: arrow presses the Mac coalesces (the arrow joystick
/// and the blind trackpad). Refused under secure input, without refusing
/// every key.
public struct CaretMove: Codable, Sendable, Hashable {
    public enum Direction: String, Codable, Sendable, Hashable, CaseIterable {
        case left, right, up, down
    }

    public enum Unit: String, Codable, Sendable, Hashable, CaseIterable {
        /// ←/→ (or ↑/↓ for `.line` semantics when vertical).
        case character
        /// ⌥←/⌥→.
        case word
        /// ↑/↓.
        case line
        /// ⌥↑/⌥↓.
        case paragraph
    }

    public var direction: Direction
    public var unit: Unit
    /// 1…`TextSyncPolicy.maxCaretMoveCount` presses.
    public var count: UInt8
    /// Hold ⇧ (extend the selection).
    public var extend: Bool

    public init(direction: Direction, unit: Unit, count: UInt8, extend: Bool) {
        self.direction = direction
        self.unit = unit
        self.count = count
        self.extend = extend
    }

    /// The key chord for one press, in `KeyTable` names.
    public var chord: [String] {
        var keys: [String] = []
        if extend { keys.append("shift") }
        if unit == .word || unit == .paragraph { keys.append("option") }
        keys.append(direction.rawValue)
        return keys
    }
}
