//
//  OnboardingScene.swift
//  DeckHandiOS – Onboarding
//
//  The dot-art scene at the top of every onboarding page, all on the same
//  navy plate (radius 36, 15 pt resting grid, cobalt bloom) so pages 2–5
//  carry the welcome page's craft instead of a stock SF Symbol.
//
//    mark      the app mark with the dot hand (kept from page 1)
//    trackpad  a lit finger trail across the grid, two touch rings
//    mirror    the Mac's screen arriving under a scanline, LIVE strip
//    capture   a dotted phosphor region selection, the lifted text
//    pairing   Mac and iPhone glyphs (pitch 10) joined by a beam, Wi-Fi
//              above, the first 8 digits of a pairing code below
//
//  Each scene animates once per appearance (600–900 ms) and then holds its
//  final frame. Reduce Motion shows the final frame straight away.
//  Spec: `Product/Design/06-Pixel-Identity.md` §9, board "Onboarding, every page".
//

import SwiftUI

enum OnboardingScene: Hashable {
    case mark, trackpad, mirror, capture, pairing

    /// What VoiceOver reads for the artwork.
    var accessibilityLabel: String {
        switch self {
        case .mark: "The Pixel Hand mark"
        case .trackpad: "A finger trail lighting the dots of the trackpad"
        case .mirror: "Your Mac's screen arriving live"
        case .capture: "A region of the Mac's screen selected, with its text lifted out"
        case .pairing: "A Mac and an iPhone joined by a beam, with a pairing code below"
        }
    }

    /// How long the intro animation runs.
    var duration: Double {
        switch self {
        case .mark: PixelHandMotion.powerOnDuration
        case .trackpad: 0.9
        case .mirror: 0.8
        case .capture: 0.9
        case .pairing: 0.8
        }
    }
}

struct OnboardingSceneView: View {
    let scene: OnboardingScene
    /// Edge of the square plate: 400 / 340 / 248 by size class.
    let size: CGFloat

    var body: some View {
        Group {
            if scene == .mark {
                DeckHandMark(size: size * 0.78)
                    .frame(width: size, height: size)
            } else {
                SceneClock(duration: scene.duration) { progress in
                    plate { content(progress: progress) }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(scene.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private func plate<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        PixelSurface(cornerRadius: PixelHandTheme.Radius.sheet) {
            content()
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.sheet, style: .continuous))
        // No glow here: the page's pixel dissolve masks this view to its
        // square frame, which cut the glow into a hard-edged square behind
        // the rounded card (VQ-004). `OnboardingSceneGlow` draws it
        // outside the transition instead.
    }

    @ViewBuilder
    private func content(progress: Double) -> some View {
        switch scene {
        case .mark: EmptyView()
        case .trackpad: TrackpadScene(size: size, progress: progress)
        case .mirror: MirrorScene(size: size, progress: progress)
        case .capture: CaptureScene(size: size, progress: progress)
        case .pairing: PairingScene(size: size, progress: progress)
        }
    }
}

/// The cobalt glow behind a scene's plate, drawn outside the page
/// transition so nothing clips it; matches the plate's concentric radius.
struct OnboardingSceneGlow: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.sheet, style: .continuous)
            .fill(PixelHandTheme.Brand.screen)
            .frame(width: size, height: size)
            .shadow(color: PixelHandTheme.Brand.cobalt.opacity(0.45), radius: size * 0.1)
            .accessibilityHidden(true)
    }
}

// MARK: - Clock

/// Drives a scene's intro once per appearance: 0 → 1 over `duration` with an
/// ease-out, then stops redrawing. Reduce Motion: 1 from the start.
private struct SceneClock<Content: View>: View {
    let duration: Double
    @ViewBuilder let content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var isFinished = false

    var body: some View {
        if reduceMotion || isFinished {
            content(1)
        } else {
            TimelineView(.animation) { context in
                content(eased(context.date))
            }
            .onAppear { start = Date() }
            .task {
                try? await Task.sleep(for: .seconds(duration + 0.05))
                isFinished = true
            }
        }
    }

