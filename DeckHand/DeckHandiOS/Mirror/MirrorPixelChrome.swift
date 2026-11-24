//
//  MirrorPixelChrome.swift
//  DeckHandiOS – Mirror
//
//  The mirror's pixel chrome, shared by the docked `MirrorPane` and the
//  floating tile (UX-006, UX-016): the cursor badge, the glass toolbar
//  buttons, the desktop dots bar, notices, and the scanline that sweeps in
//  a new picture. Text comes from `MirrorPaneChrome` (Core) so every
//  dot-matrix string is drawable and has a spoken label.
//  Spec: `Product/Design/06-Pixel-Identity.md` §3–§5, `07-Polish-Spec.md` §4.
//

import SwiftUI

// MARK: - Cursor badge

/// 20 pt navy capsule: pointer glyph, `ON 2`, an arrow toward that display.
/// Tap shows that display. Only while the pointer is on another display.
struct MirrorCursorBadgeView: View {
    let badge: MirrorCursorBadge
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                PHGlyph(glyph: PixelGlyphs.pointer, pitch: 1.6, accent: PixelHandTheme.Brand.phosphor)
                DotMatrixText(badge.text, pitch: 1.4, glows: true, stepsWithType: false)
                PHGlyph(glyph: PixelGlyphs.spaceRight, pitch: 1.6, accent: PixelHandTheme.Brand.phosphor)
                    .rotationEffect(arrowAngle)
            }
            .foregroundStyle(PixelHandTheme.Brand.phosphor)
            .padding(.horizontal, 6)
            .frame(height: PixelHandTheme.ControlHeight.badge)
            .background(PixelHandTheme.Brand.screen.opacity(0.84), in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.badge, style: .continuous)
                    .strokeBorder(PixelHandTheme.Brand.glow.opacity(0.5), lineWidth: PixelHandTheme.Stroke.hairline)
            )
            // 44 pt target around the 20 pt badge.
            .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pixelOnNavy()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.spoken)
        .accessibilityAddTraits(.isButton)
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.badge)
    }

    private var arrowAngle: Angle {
        switch badge.arrow {
        case .right: .zero
        case .left: .degrees(180)
        case .up: .degrees(-90)
        case .down: .degrees(90)
        }
    }
}

// MARK: - Toolbar

/// One 44 pt item in the mirror's glass toolbar: a glyph at pitch 2, an
/// optional dot-matrix counter, lit (white 18 % plate, glyph accent) when on.
struct MirrorToolButton: View {
    let glyph: GlyphBitmap
    var counter: String?
    let label: String
    var isOn = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                PHGlyph(glyph: glyph, pitch: 2, accent: isOn ? PixelHandTheme.Brand.phosphor : nil)
                if let counter {
                    DotMatrixText(counter, pitch: 1.6, glows: false, stepsWithType: false)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, counter == nil ? 0 : 10)
            .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.hit)
            .background {
                if isOn {
                    Capsule().fill(Color.white.opacity(0.18))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.32)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.hit / 2)
    }
}

/// ‹ desktop dots ›: the mirrored display's Spaces between the Space
/// buttons. ‹ › dim (never vanish) at the ends and with one desktop, so the
/// toolbar keeps its shape. Hidden entirely for a window mirror.
struct MirrorSpaceControls: View {
    let strip: MirrorSpaceStrip
    let onSwitch: (SpaceDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            MirrorToolButton(
                glyph: PixelGlyphs.spaceLeft,
                label: "Previous desktop",
                isEnabled: strip.previous == .enabled,
                action: { onSwitch(.previous) }
            )
            if !strip.dots.isEmpty {
                DesktopDots(
                    count: strip.dots.count,
                    current: strip.dots.firstIndex(where: \.isCurrent) ?? 0,
                    fullScreen: Set(strip.dots.compactMap { dot -> Int? in
                        if case .fullScreen = dot.kind { return dot.index }
                        return nil
                    })
                )
                .accessibilityLabel(strip.accessibilitySummary ?? "")
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: strip)
            }
            MirrorToolButton(
                glyph: PixelGlyphs.spaceRight,
                label: "Next desktop",
                isEnabled: strip.next == .enabled,
                action: { onSwitch(.next) }
            )
        }
    }
}

