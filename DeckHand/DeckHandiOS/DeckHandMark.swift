//
//  DeckHandMark.swift
//  DeckHandiOS
//
//  The app icon rebuilt as a live view: a tilted iPad with a glossy frame,
//  and the classic pointing-hand cursor drawn in lit dots on its screen. Tap
//  rays flick on above the fingertip once the device settles. Used on the
//  first-run surfaces so they read as the icon the user just tapped.
//

import SwiftUI

struct DeckHandMark: View {
    /// Overall edge length of the square the mark is drawn in.
    var size: CGFloat = 132
    /// Plays the entrance and the tap. Off for static contexts like a nav bar.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var raysLit = false

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                MarkArtwork.drawDevice(in: &context, canvasSize: canvasSize)
            }
            Canvas { context, canvasSize in
                MarkArtwork.drawRays(in: &context, canvasSize: canvasSize)
            }
            .opacity(raysLit ? 1 : 0)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-7))
        // The device sits on the dark brand canvas, so it gets a violet bloom
        // rather than a drop shadow.
        .shadow(color: DeckHandTheme.Brand.glow.opacity(0.45), radius: size * 0.16)
        .scaleEffect(hasAppeared ? 1 : 0.94)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            guard animated, !reduceMotion else {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    hasAppeared = true
                    raysLit = true
                }
                return
            }
            withAnimation(.spring(duration: 0.42, bounce: 0.18)) { hasAppeared = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.35)) { raysLit = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Deck Hand")
    }
}

/// Drawing for `DeckHandMark`, in a 900-unit square centred on the origin.
/// Values match the master artwork in `website/brand/concept-b2-ipad.svg`.
private enum MarkArtwork {
    static let canvasUnits: CGFloat = 900
    static let deviceSize = CGSize(width: 860, height: 650)
    static let bezel: CGFloat = 36
    static let deviceCorner: CGFloat = 118
    static let screenCorner: CGFloat = 74
    static let pitch: CGFloat = 26
    static let dot: CGFloat = 18

    /// The pointing hand, one character per dot, drawn like the classic Mac
    /// hand cursor: `X` is the lit outline (including the knuckle dividers
    /// and thumb crease), `o` is the violet fill.
    static let hand: [String] = [
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
    ]

    static let cells: [[Bool]] = hand.map { row in row.map { $0 != "." } }
    static let outline: [[Bool]] = hand.map { row in row.map { $0 == "X" } }

    static var screenSize: CGSize {
        CGSize(width: deviceSize.width - bezel * 2, height: deviceSize.height - bezel * 2)
    }

    static var screenRect: CGRect {
        CGRect(x: -screenSize.width / 2, y: -screenSize.height / 2,
               width: screenSize.width, height: screenSize.height)
    }

    /// Centre of the hand's top-left dot. The hand sits a touch left of
    /// centre so the finger and its rays read as the middle of the screen.
    static var origin: CGPoint {
        CGPoint(x: -(8 - 0.3) * pitch, y: -screenSize.height / 2 + 3.5 * pitch)
    }

    enum Kind {
        case off, fill, edge, nearRay, farRay, mint
    }

    static func isFilled(_ x: Int, _ y: Int) -> Bool {
        guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else { return false }
        return cells[y][x]
    }

    static func kind(_ x: Int, _ y: Int) -> Kind {
        if isFilled(x, y) {
            return outline[y][x] ? .edge : .fill
        }
        if let ray = ray(x, y) { return ray }
        if x == mintCell.x && y == mintCell.y { return .mint }
        return .off
    }

    /// Three short strokes above the fingertip: straight up, and out to
    /// either side.
    static func ray(_ x: Int, _ y: Int) -> Kind? {
        let tip = cells[0]
        guard let left = tip.firstIndex(of: true), let right = tip.lastIndex(of: true) else { return nil }
        if y == -2 && (left...right).contains(x) { return .nearRay }
        if y == -3 && (left...right).contains(x) { return .farRay }
        if y == -1 && (x == left - 2 || x == right + 2) { return .nearRay }
        if y == -2 && (x == left - 3 || x == right + 3) { return .farRay }
        return nil
    }

    /// One mint dot near the top-right corner, carried over from the mint
    /// tile in the original icon.
    static var mintCell: (x: Int, y: Int) {
        let target = CGPoint(x: screenSize.width / 2 - 2.6 * pitch, y: -screenSize.height / 2 + 2.4 * pitch)
        return (Int(((target.x - origin.x) / pitch).rounded()),
                Int(((target.y - origin.y) / pitch).rounded()))
    }

    static func forEachDot(_ body: (CGRect, Kind) -> Void) {
        let limitX = screenSize.width / 2 - dot * 0.8
        let limitY = screenSize.height / 2 - dot * 0.8
        for y in -20...30 {
            for x in -20...30 {
                let centre = CGPoint(x: origin.x + CGFloat(x) * pitch, y: origin.y + CGFloat(y) * pitch)
                guard abs(centre.x) <= limitX, abs(centre.y) <= limitY else { continue }
                let rect = CGRect(x: centre.x - dot / 2, y: centre.y - dot / 2, width: dot, height: dot)
                body(rect, kind(x, y))
            }
        }
    }

