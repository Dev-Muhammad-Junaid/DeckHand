//
//  GlyphBitmap.swift
//  PixelHandCore
//
//  One 9 × 9 pixel glyph as data. The stroke rule and the drawing maths live
//  here so they are tested on Linux; the app draws the dots with a `Canvas`.
//  Spec: `Product/Design/06-Pixel-Identity.md` §0–§1.
//

/// A cell on a glyph's grid. `x` grows to the right, `y` downwards.
public struct GlyphPoint: Sendable, Hashable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// A 9 × 9 dot glyph: which cells are lit, and the optional accent dot that
/// marks where the action happens (drawn `glow` on navy, `accent` on light).
public struct GlyphBitmap: Sendable, Hashable, Identifiable {
    /// Glyphs are always 9 × 9: an odd grid has a true centre.
    public static let size = 9

    /// The board's name (`"pointer"`, `"mission"`, …). Unique in the set.
    public let name: String
    /// A plain-language label ("Mission Control"). The control that shows the
    /// glyph carries the accessibility label; this is for lists and editors.
    public let label: String
    /// One entry per row, top first. Bit `x` (0 = leftmost) is a lit dot.
    public let rows: [UInt16]
    /// The lit accent dot, if the glyph has one.
    public let accent: GlyphPoint?
    /// Media-state glyphs (play, pause) are solid fills; every other glyph is
    /// an outline with one-dot strokes.
    public let isSolid: Bool

    public var id: String { name }

    /// Builds a glyph from nine strings of nine characters: `#` a dot, `*`
    /// the accent dot, anything else an unlit cell. Malformed patterns are a
    /// programming error.
    public init(name: String, label: String, pattern: [String], isSolid: Bool = false) {
        precondition(pattern.count == Self.size, "\(name): \(pattern.count) rows, expected \(Self.size)")
        var rows: [UInt16] = []
        var accent: GlyphPoint?
        for (y, line) in pattern.enumerated() {
            let cells = Array(line)
            precondition(cells.count == Self.size, "\(name) row \(y): \(cells.count) cells, expected \(Self.size)")
            var bits: UInt16 = 0
            for (x, cell) in cells.enumerated() where cell == "#" || cell == "*" {
                bits |= 1 << UInt16(x)
                if cell == "*" {
                    precondition(accent == nil, "\(name): more than one accent dot")
                    accent = GlyphPoint(x: x, y: y)
                }
            }
            rows.append(bits)
        }
        self.name = name
        self.label = label
        self.rows = rows
        self.accent = accent
        self.isSolid = isSolid
    }

    /// Whether the dot at (`x`, `y`) is lit. Out-of-range cells are off.
    public func isOn(_ x: Int, _ y: Int) -> Bool {
        guard (0..<Self.size).contains(x), (0..<Self.size).contains(y) else { return false }
        return rows[y] & (1 << UInt16(x)) != 0
    }

    /// Whether (`x`, `y`) is the accent dot.
    public func isAccent(_ x: Int, _ y: Int) -> Bool {
        accent == GlyphPoint(x: x, y: y)
    }

    /// Every lit cell, row by row. The accent dot is included.
    public var litPoints: [GlyphPoint] {
        var points: [GlyphPoint] = []
        for y in 0..<Self.size {
            for x in 0..<Self.size where isOn(x, y) {
                points.append(GlyphPoint(x: x, y: y))
            }
        }
        return points
    }

    /// The top-left cells of every fully lit 2 × 2 block that doesn't include
    /// the accent dot. Stroke rule 1 (one-dot strokes) wants this empty for
    /// outline glyphs; the accent is exempt because it marks a lit point (the
    /// shutter centre, the deck's lit key), not a stroke.
    public var thickStrokeBlocks: [GlyphPoint] {
        var blocks: [GlyphPoint] = []
        for y in 0..<(Self.size - 1) {
            for x in 0..<(Self.size - 1) {
                let cells = [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]
                guard cells.allSatisfy({ isOn($0.0, $0.1) }) else { continue }
                guard !cells.contains(where: { isAccent($0.0, $0.1) }) else { continue }
                blocks.append(GlyphPoint(x: x, y: y))
            }
        }
        return blocks
    }

    /// The pattern back as nine strings, for tests and the deck editor.
    public var pattern: [String] {
        (0..<Self.size).map { y in
            String((0..<Self.size).map { x -> Character in
                isAccent(x, y) ? "*" : isOn(x, y) ? "#" : "."
            })
        }
    }
}

/// The one dot every piece of Pixel Hand art is drawn with: a square at a
/// fixed share of the pitch with a corner radius proportional to the dot
/// (`06-Pixel-Identity.md` §0). Plain numbers, so it's tested here and the
/// app turns them into `CGRect`s.
public struct DotGeometry: Sendable, Hashable {
    /// Dot side as a share of the pitch.
    public let dotRatio: Double
    /// Corner radius as a share of the dot side.
    public let cornerRatio: Double

    public init(dotRatio: Double, cornerRatio: Double) {
        self.dotRatio = dotRatio
        self.cornerRatio = cornerRatio
    }

    /// Glyph dots: 78 % of the pitch, radius 30 % of the dot.
    public static let glyph = DotGeometry(dotRatio: 0.78, cornerRatio: 0.3)
    /// Dot-matrix type: 80 % of the pitch, radius 32 % of the dot.
    public static let type = DotGeometry(dotRatio: 0.8, cornerRatio: 0.32)

    /// Side of one dot at `pitch`.
    public func dotSide(pitch: Double) -> Double { pitch * dotRatio }
    /// Corner radius of one dot at `pitch`.
    public func cornerRadius(pitch: Double) -> Double { dotSide(pitch: pitch) * cornerRatio }
    /// Inset of the dot inside its cell, so it's centred.
    public func inset(pitch: Double) -> Double { (pitch - dotSide(pitch: pitch)) / 2 }

    /// The dot's frame for cell (`x`, `y`): origin and side, in points.
    public func frame(x: Int, y: Int, pitch: Double) -> (x: Double, y: Double, side: Double) {
        let o = inset(pitch: pitch)
        return (Double(x) * pitch + o, Double(y) * pitch + o, dotSide(pitch: pitch))
    }
}
