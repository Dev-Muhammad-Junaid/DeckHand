//
//  TransferGlyphs.swift
//  PixelHandCore – Transfer
//
//  The Send sheet's own source and item glyphs (owner testing, build 26,
//  OT-9), drawn to the same rule as `PixelGlyphs`: 9 × 9, one-dot strokes,
//  the accent dot where the action happens. Kept beside the transfer code
//  like `CaptureGlyphs`. Clipboard uses the shared `PixelGlyphs.paste`,
//  text the shared `PixelGlyphs.type`.
//

public enum TransferGlyphs {
    /// Photos: a framed picture, a hill and the sun lit.
    public static let photos = GlyphBitmap(
        name: "transfer.photos",
        label: "Photos",
        pattern: [
            ".........",
            "#########",
            "#.......#",
            "#.....*.#",
            "#...#...#",
            "#..#.#..#",
            "#.#...#.#",
            "#########",
            ".........",
        ]
    )

    /// Files: a folder with its tab, the centre lit.
    public static let files = GlyphBitmap(
        name: "transfer.files",
        label: "Files",
        pattern: [
            ".........",
            "###......",
            "#..######",
            "#.......#",
            "#########",
            "#.......#",
            "#...*...#",
            "#.......#",
            "#########",
        ]
    )

    /// A link: two rings joined, the joint lit.
    public static let link = GlyphBitmap(
        name: "transfer.link",
        label: "Link",
        pattern: [
            ".........",
            ".........",
            ".###.###.",
            "#...#...#",
            "#...*...#",
            "#...#...#",
            ".###.###.",
            ".........",
            ".........",
        ]
    )

    /// Every transfer glyph.
    public static let all: [GlyphBitmap] = [photos, files, link]
}