    static func dotPath(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 6, style: .continuous)
    }

    static func prepare(_ context: inout GraphicsContext, canvasSize: CGSize) {
        context.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let scale = canvasSize.width / canvasUnits
        context.scaleBy(x: scale, y: scale)
    }

    static func drawDevice(in context: inout GraphicsContext, canvasSize: CGSize) {
        prepare(&context, canvasSize: canvasSize)

        let outer = CGRect(x: -deviceSize.width / 2, y: -deviceSize.height / 2,
                           width: deviceSize.width, height: deviceSize.height)

        // Underside first, so the frame reads as a slab rather than a sticker.
        context.fill(
            Path(roundedRect: outer.offsetBy(dx: 0, dy: 10), cornerRadius: deviceCorner, style: .continuous),
            with: .linearGradient(
                Gradient(colors: [Color(hex: "C9D3FB"), Color(hex: "7D8FE6")]),
                startPoint: CGPoint(x: 0, y: outer.minY),
                endPoint: CGPoint(x: 0, y: outer.maxY + 10)
            )
        )
        context.fill(
            Path(roundedRect: outer, cornerRadius: deviceCorner, style: .continuous),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(hex: "E4EAFF"), location: 0.75),
                    .init(color: Color(hex: "B3C1F5"), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: outer.minY),
                endPoint: CGPoint(x: 0, y: outer.maxY)
            )
        )
        context.stroke(
            Path(roundedRect: outer.insetBy(dx: 3, dy: 3), cornerRadius: deviceCorner - 3, style: .continuous),
            with: .color(Color.white.opacity(0.9)),
            lineWidth: 4
        )

        let screen = screenRect
        context.fill(
            Path(roundedRect: screen.insetBy(dx: -4, dy: -4), cornerRadius: screenCorner + 4, style: .continuous),
            with: .color(Color(hex: "B9C5F2"))
        )

        let screenPath = Path(roundedRect: screen, cornerRadius: screenCorner, style: .continuous)
        context.drawLayer { layer in
            layer.clip(to: screenPath)
            layer.fill(
                screenPath,
                with: .radialGradient(
                    Gradient(colors: [Color(hex: "1C2C80"), Color(hex: "060A2A")]),
                    center: CGPoint(x: 0, y: screen.minY + screen.height * 0.35),
                    startRadius: 0,
                    endRadius: screen.width * 0.8
                )
            )

            // Cyan bloom behind the hand's outline and the mint dot.
            layer.drawLayer { glow in
                glow.addFilter(.blur(radius: 7))
                forEachDot { rect, kind in
                    switch kind {
                    case .edge: glow.fill(dotPath(rect), with: .color(Color(hex: "3DE0E0")))
                    case .mint: glow.fill(dotPath(rect.insetBy(dx: -3, dy: -3)), with: .color(Color(hex: "3DE0B0")))
                    default: break
                    }
                }
            }

            forEachDot { rect, kind in
                let path = dotPath(rect)
                switch kind {
                case .edge: layer.fill(path, with: .color(Color(hex: "EFFFFC")))
                case .fill: layer.fill(path, with: .color(Color(hex: "8E70FF")))
                case .mint: layer.fill(path, with: .color(Color(hex: "3DE0B0")))
                case .off: layer.fill(path, with: .color(Color(hex: "2B3C99").opacity(0.5)))
                case .nearRay, .farRay: break // drawn by `drawRays`
                }
            }

            // Glass sheen across the upper-left of the screen.
            layer.fill(
                screenPath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color.white.opacity(0.22), location: 0),
                        .init(color: Color.white.opacity(0.04), location: 0.45),
                        .init(color: Color.white.opacity(0), location: 0.46),
                    ]),
                    startPoint: CGPoint(x: screen.minX, y: screen.minY),
                    endPoint: CGPoint(x: screen.maxX, y: screen.maxY)
                )
            )
        }
    }

    static func drawRays(in context: inout GraphicsContext, canvasSize: CGSize) {
        prepare(&context, canvasSize: canvasSize)
        let screenPath = Path(roundedRect: screenRect, cornerRadius: screenCorner, style: .continuous)

        context.drawLayer { layer in
            layer.clip(to: screenPath)
            layer.drawLayer { glow in
                glow.addFilter(.blur(radius: 7))
                forEachDot { rect, kind in
                    if kind == .nearRay || kind == .farRay {
                        glow.fill(dotPath(rect), with: .color(Color(hex: "3DE0E0").opacity(kind == .nearRay ? 1 : 0.7)))
                    }
                }
            }
            forEachDot { rect, kind in
                switch kind {
                case .nearRay: layer.fill(dotPath(rect), with: .color(Color(hex: "9FF6FF")))
                case .farRay: layer.fill(dotPath(rect), with: .color(Color(hex: "9FF6FF").opacity(0.7)))
                default: break
                }
            }
        }
    }
}

#Preview {
    ZStack {
        DeckHandTheme.brandBackground()
        DeckHandMark(size: 172)
    }
    .ignoresSafeArea()
}
