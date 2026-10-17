//
//  PixelArt.swift
//  Deck Hand – Shared
//
//  The dot-matrix artwork from the app icon: the pointing hand drawn in lit
//  dots, the approval check and cross, and the small glyphs used for empty
//  states. The website draws the same strings
//  (`website/tools/mockups/build.py`, `GLYPHS`), so the app, the Mac menu
//  bar and the site share one set of pixel art.
//

import SwiftUI

/// What one dot in a bitmap is.
enum PixelKind: Sendable, Equatable {
    case off
    /// The lit outline (`X`).
    case outline
    /// The violet fill (`o`).
    case fill
    /// The one cyan detail in a glyph (`c`).
    case detail
    /// A tap ray right above the fingertip (`r`).
    case ray
    /// The fainter outer tap ray (`f`).
    case farRay

    init(_ character: Character) {
        switch character {
        case "X": self = .outline
        case "o": self = .fill
        case "c": self = .detail
        case "r": self = .ray
        case "f": self = .farRay
        default: self = .off
        }
    }

    /// Lit kinds get a bloom around them; the fill sits flat.
    var glows: Bool {
        switch self {
        case .outline, .detail, .ray, .farRay: true
        case .off, .fill: false
        }
    }
}

/// A grid of dots, one string per row. Rows shorter than the widest row are
/// treated as padded with unlit dots.
struct PixelBitmap: Sendable, Equatable {
    let width: Int
    let height: Int
    private let cells: [PixelKind]

    init(_ rows: [String]) {
        let width = rows.map(\.count).max() ?? 0
        var cells: [PixelKind] = []
        cells.reserveCapacity(width * rows.count)
        for row in rows {
            let kinds = row.map(PixelKind.init)
            cells.append(contentsOf: kinds)
            cells.append(contentsOf: repeatElement(.off, count: width - kinds.count))
        }
        self.width = width
        self.height = rows.count
        self.cells = cells
    }

    private init(width: Int, height: Int, cells: [PixelKind]) {
        self.width = width
        self.height = height
        self.cells = cells
    }

    subscript(x: Int, y: Int) -> PixelKind {
        guard x >= 0, y >= 0, x < width, y < height else { return .off }
        return cells[y * width + x]
    }

    /// `self` placed at (`x`, `y`) on a larger, otherwise unlit canvas.
    func placed(atX x: Int, y: Int, width: Int, height: Int) -> PixelBitmap {
        var cells = [PixelKind](repeating: .off, count: width * height)
        for row in 0..<self.height {
            for column in 0..<self.width {
                let tx = column + x, ty = row + y
                guard tx >= 0, ty >= 0, tx < width, ty < height else { continue }
                cells[ty * width + tx] = self[column, row]
            }
        }
        return PixelBitmap(width: width, height: height, cells: cells)
    }

    /// A copy with `kind` written at each point that's on the canvas.
    func setting(_ kind: PixelKind, at points: [(x: Int, y: Int)]) -> PixelBitmap {
        var cells = self.cells
        for point in points where point.x >= 0 && point.y >= 0 && point.x < width && point.y < height {
            cells[point.y * width + point.x] = kind
        }
        return PixelBitmap(width: width, height: height, cells: cells)
    }

    /// A copy with every dot of one kind changed to another.
    func replacing(_ kind: PixelKind, with replacement: PixelKind) -> PixelBitmap {
        PixelBitmap(width: width, height: height, cells: cells.map { $0 == kind ? replacement : $0 })
    }

    /// Strokes drawn as dots: every dot whose centre is within `radius` of
    /// one of the line segments (in dot coordinates) is lit as `outline`.
    static func stroked(
        width: Int,
        height: Int,
        segments: [(CGPoint, CGPoint)],
        radius: CGFloat
    ) -> PixelBitmap {
        var cells = [PixelKind](repeating: .off, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let p = CGPoint(x: CGFloat(x), y: CGFloat(y))
                let near = segments.contains { distance(from: p, toSegment: $0.0, $0.1) < radius }
                if near { cells[y * width + x] = .outline }
            }
        }
        return PixelBitmap(width: width, height: height, cells: cells)
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let vx = b.x - a.x, vy = b.y - a.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / lengthSquared))
        return hypot(p.x - a.x - t * vx, p.y - a.y - t * vy)
    }
}

enum PixelArt {
    /// The pointing hand from the icon, drawn like the classic Mac hand
    /// cursor: `X` is the lit outline (including the knuckle dividers and
    /// thumb crease), `o` is the violet fill. 17 × 18.
    static let hand = PixelBitmap([
        ".....XX..........",
        "....XooX.........",
        "....XooX.........",
        "....XooX.........",
        "....XooX.........",
        "....XooXXX.XX....",
        "....XooXooXooXX..",
        "....XooXooXooXoX.",
        ".XX.XooXooXooXoX.",
        "XooXXooXooXooXoX.",
        "XoooXooooooooooX.",
        ".XooXooooooooooX.",
        "..XoooooooooooX..",
        "..XoooooooooooX..",
        "...XooooooooooX..",
        "....XooooooooX...",
        "....XooooooooX...",
        "....XXXXXXXXXX...",
    ])

