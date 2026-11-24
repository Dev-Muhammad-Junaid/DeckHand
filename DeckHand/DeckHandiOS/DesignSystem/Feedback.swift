//
//  Feedback.swift
//  DeckHandiOS – Design system
//
//  Status pills, toasts, the dot beam, the loading dot wave, the PRO badge,
//  the glyph empty state, cards and the phosphor focus ring.
//  Spec: `02-Design-System.md` §7, `06-Pixel-Identity.md` §5–§6.
//

import SwiftUI

// MARK: - Status pill

/// Icon + one sentence + an optional Fix button. Replaces the old
/// `HostCapabilityBanner` strip.
struct StatusPill: View {
    enum Kind { case warning, info, locked }

    var kind: Kind = .warning
    /// The bold lead ("Studio is locked.").
    var title: String?
    let message: String
    var fixTitle: String?
    var onFix: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: PixelHandTheme.Space.md) {
            PHGlyph(glyph: glyph, pitch: PixelPitch.chip, accent: tint)
                .foregroundStyle(tint)
            (titleText + Text(message).foregroundColor(tint))
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let fixTitle, let onFix {
                Button(fixTitle, action: onFix)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .padding(.horizontal, PixelHandTheme.Space.md)
                    .frame(minHeight: 32)
                    .background(PixelHandTheme.raised, in: Capsule())
                    .frame(minHeight: PixelHandTheme.ControlHeight.hit)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, PixelHandTheme.Space.md)
        .padding(.vertical, PixelHandTheme.Space.xs)
        .frame(minHeight: PixelHandTheme.ControlHeight.standard)
        .background(background, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var titleText: Text {
        guard let title else { return Text("") }
        return Text(title + " ").bold().foregroundColor(PixelHandTheme.ink)
    }

    private var glyph: GlyphBitmap {
        switch kind {
        case .warning: PixelGlyphs.settings
        case .info: PixelGlyphs.mac
        case .locked: PixelGlyphs.lock
        }
    }

    private var tint: Color {
        kind == .info ? PixelHandTheme.accentInk : PixelHandTheme.warning
    }

    private var background: Color {
        kind == .info ? PixelHandTheme.accentTint : PixelHandTheme.warningTint
    }
}

// MARK: - Toast

/// A glass capsule with a status pixel and one line. Announced to VoiceOver
/// when it appears.
struct PHToast: View {
    let message: String
    var isFailure = false
    /// Overrides the pixel: `.off` while disconnected (a disconnected state
    /// never shows a lit mint dot, 04 §7, VQ-028).
    var pixel: StatusPixel.Kind?

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            StatusPixel(state: pixel ?? (isFailure ? .needsYou : .live), size: 8)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PixelHandTheme.ink)
                .lineLimit(2)
        }
        .padding(.leading, PixelHandTheme.Space.md)
        .padding(.trailing, 14)
        .frame(minHeight: 40)
        .phGlass(in: Capsule())
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

// MARK: - Dot beam

/// A row of 6 pt dots filling left to right for long waits (pairing,
/// transfers, AI planning). Turns mint on success. Replaces spinners on
/// brand surfaces.
struct DotBeam: View {
    enum Phase { case progress(Double), success, failure }

    var state: Phase = .progress(0)
    var count = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(color(for: index))
                    .frame(width: 6, height: 6)
                    .shadow(color: isLit(index) ? PixelHandTheme.Brand.glow.opacity(0.9) : .clear, radius: isLit(index) ? 3 : 0)
            }
        }
        .animation(PixelHandMotion.standard, value: litCount)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var litCount: Int {
        switch state {
        case .progress(let p): Int((min(max(p, 0), 1) * Double(count)).rounded(.down))
        case .success, .failure: count
        }
    }

    private func isLit(_ index: Int) -> Bool {
        if case .progress = state { return index < litCount }
        return false
    }

    private func color(for index: Int) -> Color {
        switch state {
        case .progress: index < litCount ? PixelHandTheme.Brand.glow : PixelHandTheme.fill2
        case .success: PixelHandTheme.success
        case .failure: PixelHandTheme.danger
        }
    }

    private var accessibilityText: String {
        switch state {
        case .progress(let p): "\(Int(min(max(p, 0), 1) * 100)) percent"
        case .success: "Done"
        case .failure: "Failed"
        }
    }
}

// MARK: - Loading dot wave

/// A 9 × 3 dot block with a brightness wave crossing it every 1.2 s (`cos³`
/// falloff). Replaces every spinner on brand surfaces. Reduce Motion: the
/// middle frame, static. Low Power Mode: 15 fps.
struct DotWave: View {
    var pitch: CGFloat = 8
    var label = "Loading"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                waveFrame(phase: 0.5)
            } else if ProcessInfo.processInfo.isLowPowerModeEnabled {
                TimelineView(.periodic(from: .now, by: 1.0 / 15)) { context in
                    waveFrame(phase: phase(at: context.date))
                }
            } else {
                TimelineView(.animation) { context in
                    waveFrame(phase: phase(at: context.date))
                }
            }
        }
        .frame(width: pitch * 9, height: pitch * 3)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private func phase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return t.truncatingRemainder(dividingBy: PixelHandMotion.wavePeriod) / PixelHandMotion.wavePeriod
    }

    private func waveFrame(phase: Double) -> some View {
        let pitch = self.pitch
        return Canvas { context, _ in
            let side = pitch * 0.78
            let o = (pitch - side) / 2
            for y in 0..<3 {
                for x in 0..<9 {
                    let v = max(0, cos((Double(x) / 8 - phase) * .pi * 1.6))
                    let lit = pow(v, 3)
                    let rect = CGRect(x: CGFloat(x) * pitch + o, y: CGFloat(y) * pitch + o, width: side, height: side)
                    let path = Path(roundedRect: rect, cornerRadius: side * 0.3)
                    context.fill(path, with: .color(PixelHandTheme.Brand.phosphor.opacity(0.18 + 0.82 * lit)))
                }
            }
        }
        .shadow(color: PixelHandTheme.Brand.glow.opacity(0.5), radius: 3)
    }
}

