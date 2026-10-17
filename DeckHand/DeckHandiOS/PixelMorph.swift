//
//  PixelMorph.swift
//  DeckHandiOS
//
//  The approval glyph. While the Mac decides, the dot hand's rays pulse
//  slowly; when the answer comes, its dots rearrange outward from the
//  centre into a mint check or a red cross.
//

import SwiftUI

enum ApprovalGlyph: Equatable {
    case waiting
    case approved
    case denied
    case disconnected

    /// Maps the authorization status strings `AuthorizationOverlay` uses.
    init(status: String) {
        switch status {
        case "granted": self = .approved
        case "denied": self = .denied
        case "host_disconnected": self = .disconnected
        default: self = .waiting
        }
    }

    var bitmap: PixelBitmap {
        switch self {
        case .waiting: PixelArt.handWithRays
        case .approved: PixelArt.check
        case .denied: PixelArt.cross
        case .disconnected:
            PixelArt.handWithRays.replacing(.ray, with: .off).replacing(.farRay, with: .off)
        }
    }

    /// Drawn on a `PixelScreen`, so the status colors resolve dark.
    var palette: PixelPalette {
        switch self {
        case .waiting: .brand
        case .approved: .solid(DeckHandTheme.success)
        case .denied: .solid(DeckHandTheme.danger)
        case .disconnected:
            PixelPalette(
                outline: DeckHandTheme.warning,
                fill: DeckHandTheme.Brand.pixelViolet.opacity(0.25),
                detail: DeckHandTheme.warning,
                ray: DeckHandTheme.warning,
                glow: DeckHandTheme.warning.opacity(0.6),
                unlit: DeckHandTheme.Brand.dotOff
            )
        }
    }

    /// Only the waiting hand moves on its own.
    var breathes: Bool { self == .waiting }
}

struct PixelMorph: View {
    let glyph: ApprovalGlyph
    /// Distance between dot centres, in points.
    var pitch: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glyph being dissolved out of, during a change.
    @State private var previous: ApprovalGlyph?
    @State private var changedAt: TimeInterval = 0
    @State private var changeCount = 0

    /// Longest delay (the corners) plus one dot's fade.
    static let duration: TimeInterval = 0.7
    /// How long one dot takes to change.
    static let dotDuration: TimeInterval = 0.28
    /// One full breath of the waiting rays.
    static let breathPeriod: TimeInterval = 1.6

    var body: some View {
        let glyph = self.glyph
        let previous = self.previous
        let changedAt = self.changedAt
        let pitch = self.pitch
        let breathes = glyph.breathes && !reduceMotion
        // A slow breath doesn't need the full ProMotion rate; a change does.
        let interval: Double? = previous == nil ? 1.0 / 30 : nil
        TimelineView(.animation(minimumInterval: interval, paused: previous == nil && !breathes)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let wave: Double = 0.5 + 0.5 * sin(now * 2 * Double.pi / Self.breathPeriod)
            let breath: Double = breathes ? 0.35 + 0.65 * wave : 1
            Canvas { context, _ in
                Self.draw(
                    glyph: glyph,
                    previous: previous,
                    elapsed: now - changedAt,
                    breath: breath,
                    pitch: pitch,
                    in: &context
                )
            }
        }
        .frame(width: CGFloat(PixelArt.stageWidth) * pitch, height: CGFloat(PixelArt.stageHeight) * pitch)
        .onChange(of: glyph) { old, _ in
            // Under Reduce Motion the new glyph simply replaces the old one.
            guard !reduceMotion else { return }
            previous = old
            changedAt = Date.timeIntervalSinceReferenceDate
            changeCount += 1
            let change = changeCount
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.duration))
                if changeCount == change { previous = nil }
            }
        }
        .accessibilityHidden(true)
    }

    private static func draw(
        glyph: ApprovalGlyph,
        previous: ApprovalGlyph?,
        elapsed: TimeInterval,
        breath: Double,
        pitch: CGFloat,
        in context: inout GraphicsContext
    ) {
        let target = glyph.bitmap
        let palette = glyph.palette
        let cx = Double(PixelArt.stageWidth - 1) / 2
        let cy = Double(PixelArt.stageHeight - 1) / 2

        /// 0 → 1 for one dot: changes start at the centre and spread out,
        /// with a little per-dot jitter so the edge isn't a perfect circle.
        func progress(_ x: Int, _ y: Int) -> Double {
            guard previous != nil else { return 1 }
            let jitter = Double((x * 73 + y * 151) % 97) / 97
            let delay = hypot(Double(x) - cx, Double(y) - cy) * 0.022 + jitter * 0.05
            let k = min(1, max(0, (elapsed - delay) / dotDuration))
            return 1 - pow(1 - k, 3)
        }

        // Every dot, unlit, underneath.
        PixelPainter.draw(target, in: &context, pitch: pitch, glow: nil) { _, _, _ in
            (palette.unlit, 1)
        }

        if let previous {
            let fromPalette = previous.palette
            PixelPainter.draw(previous.bitmap, in: &context, pitch: pitch, glow: fromPalette.glow) { x, y, kind in
                kind == .off ? (.clear, 0) : (fromPalette.color(for: kind), 1 - progress(x, y))
            }
        }

        PixelPainter.draw(target, in: &context, pitch: pitch, glow: palette.glow) { x, y, kind in
            guard kind != .off else { return (.clear, 0) }
            let isRay = kind == .ray || kind == .farRay
            return (palette.color(for: kind), progress(x, y) * (isRay ? breath : 1))
        }
    }
}