    /// Width and height of the canvas the approval glyphs share, so the
    /// hand can rearrange into the check or the cross dot for dot.
    static let stageWidth = 19
    static let stageHeight = 21

    /// The hand with its three tap rays above the fingertip: straight up and
    /// out to either side, on the shared approval canvas.
    static let handWithRays: PixelBitmap = hand
        .placed(atX: 1, y: 3, width: stageWidth, height: stageHeight)
        // Ray positions are relative to the hand's own grid (fingertip at
        // columns 5–6 of row 0), shifted by the placement above.
        .setting(.ray, at: [(6, 1), (7, 1), (4, 2), (9, 2)])
        .setting(.farRay, at: [(6, 0), (7, 0), (3, 1), (10, 1)])

    /// Approved: a check on the shared approval canvas.
    static let check = PixelBitmap.stroked(
        width: stageWidth,
        height: stageHeight,
        segments: [
            (CGPoint(x: 3.5, y: 11), CGPoint(x: 7.5, y: 15)),
            (CGPoint(x: 7.5, y: 15), CGPoint(x: 15, y: 5.5)),
        ],
        radius: 1.25
    )

    /// Denied: a cross on the shared approval canvas.
    static let cross = PixelBitmap.stroked(
        width: stageWidth,
        height: stageHeight,
        segments: [
            (CGPoint(x: 4, y: 5), CGPoint(x: 14, y: 15)),
            (CGPoint(x: 14, y: 5), CGPoint(x: 4, y: 15)),
        ],
        radius: 1.15
    )

    // MARK: Glyphs (the website's interlude row)

    /// The classic Mac arrow.
    static let point = PixelBitmap([
        "X...........", "XX..........", "XoX.........", "XooX........", "XoooX.......", "XooooX......",
        "XoooooX.....", "XooooooX....", "XoooooooX...", "XooooooooX..", "XoooooXXXXX.", "XooXooX.....",
        "XoX.XooX....", "XX..XooX....", "X....XooX...", ".....XooX...", "......XX....",
    ])

    /// Two overlapping windows: the live mirror, and window lists.
    static let mirror = PixelBitmap([
        "...XXXXXXXXX", "...X.......X", "XXXXXXXX...X", "XooooooX...X", "XoocoooX...X",
        "XooooooXXXXX", "XooooooX....", "XXXXXXXX....",
    ])

    /// A viewfinder: captures and text recognition.
    static let capture = PixelBitmap([
        "XXX.....XXX", "X.........X", "X.........X", "....ooo....", "...oocoo...",
        "...ooooo...", "....ooo....", "X.........X", "X.........X", "XXX.....XXX",
    ])

    /// A grid of app tiles.
    static let launch = PixelBitmap([
        "XXXX..XXXX", "XooX..XccX", "XooX..XccX", "XXXX..XXXX", "..........",
        "..........", "XXXX..XXXX", "XooX..XooX", "XooX..XooX", "XXXX..XXXX",
    ])

    /// A dialog with its buttons: shortcuts and answering the Mac.
    static let answer = PixelBitmap([
        "XXXXXXXXXXXX", "X..........X", "X.oooooooo.X", "X.ooooo....X", "X..........X",
        "X.ooo..cccc.", "X..........X", "XXXXXXXXXXXX",
    ])
}

// MARK: - Palette

/// The colors a bitmap is drawn in, by `PixelKind`.
struct PixelPalette: Equatable {
    var outline: Color
    var fill: Color
    var detail: Color
    var ray: Color
    /// Bloom behind lit dots.
    var glow: Color
    /// Dots that are off. `.clear` draws only the lit art.
    var unlit: Color

    /// The icon: phosphor outline, violet fill, cyan rays and bloom.
    static let brand = PixelPalette(
        outline: DeckHandTheme.Brand.phosphor,
        fill: DeckHandTheme.Brand.pixelViolet,
        detail: DeckHandTheme.Brand.ray,
        ray: DeckHandTheme.Brand.ray,
        glow: DeckHandTheme.Brand.glow,
        unlit: DeckHandTheme.Brand.dotOff
    )

    /// Every lit dot in one color, for status glyphs (a mint check, a red
    /// cross) and template images.
    static func solid(_ color: Color, unlit: Color = DeckHandTheme.Brand.dotOff) -> PixelPalette {
        PixelPalette(outline: color, fill: color.opacity(0.35), detail: color, ray: color, glow: color, unlit: unlit)
    }