    private func eased(_ date: Date) -> Double {
        let t = min(max(date.timeIntervalSince(start) / duration, 0), 1)
        return 1 - pow(1 - t, 3)
    }
}

// MARK: - Shared pieces

/// The scene's scale against the board's 320 pt reference plate.
private func sceneScale(_ size: CGFloat) -> CGFloat { size / 320 }

/// The Mac's desktop in the app's palette: navy wallpaper with a cobalt lift,
/// menu bar, an editor window, a smaller window and the Dock. A still frame,
/// drawn rather than bundled so it stays crisp at every scene size.
private struct MiniMacDesktop: View {
    var showsDialog = false

    var body: some View {
        let showsDialog = self.showsDialog
        Canvas { context, size in
            let w = size.width, h = size.height
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(
                Path(bounds),
                with: .linearGradient(
                    Gradient(colors: [PixelHandTheme.Brand.cobalt.opacity(0.9), PixelHandTheme.Brand.screenLift, PixelHandTheme.Brand.screen]),
                    startPoint: CGPoint(x: w * 0.1, y: 0),
                    endPoint: CGPoint(x: w * 0.9, y: h)
                )
            )
            // Menu bar.
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.06)), with: .color(.black.opacity(0.35)))
            for i in 0..<4 {
                let x = w * (0.04 + CGFloat(i) * 0.06)
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: h * 0.022, width: w * 0.04, height: h * 0.018), cornerRadius: 1),
                    with: .color(.white.opacity(i == 0 ? 0.85 : 0.45))
                )
            }
            // Editor window.
            let editor = CGRect(x: w * 0.07, y: h * 0.14, width: w * 0.62, height: h * 0.62)
            Self.window(in: &context, rect: editor, lines: 7)
            // Side window.
            let side = CGRect(x: w * 0.6, y: h * 0.3, width: w * 0.33, height: h * 0.4)
            Self.window(in: &context, rect: side, lines: 3)
            if showsDialog {
                let dialog = CGRect(x: w * 0.26, y: h * 0.32, width: w * 0.34, height: h * 0.24)
                context.fill(
                    Path(roundedRect: dialog, cornerRadius: h * 0.03),
                    with: .color(Color(white: 0.98))
                )
                let button = CGRect(x: dialog.maxX - dialog.width * 0.38, y: dialog.maxY - dialog.height * 0.32, width: dialog.width * 0.3, height: dialog.height * 0.2)
                context.fill(Path(roundedRect: button, cornerRadius: button.height / 2), with: .color(PixelHandTheme.Brand.cobaltHigh))
                context.fill(
                    Path(roundedRect: CGRect(x: dialog.minX + dialog.width * 0.1, y: dialog.minY + dialog.height * 0.2, width: dialog.width * 0.7, height: dialog.height * 0.1), cornerRadius: 1),
                    with: .color(.black.opacity(0.5))
                )
            }
            // Dock.
            let dock = CGRect(x: w * 0.28, y: h * 0.86, width: w * 0.44, height: h * 0.1)
            context.fill(Path(roundedRect: dock, cornerRadius: dock.height * 0.3), with: .color(.white.opacity(0.18)))
            let colors: [Color] = [PixelHandTheme.Brand.sky, PixelHandTheme.Brand.mint, PixelHandTheme.Brand.pixelViolet, .orange, PixelHandTheme.Brand.cobaltHigh, .white]
            let tile = dock.height * 0.66
            let gap = (dock.width - tile * CGFloat(colors.count)) / CGFloat(colors.count + 1)
            for (i, color) in colors.enumerated() {
                let rect = CGRect(x: dock.minX + gap + CGFloat(i) * (tile + gap), y: dock.midY - tile / 2, width: tile, height: tile)
                context.fill(Path(roundedRect: rect, cornerRadius: tile * 0.24), with: .color(color.opacity(0.9)))
            }
        }
    }

    nonisolated private static func window(in context: inout GraphicsContext, rect: CGRect, lines: Int) {
        let radius = rect.height * 0.06
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(Color(red: 0.953, green: 0.957, blue: 0.976)))
        let bar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.12)
        context.fill(
            Path(roundedRect: bar, cornerRadius: radius),
            with: .color(Color(red: 0.88, green: 0.89, blue: 0.93))
        )
        let lights: [Color] = [Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)]
        let d = bar.height * 0.42
        for (i, color) in lights.enumerated() {
            context.fill(
                Path(ellipseIn: CGRect(x: bar.minX + d * (0.9 + CGFloat(i) * 1.6), y: bar.midY - d / 2, width: d, height: d)),
                with: .color(color)
            )
        }
        let lineHeight = max(rect.height * 0.045, 1.5)
        let top = bar.maxY + rect.height * 0.08
        let step = (rect.height - bar.height - rect.height * 0.14) / CGFloat(max(lines, 1))
        for i in 0..<lines {
            let widths: [CGFloat] = [0.7, 0.55, 0.82, 0.4, 0.66, 0.5, 0.74]
            let line = CGRect(
                x: rect.minX + rect.width * (i % 3 == 1 ? 0.14 : 0.08),
                y: top + CGFloat(i) * step,
                width: rect.width * widths[i % widths.count] * 0.86,
                height: lineHeight
            )
            let color: Color = i == 3 ? PixelHandTheme.Brand.cobaltHigh.opacity(0.7) : .black.opacity(0.22)
            context.fill(Path(roundedRect: line, cornerRadius: lineHeight / 2), with: .color(color))
        }
    }
}

