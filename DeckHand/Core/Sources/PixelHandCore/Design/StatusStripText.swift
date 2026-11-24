//
//  StatusStripText.swift
//  PixelHandCore – Design
//
//  What a dot-matrix status strip says when it can't say everything
//  (`06-Pixel-Identity.md` §3): it truncates at a separator, never mid-word.
//  A Mac's name shortens word by word ("Muhammad's MacBook Pro" →
//  "Muhammad's MacBook" → "Muhammad's"), and when even the first word
//  doesn't fit the strip shows its live pixel alone. Used by the widgets
//  and the Lock Screen widget, which can't measure text any other way than
//  by trying each line in a `ViewThatFits`.
//

import Foundation

public enum StatusStripText {
    /// Between a strip's items.
    public static let separator = " · "

    /// The longest Mac name a strip ever draws, in characters, before word
    /// shortening starts.
    public static let maxNameCharacters = 32

    /// `name` and its shorter forms, longest first, each ending on a whole
    /// word: "Muhammad's MacBook Pro", "Muhammad's MacBook", "Muhammad's".
    /// Runs of spaces collapse, and words the font can't draw at all (an
    /// emoji, a lone dash) are dropped from the end of a form. Empty for a
    /// blank name.
    public static func nameForms(_ name: String) -> [String] {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        var forms: [String] = []
        var count = words.count
        while count > 0 {
            var prefix = Array(words.prefix(count))
            while let last = prefix.last, !isDrawable(word: last) { prefix.removeLast() }
            let form = prefix.joined(separator: " ")
            if !form.isEmpty, form.count <= maxNameCharacters, !forms.contains(form) {
                forms.append(form)
            }
            count -= 1
        }
        // A single word longer than the cap stays whole: it is the name.
        if forms.isEmpty, let first = words.first(where: isDrawable(word:)) {
            forms.append(first)
        }
        return forms
    }

    /// Every line a strip may show, most complete first. Details (the
    /// front app, LOCKED, OFFLINE) are kept as long as possible, and the
    /// name shortens word by word before a detail is dropped; trailing
    /// details go first. No line cuts a word.
    public static func candidates(name: String?, details: [String]) -> [String] {
        let names = name.map(nameForms) ?? []
        let items = details
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var lines: [String] = []
        func add(_ line: String) {
            if !line.isEmpty, !lines.contains(line) { lines.append(line) }
        }
        for kept in stride(from: items.count, through: 0, by: -1) {
            let tail = Array(items.prefix(kept))
            if names.isEmpty {
                add(tail.joined(separator: separator))
            }
            for form in names {
                add(([form] + tail).joined(separator: separator))
            }
        }
        return lines
    }

    /// The first of `candidates(name:details:)` that fits `maxCells`
    /// dot-matrix cells, or nil when nothing fits and the strip shows its
    /// live pixel alone.
    public static func fit(name: String?, details: [String], maxCells: Int) -> String? {
        candidates(name: name, details: details).first { DotMatrixFont.widthInCells($0) <= maxCells }
    }

    /// Whether `word` has a letter or digit the dot-matrix font draws. A
    /// lone dash or an emoji isn't worth ending a strip on.
    static func isDrawable(word: String) -> Bool {
        DotMatrixFont.normalized(word).contains { character in
            (character.isLetter || character.isNumber) && (DotMatrixFont.pattern(for: character) ?? 0) != 0
        }
    }
}
