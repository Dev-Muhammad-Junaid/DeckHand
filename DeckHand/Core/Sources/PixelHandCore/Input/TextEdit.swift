//
//  TextEdit.swift
//  PixelHandCore
//
//  Live text sync (protocol 17): the maths both sides share.
//
//  - `TextEdit.between(old, new)`: the smallest range edit (common prefix
//    and suffix) between two texts, counted in whole characters so it
//    never splits an emoji, a flag or a combining sequence, and reported
//    in UTF-16 units (the Mac's `NSRange` offsets). Autocorrect replacing
//    "teh" three words back becomes one 3-unit range, not 40 Backspaces.
//  - `TextHash`: FNV-1a over UTF-16 units, the same on every platform.
//  - `TextEditContext.make`: what an edit was based on (`TextEditRequest`).
//  - `TextEditCheck`: the Mac's decision for an incoming edit: apply where
//    the remote said, rebase to where its context moved, conflict, or
//    refuse.
//

import Foundation

/// One range edit: replace `range` (UTF-16 units of the old text) with
/// `replacement`.
public struct TextEdit: Equatable, Sendable {
    public var range: TextRange
    public var replacement: String

    public init(range: TextRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    public var isEmpty: Bool { range.length == 0 && replacement.isEmpty }

    /// The edit that turns `old` into `new`: everything they share at the
    /// start and at the end stays. Characters are compared by their exact
    /// UTF-16 units (not canonical equivalence), so offsets always match
    /// what the Mac counts.
    public static func between(_ old: String, _ new: String) -> TextEdit {
        let o = Array(old)
        let n = Array(new)
        func same(_ a: Character, _ b: Character) -> Bool { a.utf16.elementsEqual(b.utf16) }
        var prefix = 0
        while prefix < o.count, prefix < n.count, same(o[prefix], n[prefix]) { prefix += 1 }
        var suffix = 0
        while suffix < o.count - prefix, suffix < n.count - prefix,
              same(o[o.count - 1 - suffix], n[n.count - 1 - suffix]) {
            suffix += 1
        }
        let start = o[..<prefix].reduce(0) { $0 + $1.utf16.count }
        let removed = o[prefix..<(o.count - suffix)].reduce(0) { $0 + $1.utf16.count }
        return TextEdit(
            range: TextRange(start: start, length: removed),
            replacement: String(n[prefix..<(n.count - suffix)])
        )
    }

    /// `text` with this edit applied, or `nil` when the range is outside
    /// it.
    public func applied(to text: String) -> String? {
        TextUnits.replacing(range, in: text, with: replacement)
    }

    /// The caret after the edit: just after the replacement.
    public var caretAfter: Int { range.start + replacement.utf16.count }
}

/// UTF-16 helpers.
public enum TextUnits {
    /// The units of `range` in `text`, or `nil` when out of bounds.
    public static func substring(_ text: String, _ range: TextRange) -> String? {
        let units = Array(text.utf16)
        guard range.start >= 0, range.length >= 0, range.end <= units.count else { return nil }
        return String(decoding: units[range.start..<range.end], as: UTF16.self)
    }

    /// `text` with `range` replaced, or `nil` when out of bounds.
    public static func replacing(_ range: TextRange, in text: String, with replacement: String) -> String? {
        var units = Array(text.utf16)
        guard range.start >= 0, range.length >= 0, range.end <= units.count else { return nil }
        units.replaceSubrange(range.start..<range.end, with: Array(replacement.utf16))
        return String(decoding: units, as: UTF16.self)
    }

    /// Whether `offset` falls between two characters of `text` (not inside
    /// a surrogate pair or a grapheme cluster).
    public static func isCharacterBoundary(_ offset: Int, in text: String) -> Bool {
        if offset == 0 { return true }
        var units = 0
        for character in text {
            if units == offset { return true }
            if units > offset { return false }
            units += character.utf16.count
        }
        return units == offset
    }

    /// The number of characters in `range` of `text` (what one arrow press
    /// per character covers on the Mac), or `nil` when the range is out of
    /// bounds or cuts a character.
    public static func characterCount(_ range: TextRange, in text: String) -> Int? {
        guard range.start >= 0, range.length >= 0,
              isCharacterBoundary(range.start, in: text), isCharacterBoundary(range.end, in: text) else { return nil }
        var units = 0
        var count = 0
        for character in text {
            if units >= range.end { break }
            if units >= range.start { count += 1 }
            units += character.utf16.count
        }
        return range.end <= units || range.length == 0 ? count : nil
    }

