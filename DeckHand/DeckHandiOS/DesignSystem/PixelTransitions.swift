//
//  PixelTransitions.swift
//  DeckHandiOS – Design system
//
//  The pixel transitions (UX-017, `06-Pixel-Identity.md` §7):
//
//  - Pixel dissolve: the outgoing view breaks into 8 pt cells (6 pt on
//    compact widths) in a seeded order while the incoming one fills in
//    behind a band of phosphor dots. 280 ms, linear. Surfaces, onboarding
//    pages. Reduce Motion: a 160 ms cross-fade.
//  - Power-on: brightness 0 → 115 % at 210 ms → 100 % by 600 ms. Connected,
//    pairing success, Pro unlocked. Reduce Motion: instant, no flash.
//  - Scanline: `mirrorScanline(on:)` in `Mirror/MirrorPixelChrome.swift`,
//    timed by `PixelHandMotion.scanlineDuration`.
//
//  The dissolve draws its mask and its edge with stitchable Metal shaders
//  (`PixelTransitions.metal`) rather than running a layer effect over the
//  content, so surfaces backed by UIKit views (the trackpad, the mirror's
//  video layer) dissolve too instead of rasterising to a placeholder.
//  Timings come from `PixelTransitionPlan` in Core, where they're tested.
//

import SwiftUI

// MARK: - Motion

extension PixelHandMotion {
    /// The animation that drives `transition`; Reduce Motion gives the
    /// plan's fallback (a 160 ms cross-fade, or none for the power-on).
    static func animation(for transition: PixelTransition, reduceMotion: Bool) -> Animation? {
        let timing = PixelTransitionPlan.timing(transition, reduceMotion: reduceMotion)
        switch timing.effect {
        case .instant:
            return nil
        case .pixel, .fade:
            switch timing.curve {
            case .linear: return .linear(duration: timing.duration)
            case .easeOut: return .easeOut(duration: timing.duration)
            case .easeInOut: return .easeInOut(duration: timing.duration)
            }
        }
    }

    /// Surface and Mac switches: the dissolve's 280 ms linear threshold, or
    /// the 160 ms cross-fade under Reduce Motion.
    static func dissolve(reduceMotion: Bool) -> Animation {
        animation(for: .dissolve, reduceMotion: reduceMotion) ?? reducedFade
    }
}

// MARK: - Pixel dissolve

extension AnyTransition {
    /// The pixel dissolve on 8 pt cells. Gate it on Reduce Motion at the
    /// call site, or use `pixelDissolve(reduceMotion:isCompact:)`.
    static var pixelDissolve: AnyTransition {
        pixelDissolve(cell: PixelHandMotion.dissolveCell)
    }

    /// The pixel dissolve, or a cross-fade under Reduce Motion. Compact
    /// widths use 6 pt cells. Animate with `PixelHandMotion.dissolve(reduceMotion:)`.
    static func pixelDissolve(reduceMotion: Bool, isCompact: Bool = false) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return pixelDissolve(cell: isCompact ? PixelHandMotion.dissolveCellCompact : PixelHandMotion.dissolveCell)
    }

    /// The pixel dissolve on `cell`-point cells. The incoming and outgoing
    /// views share `seed`, so between them every cell is covered once.
    static func pixelDissolve(cell: CGFloat, seed: Float = 0) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PixelDissolveModifier(progress: 0, isOutgoing: false, cell: cell, seed: seed),
                identity: PixelDissolveModifier(progress: 1, isOutgoing: false, cell: cell, seed: seed)
            ),
            removal: .modifier(
                active: PixelDissolveModifier(progress: 1, isOutgoing: true, cell: cell, seed: seed),
                identity: PixelDissolveModifier(progress: 0, isOutgoing: true, cell: cell, seed: seed)
            )
        )
    }
}

/// Masks a view to the cells it shows at `progress`, and draws the phosphor
/// edge on the incoming side. At rest the mask is a plain full rectangle and
/// the shaders are off, so the view keeps its identity, state and hit
/// testing.
struct PixelDissolveModifier: ViewModifier, Animatable {
    var progress: Double
    let isOutgoing: Bool
    let cell: CGFloat
    let seed: Float

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let isRunning = p > 0 && p < 1
        // At the ends the mask is all or nothing; in between the shader
        // picks cells.
        let isVisibleAtRest = isOutgoing ? p <= 0 : p >= 1
        let band = Float(PixelTransitionPlan.dissolveEdgeBand)
        content
            .mask {
                Rectangle()
                    .fill(Color.black.opacity(isRunning || isVisibleAtRest ? 1 : 0))
                    .colorEffect(
                        ShaderLibrary.pixelDissolveMask(
                            .float(Float(p)), .float(Float(cell)), .float(seed),
                            .float(isOutgoing ? 1 : 0), .float(band)
                        ),
                        isEnabled: isRunning
                    )
            }
            .overlay {
                Rectangle()
                    .fill(PixelHandTheme.Brand.phosphor)
                    .colorEffect(
                        ShaderLibrary.pixelDissolveEdge(
                            .float(Float(p)), .float(Float(cell)), .float(seed), .float(band)
                        ),
                        isEnabled: isRunning && !isOutgoing
                    )
                    .opacity(isRunning && !isOutgoing ? 1 : 0)
                    .shadow(color: PixelHandTheme.Brand.glow.opacity(isRunning && !isOutgoing ? 0.6 : 0), radius: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

// MARK: - Power-on

extension View {
    /// Powers the view on (brightness 0 → 115 % → 100 % over 600 ms) each
    /// time `isOn` turns true. Reduce Motion: no flash, the view just shows.
    func powerOn(when isOn: Bool) -> some View {
        modifier(PowerOnModifier(isOn: isOn))
    }
}

private struct PowerOnModifier: ViewModifier {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var count = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: count) { view, level in
                view
                    .opacity(min(level, 1))
                    // Above 100 % the overshoot reads as a phosphor wash. An
                    // overlay rather than `.brightness`, which would
                    // rasterise UIKit-backed content.
                    .overlay {
                        PixelHandTheme.Brand.glow
                            .opacity(max(0, level - 1) * 0.6)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            } keyframes: { _ in
                MoveKeyframe(0.0)
                CubicKeyframe(PixelTransitionPlan.powerOnBrightness[1], duration: PixelTransitionPlan.powerOnPeakTime)
                CubicKeyframe(
                    PixelTransitionPlan.powerOnBrightness[2],
                    duration: PixelTransitionPlan.powerOnDuration - PixelTransitionPlan.powerOnPeakTime
                )
            }
            .onChange(of: isOn) { _, isOn in
                if isOn && !reduceMotion { count += 1 }
            }
    }
}

// MARK: - Previews

private struct DissolvePreview: View {
    @State private var showsDeck = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Group {
                    if showsDeck {
                        PHEmptyState(glyph: PixelGlyphs.deck, title: "Deck", message: "Keys for the app in front.")
                    } else {
                        PHEmptyState(glyph: PixelGlyphs.pointer, title: "Pointer", message: "The trackpad.")
                    }
                }
                .id(showsDeck)
                .transition(.pixelDissolve(reduceMotion: reduceMotion))
            }
            .frame(width: 320, height: 300)
            .background(PixelHandTheme.Brand.screen, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card))
            Button("Switch") {
                withAnimation(PixelHandMotion.dissolve(reduceMotion: reduceMotion)) { showsDeck.toggle() }
            }
            .buttonStyle(.ph(.primary, size: .small))
        }
        .padding(24)
    }
}

#Preview("Pixel dissolve") {
    DissolvePreview()
}
