//
//  PixelGlyphs+Layout.swift
//  PixelHandCore
//
//  Layout glyphs for the iPad arrangements (UX-007), on the same 9 × 9
//  grid as the set: the Split preset (screen over trackpad, the pad's
//  action point lit), the Macs sidebar toggle, the right column's edge
//  handle chevron and the Type panel's numpad tab (build 24, OT-3/OT-4). They sit outside
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

    /// The collapsed right column's edge handle: "open toward the left"
    /// (owner testing, build 24, OT-4). The tip is the lit action point.
    public static let chevronLeft = GlyphBitmap(
        name: "chevronLeft",
        label: "Show the column",
        pattern: [
            ".........",
            ".....#...",
            "....##...",
            "...##....",
            "..*#.....",
            "...##....",
            "....##...",
            ".....#...",
            ".........",
        ]
    )

    /// The Type panel's numpad tab (OT-3): a 3 × 3 block of keys.
    public static let numpad = GlyphBitmap(
        name: "numpad",
        label: "Numpad",
        pattern: [
            ".........",
            ".##.##.##",
            ".##.##.##",
            ".........",
            ".##.*#.##",
            ".##.##.##",
            ".........",
            ".##.##.##",
            ".##.##.##",
        ]
    )

    /// The Type panel's grip (owner testing, build 25, OT-6): two columns
    /// of three dots, the usual "drag me" mark, on the 9 × 9 grid.
    public static let grip = GlyphBitmap(
        name: "grip",
        label: "Move",
        pattern: [
            ".........",
            "..##.##..",
            "..##.##..",
            ".........",
            "..##.##..",
            "..##.##..",
            ".........",
            "..##.##..",
            "..##.##..",
        ]
    )

    /// Fold the Type panel to its pill (OT-6): a bar along the foot.
    public static let collapse = GlyphBitmap(
        name: "collapse",
        label: "Collapse",
        pattern: [
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            ".#######.",
            ".#######.",
        ]
    )

    /// The Type panel's resize corner (OT-6): a stepped diagonal, the
    /// corner dot lit.
    public static let resizeCorner = GlyphBitmap(
        name: "resizeCorner",
        label: "Resize",
        pattern: [
            ".........",
            ".......#.",
            ".........",
            ".....#.#.",
            ".........",
            "...#.#.#.",
            ".........",
            ".#.#.#.*.",
            ".........",
        ]
    )

    /// The arrow keys' legends (OT-7), solid heads on a stem.
    public static let keyUp = GlyphBitmap(
        name: "keyUp",
        label: "Up arrow",
        pattern: [
            "....#....",
            "...###...",
            "..#####..",
            ".###.###.",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            ".........",
        ]
    )

    public static let keyDown = GlyphBitmap(
        name: "keyDown",
        label: "Down arrow",
        pattern: [
            ".........",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            ".###.###.",
            "..#####..",
            "...###...",
            "....#....",
        ]
    )

    public static let keyLeft = GlyphBitmap(
        name: "keyLeft",
        label: "Left arrow",
        pattern: [
            ".........",
            "...#.....",
            "..##.....",
            ".###.....",
            "#########",
            ".###.....",
            "..##.....",
            "...#.....",
            ".........",
        ]
    )

    public static let keyRight = GlyphBitmap(
        name: "keyRight",
        label: "Right arrow",
        pattern: [
            ".........",
            ".....#...",
            ".....##..",
            ".....###.",
            "#########",
            ".....###.",
            ".....##..",
            ".....#...",
            ".........",
        ]
    )

    /// The layout glyphs, kept apart from the spec's 40.
    public static let layout: [GlyphBitmap] = [
        layoutSplit, sidebar, chevronLeft, numpad,
        grip, collapse, resizeCorner, keyUp, keyDown, keyLeft, keyRight,
    ]
}
