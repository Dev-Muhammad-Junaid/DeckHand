//
//  CaptureChrome.swift
//  DeckHandiOS – Capture
//
//  The parts every capture flow is built from (UX-009): the navy stage with
//  the resting dot grid, the header (close glyph, dot-matrix status strip,
//  one trailing action), round glyph buttons, the action dock with glyph +
//  label items and a phosphor press flash, and the annotation inks.
//  Words and sizes come from Core (`CaptureSheetChrome`).
//  Spec: `Product/Design/05-Implementation-Plan.md` UX-009,
//  `06-Pixel-Identity.md`, `07-Polish-Spec.md`.
//

import SwiftUI
import UIKit

// MARK: - Stage

/// The navy instrument panel every capture step sits on: `screen` with the
/// resting dot grid, edge to edge.
struct CaptureStage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            PixelHandTheme.Brand.screen.ignoresSafeArea()
            RestingDotGrid()
                .opacity(0.55)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            content()
        }
        .pixelOnNavy()
        // System pieces inside (menus, dialogs, text selection) read dark on
        // the navy stage, in both appearances.
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Header

/// Close glyph · status strip · one trailing action. 44 pt tall, the strip
/// takes whatever room is left and drops items from its end.
struct CaptureHeader<Trailing: View>: View {
    let strip: CaptureStrip
    var style: StatusStrip.Style = .live
    var closeGlyph: GlyphBitmap = PixelGlyphs.close
    let closeLabel: String
    let onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            CaptureIconButton(glyph: closeGlyph, label: closeLabel, action: onClose)
            StatusStrip(items: strip.items, style: style, pitch: 1.6, accessibilityText: strip.spoken)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: PixelHandTheme.ControlHeight.hit)
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.top, PixelHandTheme.Space.sm)
    }
}

extension CaptureHeader where Trailing == EmptyView {
    init(strip: CaptureStrip, style: StatusStrip.Style = .live, closeGlyph: GlyphBitmap = PixelGlyphs.close, closeLabel: String, onClose: @escaping () -> Void) {
        self.init(strip: strip, style: style, closeGlyph: closeGlyph, closeLabel: closeLabel, onClose: onClose) { EmptyView() }
    }
}

// MARK: - Buttons

/// A 36 pt raised navy circle with a white glyph, in a 44 pt target.
struct CaptureIconButton: View {
    let glyph: GlyphBitmap
    let label: String
    var isOn = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            GestureHaptic.light.trigger()
            action()
        } label: {
            PHGlyph(glyph: glyph, pitch: 2, accent: isOn ? PixelHandTheme.Brand.phosphor : nil)
                .foregroundStyle(isOn ? PixelHandTheme.Brand.phosphor : Color.white)
                .frame(width: 36, height: 36)
                .background(PixelHandTheme.Brand.screenRaised, in: Circle())
                .overlay(Circle().strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline))
                .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(CapturePressStyle(shape: Circle()))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.hit / 2)
    }
}

/// A dock item: the glyph over a one-word label; glyph only at the
/// accessibility sizes (the label is still spoken). While busy the glyph
/// becomes the loading dot wave.
struct CaptureActionButton: View {
    let glyph: GlyphBitmap
    let title: String
    var isBusy = false
    var isEnabled = true
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            guard !isBusy else { return }
            GestureHaptic.light.trigger()
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isBusy {
                        DotWave(pitch: 2.6, label: "\(title) in progress")
                    } else {
                        PHGlyph(glyph: glyph, pitch: 2.2, stepsWithType: true)
                    }
                }
                .frame(minHeight: 24)
                if !typeSize.isAccessibilitySize {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, PixelHandTheme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(CapturePressStyle(shape: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(title)
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
    }
}

/// Quiet white at rest; pressed, the glyph and text light phosphor over a
/// glow wash (the press flash).
struct CapturePressStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? PixelHandTheme.Brand.phosphor : Color.white.opacity(0.88))
            .background(shape.fill(configuration.isPressed ? PixelHandTheme.Brand.glow.opacity(0.14) : Color.clear))
            .animation(.easeOut(duration: PixelHandMotion.pressFlash), value: configuration.isPressed)
    }
}

// MARK: - Dock

/// The bottom tool panel: raised navy, radius 24, hairline rim, 16 pt from
/// the edges. Sits above the home indicator. `maxWidth` keeps a row of
/// actions together and centred on wide windows (the capture preview,
/// `CapturePreviewLayout.dockMaximumWidth`); `nil` spans the stage.
struct CaptureDock<Content: View>: View {
    var maxWidth: CGFloat?
    /// The card's accessibility identifier (its visible frame), if any.
    var identifier: String?
    @ViewBuilder let content: () -> Content

    init(maxWidth: CGFloat? = nil, identifier: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.maxWidth = maxWidth
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        VStack(spacing: PixelHandTheme.Space.sm) {
            content()
        }
        .padding(PixelHandTheme.Space.sm)
        .frame(maxWidth: maxWidth)
        // As tall as its row, never stretched by the stage (build 27 bug 4
        // measured the dock's frame running 1,169 pt past the window).
        .fixedSize(horizontal: false, vertical: true)
        .background(
            PixelHandTheme.Brand.screenRaised.opacity(0.94),
            in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.bottom, PixelHandTheme.Space.sm)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Picture well

/// The capture on a black well (radius 24, hairline), so a dark screenshot
/// still reads against the navy stage.
struct CapturePictureWell<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(Color.black, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                    .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline)
            )
            .padding(.horizontal, PixelHandTheme.Space.lg)
    }
}

// MARK: - Inks

extension CaptureSheetChrome.Ink {
    var uiColor: UIColor {
        switch self {
        case .phosphor: UIColor(PixelHandTheme.Brand.phosphor)
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .white: .white
        case .black: .black
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

// MARK: - Geometry bridges

extension CaptureGeometry {
    /// The image's size in pixels, for the status strip.
    static func pixelSize(of image: UIImage) -> (width: Int, height: Int) {
        (Int((image.size.width * image.scale).rounded()), Int((image.size.height * image.scale).rounded()))
    }

    /// `image` aspect-fitted in a container of `size`, as a `CGRect`.
    static func fitted(_ image: UIImage, in size: CGSize) -> CGRect {
        CGRect(fittedRect(
            contentWidth: Double(image.size.width),
            contentHeight: Double(image.size.height),
            in: MirrorRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))
        ))
    }
}