    func color(for kind: PixelKind) -> Color {
        switch kind {
        case .off: unlit
        case .outline: outline
        case .fill: fill
        case .detail: detail
        case .ray: ray
        case .farRay: ray.opacity(0.7)
        }
    }
}

// MARK: - Drawing

/// Draws bitmaps as dots. Not tied to a view, so the Mac's menu bar icon
/// and animated glyphs can share it.
enum PixelPainter {
    /// Dot size relative to pitch, matching the icon (18-unit dots on a
    /// 26-unit pitch).
    static let dotRatio: CGFloat = 0.7

    static func dotPath(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.width * 0.32, style: .continuous)
    }

    /// Draws `bitmap` with its top-left dot cell at the origin. `shade`
    /// returns the color and opacity for each dot, so callers can animate
    /// individual dots; lit dots with opacity above zero get the bloom.
    static func draw(
        _ bitmap: PixelBitmap,
        in context: inout GraphicsContext,
        pitch: CGFloat,
        glow: Color?,
        shade: (_ x: Int, _ y: Int, _ kind: PixelKind) -> (Color, Double)
    ) {
        let dot = pitch * dotRatio
        func rect(_ x: Int, _ y: Int, grow: CGFloat = 0) -> CGRect {
            CGRect(
                x: CGFloat(x) * pitch + (pitch - dot) / 2 - grow,
                y: CGFloat(y) * pitch + (pitch - dot) / 2 - grow,
                width: dot + grow * 2,
                height: dot + grow * 2
            )
        }

        if let glow {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: pitch * 0.45))
                for y in 0..<bitmap.height {
                    for x in 0..<bitmap.width where bitmap[x, y].glows {
                        let (_, opacity) = shade(x, y, bitmap[x, y])
                        guard opacity > 0 else { continue }
                        layer.fill(dotPath(rect(x, y, grow: dot * 0.15)), with: .color(glow.opacity(opacity)))
                    }
                }
            }
        }

        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let (color, opacity) = shade(x, y, bitmap[x, y])
                guard opacity > 0 else { continue }
                context.fill(dotPath(rect(x, y)), with: .color(color.opacity(opacity)))
            }
        }
    }
}

// MARK: - Static glyph

/// A bitmap drawn as dots, with a bloom behind the lit ones. For pixel art
/// that doesn't animate: empty states, the Mac popover header.
struct PixelGlyph: View {
    let bitmap: PixelBitmap
    /// Distance between dot centres, in points.
    var pitch: CGFloat = 5
    var palette: PixelPalette = .brand
    /// Turn off on small sizes, where a bloom just blurs.
    var glows: Bool = true

    var body: some View {
        let bitmap = self.bitmap
        let pitch = self.pitch
        let palette = self.palette
        let glow = glows ? palette.glow : nil
        Canvas { context, _ in
            PixelPainter.draw(bitmap, in: &context, pitch: pitch, glow: glow) { _, _, kind in
                (palette.color(for: kind), 1)
            }
        }
        .frame(width: CGFloat(bitmap.width) * pitch, height: CGFloat(bitmap.height) * pitch)
        .accessibilityHidden(true)
    }
}

/// A small piece of the icon's screen glass. Dot art is drawn in light
/// colors, so on light or material surfaces it sits on one of these.
struct PixelScreen<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [DeckHandTheme.Brand.screenHigh.opacity(0.85), DeckHandTheme.Brand.screen],
                            center: UnitPoint(x: 0.5, y: 0.3),
                            startRadius: 0,
                            endRadius: 140
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(DeckHandTheme.Brand.tileStroke, lineWidth: 1)
                    )
            )
            // Status colors inside resolve to their dark-appearance values.
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Live pixel

/// The icon's mint pixel as a status light: a small rounded square that
/// breathes while something is live. Holds still under Reduce Motion.
struct LivePixel: View {
    var color: Color = DeckHandTheme.success
    var size: CGFloat = 6
    /// Breathes twice as fast for transient states such as reconnecting.
    var isUrgent: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = self.color
        let size = self.size
        // One full breath is DeckHandMotion.ambient's 2.4 s: two phases.
        let halfBreath = isUrgent ? 0.6 : 1.2
        let square = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)

        Group {
            if reduceMotion {
                square.shadow(color: color.opacity(0.55), radius: size * 0.7)
            } else {
                square
                    .phaseAnimator([false, true]) { content, dim in
                        content
                            .opacity(dim ? 0.55 : 1)
                            .shadow(color: color.opacity(dim ? 0.1 : 0.55), radius: dim ? 1 : size * 0.7)
                    } animation: { _ in
                        .easeInOut(duration: halfBreath)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