/// The Mac's screen frame inside a scene: 82 % of the plate, 16 : 10, 20 % down.
private struct MacScreenFrame {
    let rect: CGRect

    init(plate size: CGFloat) {
        let w = (size * 0.82).rounded()
        let h = (w / 1.6).rounded()
        rect = CGRect(x: ((size - w) / 2).rounded(), y: (size * 0.2).rounded(), width: w, height: h)
    }
}

// MARK: - Trackpad

/// The resting grid with a lit trail: the finger enters bottom-left and curves
/// up to the right, the dots under it brightening and growing, then two touch
/// rings settle where it stops. Uses the grid maths of `RestingDotGrid` so the
/// lit dots sit exactly on the resting ones.
private struct TrackpadScene: View {
    let size: CGFloat
    let progress: Double

    var body: some View {
        let size = self.size
        let progress = self.progress
        let k = sceneScale(size)
        let end = Self.trailPoint(1, size: size)
        ZStack(alignment: .topLeading) {
            Canvas { context, canvasSize in
                let pitch: CGFloat = 15
                let columns = Int(canvasSize.width / pitch)
                let rows = Int(canvasSize.height / pitch)
                let x0 = (canvasSize.width - CGFloat(columns - 1) * pitch) / 2
                let y0 = (canvasSize.height - CGFloat(rows - 1) * pitch) / 2
                // Samples along the drawn part of the trail; each is brighter
                // and wider than the last, like the afterglow behind a drag.
                let samples: [(CGPoint, CGFloat, Double)] = (0...20).compactMap { n in
                    let t = Double(n) / 20
                    guard t <= progress else { return nil }
                    let radius = CGFloat(18 + 44 * t) * k
                    return (Self.trailPoint(t, size: size), radius, 0.25 + 0.75 * t)
                }
                var glowLayer = context
                glowLayer.addFilter(.shadow(color: PixelHandTheme.Brand.glow.opacity(0.8), radius: 3))
                for row in 0..<max(rows, 0) {
                    for column in 0..<max(columns, 0) {
                        let c = CGPoint(x: (x0 + CGFloat(column) * pitch).rounded(), y: (y0 + CGFloat(row) * pitch).rounded())
                        var level = 0.0
                        for (p, radius, intensity) in samples {
                            let d = hypot(c.x - p.x, c.y - p.y)
                            guard d < radius else { continue }
                            let falloff = 1 - Double(d / radius)
                            level = max(level, falloff * falloff * intensity)
                        }
                        guard level > 0.04 else { continue }
                        let side = 2.4 + 4.6 * CGFloat(level)
                        let rect = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
                        glowLayer.fill(
                            Path(roundedRect: rect, cornerRadius: side * 0.3),
                            with: .color(PixelHandTheme.Brand.phosphor.opacity(0.35 + 0.65 * level))
                        )
                    }
                }
            }
            // Two touch rings where the fingers rest.
            let ringOpacity = max(0, (progress - 0.7) / 0.3)
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .strokeBorder(PixelHandTheme.Brand.phosphor.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 44 * k, height: 44 * k)
                    .shadow(color: PixelHandTheme.Brand.glow.opacity(0.7), radius: 4)
                    .position(
                        x: end.x + (index == 0 ? 0 : 34 * k),
                        y: end.y + (index == 0 ? 0 : -12 * k)
                    )
                    .scaleEffect(0.8 + 0.2 * ringOpacity)
                    .opacity(ringOpacity)
            }
            StatusStrip(items: ["2 FINGERS", "SCROLL"], pitch: 1.6, accessibilityText: "Two fingers to scroll")
                .padding(16 * k)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .opacity(min(1, progress * 2))
        }
        .frame(width: size, height: size)
    }

    /// The board's trail: x from 20 % to 75 %, y a gentle upward curve.
    nonisolated private static func trailPoint(_ t: Double, size: CGFloat) -> CGPoint {
        CGPoint(
            x: size * CGFloat(0.2 + 0.55 * t),
            y: size * CGFloat(0.74 - 0.42 * t + 0.25 * t * t)
        )
    }
}