// MARK: - Notices

/// A sentence on the picture (the mirrored window ended; the pointer is
/// outside the window): navy plate, phosphor glyph, system text so it reads
/// at every Dynamic Type size.
struct MirrorNoticeLabel: View {
    let glyph: GlyphBitmap
    let text: String
    var style: StatusStrip.Style = .live

    var body: some View {
        HStack(spacing: 6) {
            PHGlyph(glyph: glyph, pitch: 1.6, accent: tint)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(PixelHandTheme.Brand.screen.opacity(0.84), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .pixelOnNavy()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var tint: Color {
        style == .needsYou ? Color(red: 1, green: 0.84, blue: 0.6) : PixelHandTheme.Brand.phosphor
    }
}

// MARK: - Scanline

/// The scanline transition: a 1.5 pt phosphor line sweeps top to bottom
/// with a 14 pt cyan afterglow, revealing the picture under it. Runs when
/// `trigger` changes (mirror connects, display or desktop changes). Under
/// Reduce Motion the picture fades in instead (the caller's fade).
struct MirrorScanline<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { proxy in
                    Rectangle()
                        .frame(height: proxy.size.height * progress)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .overlay {
                GeometryReader { proxy in
                    if progress < 1 {
                        let y = proxy.size.height * progress
                        ZStack(alignment: .top) {
                            LinearGradient(
                                colors: [.clear, PixelHandTheme.Brand.glow.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 14)
                            .offset(y: max(0, y - 14))
                            Rectangle()
                                .fill(PixelHandTheme.Brand.phosphor)
                                .frame(height: 1.5)
                                .shadow(color: PixelHandTheme.Brand.glow, radius: 4)
                                .offset(y: y)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                progress = 0
                withAnimation(.easeOut(duration: PixelHandMotion.scanlineDuration)) {
                    progress = 1
                }
            }
    }
}

extension View {
    /// Sweeps the scanline over this view whenever `trigger` changes.
    func mirrorScanline<T: Equatable>(on trigger: T) -> some View {
        modifier(MirrorScanline(trigger: trigger))
    }
}

// MARK: - Picture

/// The live picture: the HEVC display layer (S5) or the latest JPEG, at the
/// stream's aspect, with the Mac's pointer drawn over it (S3). Before the
/// first frame, the dot wave on navy.
struct MirrorPicture: View {
    let session: ControlSessionModel

    var body: some View {
        if session.mirrorShowsVideo {
            MirrorVideoLayerView(renderer: session.mirrorVideoRenderer)
                .aspectRatio(Self.aspect(session), contentMode: .fit)
                .allowsHitTesting(false)
                .background { MirrorPiPBackground(session: session) } // UX-041
                .overlay { MirrorCursorLayer(session: session) }
        } else if let image = session.mirrorImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background { MirrorPiPBackground(session: session) } // UX-041
                .overlay { MirrorCursorLayer(session: session) }
        } else {
            ZStack {
                Color.black
                VStack(spacing: PixelHandTheme.Space.md) {
                    DotWave(pitch: 6, label: "Waiting for the Mac’s screen")
                    DotMatrixText("CONNECTING", pitch: 1.6, label: "Connecting", stepsWithType: false)
                        .foregroundStyle(PixelHandTheme.Brand.phosphor)
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .pixelOnNavy()
        }
    }

    /// Width / height of the stream; 16:10 until the first frame says.
    static func aspect(_ session: ControlSessionModel) -> CGFloat {
        if session.mirrorShowsVideo, let size = session.mirrorVideoSize, size.width > 0, size.height > 0 {
            return size.width / size.height
        }
        if let size = session.mirrorImage?.size, size.width > 0, size.height > 0 {
            return size.width / size.height
        }
        return 16.0 / 10.0
    }
}