    /// A window read from the field with `start`: a leading low surrogate
    /// and a trailing high surrogate (a pair cut by the window's edge) are
    /// dropped, and `start` moves with them.
    public static func aligned(_ units: [UInt16], start: Int) -> (start: Int, units: [UInt16]) {
        var lower = 0
        var upper = units.count
        if lower < upper, UTF16.isTrailSurrogate(units[lower]) { lower += 1 }
        if upper > lower, UTF16.isLeadSurrogate(units[upper - 1]) { upper -= 1 }
        return (start + lower, Array(units[lower..<upper]))
    }
}

/// FNV-1a (32-bit) over UTF-16 units: short, stable across platforms.
public enum TextHash {
    public static func fnv1a<S: Sequence>(_ units: S) -> UInt32 where S.Element == UInt16 {
        var hash: UInt32 = 2_166_136_261
        for unit in units {
            hash ^= UInt32(unit & 0xFF)
            hash = hash &* 16_777_619
            hash ^= UInt32(unit >> 8)
            hash = hash &* 16_777_619
        }
        return hash
    }
}

extension TextEditContext {
    /// Units of context taken on each side of an edit.
    public static let contextUnits = 10

    /// The context of `range` (relative to `units`): up to `contextUnits`
    /// before it plus the replaced units, and up to `contextUnits` after.
    /// `nil` when the range is outside `units`.
    public static func make(units: [UInt16], range: TextRange) -> TextEditContext? {
        guard range.start >= 0, range.length >= 0, range.end <= units.count else { return nil }
        let beforeStart = max(0, range.start - contextUnits)
        let afterEnd = min(units.count, range.end + contextUnits)
        return TextEditContext(
            beforeHash: TextHash.fnv1a(units[beforeStart..<range.end]),
            beforeLength: range.start - beforeStart,
            afterHash: TextHash.fnv1a(units[range.end..<afterEnd]),
            afterLength: afterEnd - range.end
        )
    }
}

/// The Mac's decision for one `textEdit`.
public enum TextEditCheck {
    public enum Decision: Equatable, Sendable {
        /// Select `range` (absolute) and type the replacement.
        case apply(TextRange)
        /// The same, at a range that moved since the remote's revision.
        case rebase(TextRange)
        case conflict
        case refused(TextEditRefusal)

        public var outcome: TextEditOutcome {
            switch self {
            case .apply: .applied
            case .rebase: .rebased
            case .conflict: .conflict
            case let .refused(reason): .refused(reason: reason)
            }
        }
    }

    /// How far (UTF-16 units, either way) the Mac looks for an edit's
    /// context when the field moved under it.
    public static let rebaseRadius = 64

    /// The part of the field the Mac reads to check `request`: the range,
    /// its context and the rebase radius, clamped to the field.
    public static func span(for request: TextEditRequest, fieldLength: Int) -> TextRange {
        let lower = max(0, request.range.start - request.context.beforeLength - rebaseRadius)
        let upper = min(fieldLength, request.range.end + request.context.afterLength + rebaseRadius)
        return TextRange(start: lower, length: max(0, upper - lower))
    }

    /// Decides `request` against the field now: its token, revision,
    /// readability, whether it's editable, its length, and `span` (units
    /// of the field starting at absolute `spanStart`, normally what `span`
    /// asked for).
    public static func decide(
        _ request: TextEditRequest,
        field: FieldToken,
        readable: TextReadability,
        canEdit: Bool,
        fieldLength: Int,
        span: [UInt16],
        spanStart: Int
    ) -> Decision {
        switch readable {
        case .locked: return .refused(.locked)
        case .secure: return .refused(.secure)
        case .yes: break
        default: return .refused(.notEditable)
        }
        guard request.field == field else { return .refused(.fieldChanged) }
        guard canEdit else { return .refused(.notEditable) }
        let range = request.range
        guard range.start >= 0, range.length >= 0, range.end <= fieldLength,
              request.replacement.utf8.count <= TextSyncPolicy.maxReplacementBytes,
              request.context.beforeLength >= 0, request.context.afterLength >= 0,
              request.context.beforeLength <= TextEditContext.contextUnits,
              request.context.afterLength <= TextEditContext.contextUnits else {
            return .refused(.invalid)
        }
        if matches(request, at: range.start, span: span, spanStart: spanStart) {
            return .apply(range)
        }
        for distance in 1...rebaseRadius {
            for start in [range.start - distance, range.start + distance]
            where start >= 0 && start + range.length <= fieldLength {
                if matches(request, at: start, span: span, spanStart: spanStart) {
                    return .rebase(TextRange(start: start, length: range.length))
                }
            }
        }
        return .conflict
    }

    /// Whether the context hashes match with the range starting at
    /// absolute `start`.
    static func matches(_ request: TextEditRequest, at start: Int, span: [UInt16], spanStart: Int) -> Bool {
        let context = request.context
        let lower = start - context.beforeLength - spanStart
        let rangeEnd = start + request.range.length - spanStart
        let upper = rangeEnd + context.afterLength
        guard lower >= 0, upper <= span.count, lower <= rangeEnd else { return false }
        return TextHash.fnv1a(span[lower..<rangeEnd]) == context.beforeHash
            && TextHash.fnv1a(span[rangeEnd..<upper]) == context.afterHash
    }
}