// MARK: - Mirror

/// The Mac's screen arriving top to bottom under a cyan scanline; below the
/// line is still black. The scanline fades once the frame is complete.
private struct MirrorScene: View {
    let size: CGFloat
    let progress: Double

    var body: some View {
        let frame = MacScreenFrame(plate: size).rect
        let k = sceneScale(size)
        let reveal = CGFloat(progress)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .top) {
                MiniMacDesktop(showsDialog: true)
                Color.black
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: frame.height * (1 - reveal))
                    }
                // Scanline and its trailing glow.
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, PixelHandTheme.Brand.glow.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16 * k)
                    Rectangle()
                        .fill(PixelHandTheme.Brand.phosphor)
                        .frame(height: 1.5)
                        .shadow(color: PixelHandTheme.Brand.glow, radius: 6)
                }
                .offset(y: frame.height * reveal - 16 * k)
                .opacity(progress < 1 ? 1 : 0)
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 10 * k, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10 * k, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .offset(x: frame.minX, y: frame.minY)

            // The mirror's settings top out at 30 fps (VQ-018).
            StatusStrip(items: ["LIVE", "30 FPS"], pitch: 1.6, accessibilityText: "Live, 30 frames per second")
                .offset(x: frame.minX + 8 * k, y: frame.minY + 8 * k)

            // A small iPhone-sized pane under the screen, the live view in hand.
            HStack(spacing: 8 * k) {
                PHGlyph(glyph: PixelGlyphs.pictureInPicture, pitch: size >= 300 ? 3 : 2.2)
                    .foregroundStyle(PixelHandTheme.Brand.phosphor)
                DotMatrixText("PINCH TO READ", pitch: size >= 300 ? 2 : 1.6, label: "Pinch to read", stepsWithType: false)
                    .foregroundStyle(PixelHandTheme.Brand.phosphor)
                    .accessibilityHidden(true)
            }
            .offset(x: frame.minX + 4 * k, y: frame.maxY + 22 * k)
            .opacity(max(0, (progress - 0.6) / 0.4))
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

// MARK: - Capture

/// The desktop dimmed outside a marching dotted phosphor selection, the
/// selection's corner handles, and the text lifted out of it in dot-matrix.
private struct CaptureScene: View {
    let size: CGFloat
    let progress: Double

