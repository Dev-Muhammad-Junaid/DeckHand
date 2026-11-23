//
//  PixelGlyphs+Layout.swift
//  PixelHandCore
//
//  Two layout glyphs for the iPad arrangements (UX-007), on the same 9 × 9
//  grid as the set: the Split preset (screen over trackpad, the pad's
//  action point lit) and the Macs sidebar toggle. They sit outside
//  `PixelGlyphs.all`, which stays the spec's 40 (`06-Pixel-Identity.md` §1).
//

extension PixelGlyphs {
    /// Layout preset "Split": the screen over the trackpad.
    public static let layoutSplit = GlyphBitmap(
        name: "layoutSplit",
        label: "Split",
        pattern: [
            "#########",
            "#.......#",
            "#.......#",
            "#########",
            ".........",
            "#########",
            "#...*...#",
            "#.......#",
            "#########",
        ]
    )

    /// Show or hide the Macs sidebar.
    public static let sidebar = GlyphBitmap(
        name: "sidebar",
        label: "Sidebar",
        pattern: [
            "#########",
            "#.#.....#",
            "#.#.....#",
            "#.#.....#",
            "#.#.....#",
            "#.#.....#",
            "#.#.....#",
            "#.#.....#",
            "#########",
        ]
    )

    /// The layout glyphs, kept apart from the spec's 40.
    public static let layout: [GlyphBitmap] = [layoutSplit, sidebar]
}
