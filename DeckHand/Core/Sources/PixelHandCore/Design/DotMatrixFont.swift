//
//  DotMatrixFont.swift
//  PixelHandCore
//
//  The 5 × 7 dot-matrix type for status words, counters, stats and codes
//  (`Product/Design/06-Pixel-Identity.md` §2). Never for sentences, buttons,
//  prices or anything a person must read to decide; every string drawn with
//  it also gets a plain-language accessibility label in the app.
//

import Foundation

/// A 5 × 7 cell font with one cell of tracking (a 6-cell advance).
/// Uppercase A–Z, 0–9 and `space · : / % - . + < > ' ’ , & ( ) ? !`.
/// Lowercase is uppercased, accented letters lose their accents ("É" draws
/// as "E"), typographic dashes and quotes draw as their plain forms, and
/// anything else draws as a space.
public enum DotMatrixFont {
    /// Cells across one character.
    public static let columns = 5
    /// Cells down one character.
    public static let rows = 7
    /// Cells from one character's left edge to the next one's.
    public static let advance = 6

    /// Every character the font draws.
    public static var characters: Set<Character> { Set(table.keys) }

    /// The 35-bit pattern for `character`, row by row from the top-left;
    /// bit `row * 5 + column` is a lit dot. Lowercase letters map to
    /// uppercase. Returns nil for characters the font doesn't have.
    public static func pattern(for character: Character) -> UInt64? {
        guard let resolved = resolve(character), let string = table[resolved] else { return nil }
        var bits: UInt64 = 0
        for (index, cell) in string.enumerated() where cell == "1" {
            bits |= 1 << UInt64(index)
        }
        return bits
    }

    /// Whether `character` draws a dot at (`column`, `row`).
    public static func isOn(_ character: Character, column: Int, row: Int) -> Bool {
        guard (0..<columns).contains(column), (0..<rows).contains(row),
              let bits = pattern(for: character) else { return false }
        return bits & (1 << UInt64(row * columns + column)) != 0
    }

    /// The text as the font draws it: uppercased, unknown characters as
    /// spaces (the board does the same).
    public static func normalized(_ text: String) -> [Character] {
        text.uppercased().map { resolve($0) ?? " " }
    }

    /// Typographic characters that draw as a character the font has.
    static let aliases: [Character: Character] = [
        "‘": "’", "ʼ": "’", "`": "'", "´": "'",
        "–": "-", "—": "-", "‐": "-", "‑": "-", "−": "-",
        "•": "·", "∙": "·",
    ]

    /// The table character that draws `character`: itself, its uppercase
    /// form, an alias, or the letter without its accent. Nil when the font
    /// has nothing for it.
    static func resolve(_ character: Character) -> Character? {
        if table[character] != nil { return character }
        let upperString = String(character).uppercased()
        if upperString.count == 1, let upper = upperString.first {
            if table[upper] != nil { return upper }
            if let alias = aliases[upper] { return alias }
        }
        let folded = upperString
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .uppercased()
        if folded.count == 1, let plain = folded.first, table[plain] != nil { return plain }
        return nil
    }

    /// Width of `text` in cells: 6 per character less the trailing
    /// tracking, at least 1 so an empty string still has a frame.
    public static func widthInCells(_ text: String) -> Int {
        max(1, normalized(text).count * advance - 1)
    }

    /// Every lit cell of `text`, as cell coordinates from the top-left of
    /// the line. The app multiplies by the pitch and draws one dot per cell.
    public static func litCells(_ text: String) -> [GlyphPoint] {
        var cells: [GlyphPoint] = []
        for (index, character) in normalized(text).enumerated() {
            guard let bits = pattern(for: character), bits != 0 else { continue }
            for bit in 0..<(columns * rows) where bits & (1 << UInt64(bit)) != 0 {
                cells.append(GlyphPoint(x: index * advance + bit % columns, y: bit / columns))
            }
        }
        return cells
    }

    /// Every cell of `text`'s character boxes that is *not* lit, for the
    /// "LED panel" look (unlit cells at 14 %, used only on the PRO mark, the
    /// specimen and a strip's dim state).
    public static func unlitCells(_ text: String) -> [GlyphPoint] {
        let lit = Set(litCells(text))
        var cells: [GlyphPoint] = []
        for index in 0..<normalized(text).count {
            for row in 0..<rows {
                for column in 0..<columns {
                    let point = GlyphPoint(x: index * advance + column, y: row)
                    if !lit.contains(point) { cells.append(point) }
                }
            }
        }
        return cells
    }
}
