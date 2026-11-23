//
//  CaptureGlyphs.swift
//  PixelHandCore
//
//  The capture sheet's own action glyphs (UX-009), drawn to the same rule
//  as `PixelGlyphs`: 9 × 9, one-dot strokes, the accent dot where the action
//  happens. Kept beside the capture chrome rather than in the shared set.
//

public enum CaptureGlyphs {
    /// Save to Photos: an arrow into a tray.
    public static let save = GlyphBitmap(
        name: "capture.save",
        label: "Save",
        pattern: [
            "....#....",
            "....#....",
            "....#....",
            "..#.#.#..",
            "...#*#...",
            "....#....",
            "#.......#",
            "#.......#",
            "#########",
        ]
    )

    /// Copy: two overlapping sheets.
    public static let copy = GlyphBitmap(
        name: "capture.copy",
        label: "Copy",
        pattern: [
            "...######",
            "...#....#",
            "######..#",
            "#....#..#",
            "#....####",
            "#..*.#...",
            "#....#...",
            "#....#...",
            "######...",
        ]
    )

    /// Annotate: a pen on the diagonal, its tip lit.
    public static let annotate = GlyphBitmap(
        name: "capture.annotate",
        label: "Annotate",
        pattern: [
            "......##.",
            ".....#..#",
            "....#..#.",
            "...#..#..",
            "..#..#...",
            ".#..#....",
            ".#.#.....",
            "*##......",
            ".........",
        ]
    )

    /// Undo: a hook arrow back to the left.
    public static let undo = GlyphBitmap(
        name: "capture.undo",
        label: "Undo",
        pattern: [
            ".........",
            "..#......",
            ".#.......",
            "*######..",
            ".#.....#.",
            "..#.....#",
            "........#",
            ".......#.",
            "..#####..",
        ]
    )

    /// Clear: a bin.
    public static let clear = GlyphBitmap(
        name: "capture.clear",
        label: "Clear",
        pattern: [
            "...###...",
            "..#...#..",
            "#########",
            ".#.....#.",
            ".#.#*#.#.",
            ".#.#.#.#.",
            ".#.#.#.#.",
            ".#.....#.",
            "..#####..",
        ]
    )

    /// Reset a selection: a square with a corner arrow.
    public static let reset = GlyphBitmap(
        name: "capture.reset",
        label: "Reset",
        pattern: [
            "#.#.#.#..",
            ".......#.",
            "#.....###",
            "........#",
            "#...*....",
            "........#",
            "#.......#",
            ".........",
            "#.#.#.#.#",
        ]
    )

    /// Refresh a list: a loop with its head lit.
    public static let refresh = GlyphBitmap(
        name: "capture.refresh",
        label: "Refresh",
        pattern: [
            "..###.*..",
            ".#....##.",
            "#.....#..",
            "#........",
            "#.......#",
            "#.......#",
            ".#.....#.",
            "..#####..",
            ".........",
        ]
    )

    /// Every capture glyph.
    public static let all: [GlyphBitmap] = [save, copy, annotate, undo, clear, reset, refresh]
}
