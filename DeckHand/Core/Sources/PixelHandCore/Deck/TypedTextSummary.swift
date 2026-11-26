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

/// The key inspector's fields for typed text (OT-8): the text, and a
/// "Press Return after" switch for its trailing line break, so the common
/// "type this, then Return" reads as a switch, not an invisible newline.
public enum TypedTextEditing {
    /// The text without its last trailing line break, and whether it had
    /// one. Inner line breaks stay (the field is multi-line).
    public static func parts(_ text: String) -> (body: String, pressesReturn: Bool) {
        guard text.hasSuffix("\n") else { return (text, false) }
        return (String(text.dropLast()), true)
    }

    /// The stored text for the fields: line endings made `\n`, other
    /// control characters dropped (what the Mac would type), and a line
    /// break when Return is on.
    public static func text(body: String, pressesReturn: Bool) -> String {
        TypingText.normalized(body) + (pressesReturn ? "\n" : "")
    }
}

/// What a key's "asks first" confirmation says (OT-8). A key that types
/// names the app the text will land in, the way the Type panel's Return
/// guard does: the app the key brings forward before it types, or else
/// the app in front on the Mac now.
public enum KeyRunConfirmation {
    /// The app a typing action types into: the last app it opens or
    /// brings forward before its first typed step, or `nil` when it types
    /// into whatever is in front.
    public static func typingApp(for action: Action) -> String? {
        switch action {
        case let .sequence(steps):
            var app: String?
            for step in steps {
                guard let inner = step.action else { continue }
                if inner.typesText { return app }
                if let bundleID = inner.bundleID { app = bundleID }
            }
            return nil
        default:
            return nil
        }
    }

    /// The confirmation's message: what the key does, then where the
    /// text goes. `appName` names a bundle ID; `frontApp` is the Mac's
    /// front app now, when known.
    public static func message(for action: Action, appName: (String) -> String? = { _ in nil }, frontApp: String?) -> String {
        let summary = action.summary(appName: appName)
        guard action.typesText else { return summary }
        let target = typingApp(for: action).map { appName($0) ?? $0 } ?? frontApp ?? "the app in front on the Mac"
        let returnNote = action.pressesReturn ? ", then presses Return" : ""
        return "\(summary)\nTypes into \(target)\(returnNote)."
    }
}