    var body: some View {
        let frame = MacScreenFrame(plate: size).rect
        let k = sceneScale(size)
        let selection = CGRect(
            x: frame.width * 0.18,
            y: frame.height * 0.26,
            width: frame.width * 0.52 * CGFloat(min(1, progress * 1.4)),
            height: frame.height * 0.46 * CGFloat(min(1, progress * 1.4))
        )
        let textReveal = max(0, (progress - 0.55) / 0.45)
        let pitch: CGFloat = size >= 380 ? 2.6 : size >= 300 ? 2.2 : 1.6
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                MiniMacDesktop()
                // Dim everything outside the selection.
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle()
                            .overlay(alignment: .topLeading) {
                                Rectangle()
                                    .frame(width: selection.width, height: selection.height)
                                    .offset(x: selection.minX, y: selection.minY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                Rectangle()
                    .strokeBorder(
                        PixelHandTheme.Brand.phosphor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5], dashPhase: CGFloat(progress) * 30)
                    )
                    .shadow(color: PixelHandTheme.Brand.glow.opacity(0.8), radius: 3)
                    .frame(width: selection.width, height: selection.height)
                    .offset(x: selection.minX, y: selection.minY)
                ForEach(0..<4, id: \.self) { corner in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(PixelHandTheme.Brand.phosphor)
                        .frame(width: 7, height: 7)
                        .position(
                            x: selection.minX + (corner % 2 == 0 ? 0 : selection.width),
                            y: selection.minY + (corner < 2 ? 0 : selection.height)
                        )
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 10 * k, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10 * k, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .offset(x: frame.minX, y: frame.minY)

            VStack(alignment: .leading, spacing: 8 * k) {
                DotMatrixText("BUILD FAILED", pitch: pitch, label: "Build failed", stepsWithType: false)
                DotMatrixText("MAIN.SWIFT:42", pitch: pitch, label: "main.swift, line 42", stepsWithType: false)
            }
            .foregroundStyle(PixelHandTheme.Brand.phosphor)
            .accessibilityHidden(true)
            .offset(x: frame.minX, y: frame.maxY + 16 * k)
            .opacity(textReveal)
            .offset(y: (1 - textReveal) * 6)
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

// MARK: - Pairing

/// Wi-Fi glyph above the Mac and iPhone glyphs at pitch 10 (6 on small
/// plates), a beam filling between them, and the first eight digits of a
/// pairing code in dot-matrix numerals.
private struct PairingScene: View {
    let size: CGFloat
    let progress: Double

    var body: some View {
        let large = size >= 300
        let glyphPitch: CGFloat = large ? CGFloat(PixelPitch.hero) : 6
        let k = sceneScale(size)
        VStack(spacing: 18 * k) {
            PHGlyph(glyph: PixelGlyphs.wifi, pitch: large ? 4 : 3)
                .foregroundStyle(Color(red: 0.81, green: 0.88, blue: 1))
                .opacity(min(1, progress * 2))
            HStack(spacing: 12 * k) {
                PHGlyph(glyph: PixelGlyphs.mac, pitch: glyphPitch, showsUnlit: true)
                DotBeam(state: .progress(progress), count: 5)
                    .accessibilityHidden(true)
                PHGlyph(glyph: PixelGlyphs.iPhone, pitch: glyphPitch, showsUnlit: true)
            }
            .foregroundStyle(Color(red: 0.81, green: 0.88, blue: 1))
            DotMatrixText("4821 0934", pitch: large ? 3 : 2.2, label: "Example pairing code", stepsWithType: false)
                .foregroundStyle(PixelHandTheme.Brand.phosphor)
                .accessibilityHidden(true)
                .opacity(max(0, (progress - 0.5) / 0.5))
        }
        .frame(width: size, height: size)
    }
}

#Preview("Scenes") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach([OnboardingScene.mark, .trackpad, .mirror, .capture, .pairing], id: \.self) { scene in
                OnboardingSceneView(scene: scene, size: 340)
            }
            OnboardingSceneView(scene: .capture, size: 248)
        }
        .padding(24)
    }
    .background(PixelHandTheme.brandBackground())
}
