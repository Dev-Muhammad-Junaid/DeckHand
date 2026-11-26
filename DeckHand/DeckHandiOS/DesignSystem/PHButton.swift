//
//  PHButton.swift
//  DeckHandiOS – Design system
//
//  Buttons: primary (cobalt gradient, one per screen), secondary (fill),
//  tint, destructive, and glass circles for header chrome. Heights come from
//  the control scale (36 · 44 · 52); every target is at least 44 × 44.
//  Spec: `Product/Design/02-Design-System.md` §7, `07-Polish-Spec.md` §4.
//

import SwiftUI

struct PHButtonStyle: ButtonStyle {
    enum Kind {
        /// The one cobalt action per screen.
        case primary
        /// Quiet fill.
        case secondary
        /// Accent tint (AI panels, "Keep all").
        case tint
        /// Refused, destructive. Never next to the primary.
        case destructive
    }

    enum Size {
        /// 52 pt, `.headline`.
        case large
        /// 44 pt, `.subheadline` semibold.
        case regular
        /// 36 pt visual, 44 pt target.
        case small

        var height: CGFloat {
            switch self {
            case .large: PixelHandTheme.ControlHeight.primary
            case .regular: PixelHandTheme.ControlHeight.standard
            case .small: PixelHandTheme.ControlHeight.secondary
            }
        }

        var font: Font {
            self == .large ? .headline : .subheadline.weight(.semibold)
        }

        var horizontalPadding: CGFloat {
            self == .large ? PixelHandTheme.Space.xl : PixelHandTheme.Space.lg
        }
    }

    var kind: Kind = .primary
    var size: Size = .large
    /// Fills the available width (onboarding, sheets).
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        let fullWidth: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(size.font)
                // A button never wraps a word (build 18 QA: "E / di",
                // "Do / ne"). Inline buttons take their label's width and
                // the row around them gives way; full-width buttons may
                // take a second line at the largest sizes.
                .lineLimit(fullWidth ? 2 : 1)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
                .padding(.horizontal, size.horizontalPadding)
                .frame(minHeight: size.height)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(background, in: Capsule())
                .contentShape(Capsule())
                .frame(minHeight: PixelHandTheme.ControlHeight.hit)
                .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(PixelHandMotion.quick, value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary: .white
            case .secondary: PixelHandTheme.ink
            case .tint: PixelHandTheme.accentInk
            case .destructive: PixelHandTheme.danger
            }
        }

        private var background: AnyShapeStyle {
            switch kind {
            case .primary: AnyShapeStyle(PixelHandTheme.Brand.actionGradient)
            case .secondary: AnyShapeStyle(PixelHandTheme.fill2)
            case .tint: AnyShapeStyle(PixelHandTheme.accentTint)
            case .destructive: AnyShapeStyle(PixelHandTheme.dangerTint)
            }
        }
    }
}

extension ButtonStyle where Self == PHButtonStyle {
    static func ph(_ kind: PHButtonStyle.Kind = .primary, size: PHButtonStyle.Size = .large, fullWidth: Bool = false) -> PHButtonStyle {
        PHButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// A 44 pt glass circle with a glyph, for the header and toolbars. The
/// label is required: no unlabelled icon buttons.
struct GlassCircleButton: View {
    let glyph: GlyphBitmap
    let label: String
    var size: CGFloat = PixelHandTheme.ControlHeight.standard
    var isOn = false
    /// A badge on the circle's rim (the unseen dot, a count): drawn above
    /// the glass, never clipped (`ControlBadge`, OT-14).
    var badge: ControlBadgeKind?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PHGlyph(glyph: glyph, pitch: size >= 44 ? PixelPitch.header : 1.8)
                .foregroundStyle(isOn ? PixelHandTheme.accent : PixelHandTheme.ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .phGlass(in: Circle(), interactive: true)
        .controlBadge(badge, style: .circle())
        .phosphorFocusable(cornerRadius: size / 2)
        .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.hit)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview("Buttons") {
    VStack(spacing: 12) {
        Button("Find my Mac") {}.buttonStyle(.ph(fullWidth: true))
        Button("Back") {}.buttonStyle(.ph(.secondary, size: .regular))
        Button("Keep all") {}.buttonStyle(.ph(.tint, size: .small))
        Button("Forget this Mac") {}.buttonStyle(.ph(.destructive, size: .regular))
        HStack(spacing: 8) {
            GlassCircleButton(glyph: PixelGlyphs.capture, label: "Capture") {}
            GlassCircleButton(glyph: PixelGlyphs.settings, label: "Settings") {}
        }
    }
    .padding(16)
    .background(.phCanvas)
}
