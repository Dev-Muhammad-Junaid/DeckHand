//
//  TypedTextSummary.swift
//  PixelHandCore
//
//  How typed text reads in one line (owner testing, build 25, OT-8): in
//  Ask's plan, the key inspector, the key's face, the run confirmation,
//  widgets and App Intents. A trailing line break reads "then Return";
//  inner line breaks show as ↩, never a quote broken across lines
//  (VQ-049).
//

import Foundation

public enum TypedTextSummary {
    /// The text without its trailing line breaks, inner ones as ↩, and
    /// whether it ended with a Return.
    public static func split(_ text: String) -> (body: String, endsWithReturn: Bool) {
        var body = text
        var endsWithReturn = false
        while let last = body.last, last.isNewline {
            body.removeLast()
            endsWithReturn = true
        }
        body = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ↩ ")
        return (body, endsWithReturn)
    }

    /// One line in plain words: "Type “youtube” then Return".
    public static func line(_ text: String) -> String {
        let (body, endsWithReturn) = split(text)
        let shown = body.count > 60 ? String(body.prefix(57)) + "…" : body
        if shown.isEmpty { return endsWithReturn ? "Press Return" : "Type “”" }
        return endsWithReturn ? "Type “\(shown)” then Return" : "Type “\(shown)”"
    }

    /// A new key's label: the text's first words, cut to the deck's label
    /// length ("youtube"), or "Return" for a bare Return.
    public static func label(_ text: String) -> String {
        let (body, endsWithReturn) = split(text)
        let first = body.components(separatedBy: " ↩ ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        if first.isEmpty { return endsWithReturn ? "Return" : "Type" }
        return cut(first, to: DeckValidation.maxLabelLength)
    }

    /// The small line on the key's face under its label: the quoted text,
    /// short, and ⏎ when it presses Return ("“youtube” ⏎").
    public static func face(_ text: String, limit: Int = 12) -> String {
        let (body, endsWithReturn) = split(text)
        let quoted = body.isEmpty ? "" : "“\(cut(body, to: limit))”"
        switch (quoted.isEmpty, endsWithReturn) {
        case (true, true): return "⏎"
        case (true, false): return "“”"
        case (false, true): return quoted + " ⏎"
        case (false, false): return quoted
        }
    }

    private static func cut(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(max(1, limit - 1))) + "…" : text
    }
}
