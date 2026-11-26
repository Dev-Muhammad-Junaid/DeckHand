//
//  FocusedTextReadout.swift
//  PixelHandCore
//
//  The Mac field's text in one line, around the caret (owner testing,
//  build 26, OT-13). For native text fields the Mac reads the value and
//  the selection reliably (`FocusedText`); the loupe shows that line under
//  the picture, with the caret marked and any inline suggestion dimmed
//  after it. Web and Electron fields send no text (the Mac doesn't read
//  them), so there is no readout for them.
//

import Foundation

public struct FocusedTextReadout: Sendable, Hashable {
    /// Text before the caret (or the selection), ending at it.
    public let before: String
    /// The selected text, empty for a bare caret.
    public let selected: String
    /// Text after the caret (or the selection).
    public let after: String
    /// The app's inline suggestion, drawn dimmed at the caret. `nil` when
    /// the Mac has none (always, today: see `LANE-owner26.md`).
    public let suggestion: String?

    /// About how many characters fit each side of the caret.
    public static let defaultReach = 40

    /// The readout for `text`, or `nil` when there's none. Line breaks and
    /// tabs become spaces (one line); each side is cut to `reach`
    /// characters, with "…" where it was cut or the Mac's text window was.
    public init?(_ text: FocusedText?, reach: Int = defaultReach) {
        guard let text else { return nil }
        let utf16 = Array(text.value.utf16)
        let start = min(max(0, text.selection.start), utf16.count)
        let end = min(utf16.count, start + max(0, text.selection.length))
        func string(_ range: Range<Int>) -> String {
            String(decoding: utf16[range], as: UTF16.self)
        }
        func oneLine(_ s: String) -> String {
            String(s.map { $0.isNewline || $0 == "\t" ? " " : $0 })
        }
        let reach = max(1, reach)
        var head = oneLine(string(0..<start))
        var tail = oneLine(string(end..<utf16.count))
        if head.count > reach {
            head = "…" + head.suffix(reach)
        } else if text.truncatedBefore {
            head = "…" + head
        }
        if tail.count > reach {
            tail = tail.prefix(reach) + "…"
        } else if text.truncatedAfter {
            tail += "…"
        }
        before = head
        selected = oneLine(string(start..<end))
        after = tail
        let hint = text.suggestion.map(oneLine)?.trimmingCharacters(in: .whitespaces)
        suggestion = (hint?.isEmpty ?? true) ? nil : hint
    }

    /// What VoiceOver reads.
    public var spoken: String {
        var parts = ["Text on the Mac: \(before)\(selected)\(after)"]
        if let suggestion { parts.append("Suggestion: \(suggestion). Accept with Tab.") }
        return parts.joined(separator: ". ")
    }
}