// MARK: - PRO badge

/// Sky → cobalt capsule with "PRO" in dot-matrix. Only on locked features and
/// the paywall.
struct ProBadge: View {
    var body: some View {
        DotMatrixText("PRO", pitch: 1.4, label: "Pro", glows: false)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: PixelHandTheme.ControlHeight.badge)
            .background(PixelHandTheme.Brand.tileGradient, in: Capsule())
    }
}

// MARK: - Empty state

/// On navy: the glyph at pitch 6 over its unlit grid with the accent dot
/// breathing, a `display.small` headline, one sentence, one or two actions.
struct PHEmptyState: View {
    let glyph: GlyphBitmap
    let title: String
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: PixelHandTheme.Space.lg) {
            PHGlyph(glyph: glyph, pitch: PixelPitch.emptyState, showsUnlit: true)
                .foregroundStyle(PixelHandTheme.Brand.phosphor)
                .phaseAnimator(reduceMotion ? [1.0] : [0.4, 1.0]) { content, opacity in
                    content.opacity(0.6 + 0.4 * opacity)
                } animation: { _ in
                    .easeInOut(duration: PixelHandMotion.breathe / 2)
                }
            VStack(spacing: PixelHandTheme.Space.xs) {
                Text(title)
                    .phText(.displaySmall)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .multilineTextAlignment(.center)
            HStack(spacing: PixelHandTheme.Space.sm) {
                if let primaryTitle, let primaryAction {
                    Button(primaryTitle, action: primaryAction).buttonStyle(.ph(.primary, size: .small))
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction).buttonStyle(.ph(.secondary, size: .small))
                }
            }
        }
        .padding(PixelHandTheme.Space.xl)
        .pixelOnNavy()
    }
}

// MARK: - Card and focus

extension View {
    /// `raised` with a 0.5 pt hairline; a 1 pt shadow in light, none in dark.
    func phCard(cornerRadius: CGFloat = PixelHandTheme.Radius.card) -> some View {
        modifier(PHCardModifier(cornerRadius: cornerRadius))
    }

    /// The phosphor focus ring: dotted, 3 pt outside the shape, `glow` on
    /// dark and `accent` on light, with a soft bloom.
    func phosphorFocus(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        modifier(PhosphorFocusModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }

    /// For a control (button, chip, key, tab): tracks its own keyboard focus
    /// and iPad pointer hover and draws the phosphor ring for either, with
    /// the system focus and hover effects off so only one ring shows.
    /// UX-018, `06-Pixel-Identity.md` §5.
    func phosphorFocusable(cornerRadius: CGFloat) -> some View {
        modifier(PhosphorFocusableModifier(cornerRadius: cornerRadius))
    }
}

private struct PhosphorFocusableModifier: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .focusEffectDisabled()
            .hoverEffectDisabled()
            .onHover { isHovered = $0 }
            .phosphorFocus(isFocused || isHovered, cornerRadius: cornerRadius)
    }
}

private struct PHCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(PixelHandTheme.raised, in: shape)
            .overlay(shape.strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline))
            .shadow(color: scheme == .dark ? .clear : PixelHandTheme.Brand.screen.opacity(0.06), radius: 1, y: 1)
    }
}

private struct PhosphorFocusModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let color = scheme == .dark ? PixelHandTheme.Brand.glow : PixelHandTheme.accent
        content.overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.01, 4]))
                    .padding(-3)
                    .shadow(color: color.opacity(0.5), radius: 9)
                    .allowsHitTesting(false)
            }
        }
    }
}

#Preview("Feedback") {
    ScrollView {
        VStack(spacing: 16) {
            StatusPill(kind: .locked, title: "Studio is locked.", message: "Type the password to unlock.", fixTitle: "Keyboard", onFix: {})
            StatusPill(message: "The Mac is missing Accessibility permission.")
            PHToast(message: "Build delivered to Studio")
            DotBeam(state: .progress(0.4))
            DotBeam(state: .success)
            ProBadge()
            PixelSurface(cornerRadius: PixelHandTheme.Radius.card) {
                VStack(spacing: 24) {
                    DotWave()
                    PHEmptyState(
                        glyph: PixelGlyphs.deck,
                        title: "No keys for Figma yet",
                        message: "Add keys from Figma’s menus.",
                        primaryTitle: "Suggest keys", primaryAction: {},
                        secondaryTitle: "Add a key", secondaryAction: {}
                    )
                }
                .padding(.vertical, 24)
            }
            Text("Card").padding(24).phCard().phosphorFocus(true, cornerRadius: PixelHandTheme.Radius.card)
        }
        .padding(16)
    }
    .background(.phCanvas)
}
