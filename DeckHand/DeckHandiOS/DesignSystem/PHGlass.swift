//
//  PHGlass.swift
//  DeckHandiOS – Design system
//
//  Chrome material. Liquid Glass on iOS 26 (controls and navigation only:
//  never on the trackpad, keys, chips or the mirror picture), a thin
//  material before that, and solid `navBar` / `elevated` under Reduce
//  Transparency. Spec: `Product/Design/02-Design-System.md` §2.
//

import SwiftUI

struct PHGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    /// `.interactive()` only on glass that responds to touch.
    var interactive = false
    /// Tinted glass for the one primary chrome action.
    var tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.pixelOnNavy) private var onNavy

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(solidFill, in: shape)
                .overlay(shape.strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline))
        } else {
            glass(content)
        }
    }

    private var solidFill: Color {
        if let tint { return tint }
        return onNavy ? PixelHandTheme.Brand.navBar : PixelHandTheme.elevated
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(glassStyle, in: shape)
        } else {
            materialFallback(content)
        }
        #else
        materialFallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glassStyle: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif

    private func materialFallback(_ content: Content) -> some View {
        content
            .background {
                if let tint {
                    shape.fill(tint)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(onNavy ? 0.16 : 0.5), lineWidth: PixelHandTheme.Stroke.hairline))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

extension View {
    /// Liquid Glass (or its fallback) behind this chrome, in `shape`.
    func phGlass<S: InsettableShape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(PHGlassBackground(shape: shape, interactive: interactive, tint: tint))
    }

    /// Groups neighbouring glass so it morphs together on iOS 26.
    @ViewBuilder
    func phGlassGroup(spacing: CGFloat = PixelHandTheme.Space.sm) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
