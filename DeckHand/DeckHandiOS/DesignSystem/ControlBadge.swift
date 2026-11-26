//
//  ControlBadge.swift
//  DeckHandiOS – Design system
//
//  Badges on controls: the unseen dot, the Pro lock, the PRO label, counts
//  and live dots (owner testing, build 27, OT-14). One rule for all of
//  them: a badge is drawn in an overlay *above* the control's glass,
//  outside its clip shape, never clipped, at Core's frame on the 4 pt grid
//  (`ControlBadgePlacement`).
//
//  Why a layer and not a plain `.overlay`: on iOS 26 neighbouring glass
//  shares one `GlassEffectContainer` (`phGlassGroup`), which renders the
//  glass of every control in the group together. An overlay on one of the
//  controls sat under that combined glass, so build 27's Send dot was cut
//  off by its own circle and the free plan's Pro lock by the header's
//  glass. So inside a glass group a badge only *reports* its control's
//  bounds (an anchor preference) and the group draws every badge in one
//  overlay on top of the container (`controlBadgeLayer()`, which
//  `phGlassGroup` applies). Outside a glass group there is nothing to
//  draw over it, and the badge is the control's own overlay, last, with
//  `zIndex` 1.
//
//  Presentations (sheets, covers) inherit the environment, so the layer's
//  flag is cleared for their content (`controlBadgeScope()`), and a badge
//  in a sheet presented from the header still draws.
//

import PixelHandCore
import SwiftUI

/// Where a badge sits on its control.
struct ControlBadgeStyle: Equatable {
    var shape: ControlBadgePlacement.Shape
    var corner: ControlBadgePlacement.Corner = .topTrailing
    var anchor: ControlBadgePlacement.Anchor = .rim

    /// On a header or toolbar glass circle, straddling its rim.
    static func circle(_ corner: ControlBadgePlacement.Corner = .topTrailing) -> ControlBadgeStyle {
        .init(shape: .circle, corner: corner, anchor: .rim)
    }

    /// On a glass pill or chip, straddling its rounded end.
    static func capsule(_ corner: ControlBadgePlacement.Corner = .topTrailing) -> ControlBadgeStyle {
        .init(shape: .capsule, corner: corner, anchor: .rim)
    }

    /// Inside a tile's corner (a Mac tile in a card), so it never covers
    /// the name beside it.
    static func inset(_ distance: Double = 4, corner: ControlBadgePlacement.Corner = .topTrailing, radius: Double = Double(PixelHandTheme.Radius.chip)) -> ControlBadgeStyle {
        .init(shape: .roundedRect(radius: radius), corner: corner, anchor: .inset(distance))
    }
}

/// A badge's face, at its Core size.
struct ControlBadgeView: View {
    let kind: ControlBadgeKind

    /// The UI walks launch with `-qa.exposeBadges YES` to find badges
    /// (`ph.badge.<kind>`) and check them on screen (`test25`). Otherwise a
    /// badge is hidden from VoiceOver: its control says what it means.
    static let exposedForQA = UserDefaults.standard.bool(forKey: "qa.exposeBadges")

    var body: some View {
        let sized = face
            .frame(width: CGFloat(kind.size.width), height: CGFloat(kind.size.height))
            .allowsHitTesting(false)
        if Self.exposedForQA {
            sized
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Badge")
                .accessibilityIdentifier("ph.badge.\(kind.qaName)")
        } else {
            sized.accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var face: some View {
        switch kind {
        case .dot:
            // The app's one kind of dot: a rounded square
            // (`06-Pixel-Identity.md` §0), ringed in the canvas colour so
            // it reads on glass and on the picture.
            RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                .fill(PixelHandTheme.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                        .strokeBorder(PixelHandTheme.canvas, lineWidth: 1)
                )
        case .live:
            LivePixel(color: PixelHandTheme.Brand.mint, size: 8)
                .padding(2)
                .background(PixelHandTheme.canvas, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        case .needsYou:
            StatusPixel(state: .needsYou, size: 8)
                .padding(2)
                .background(PixelHandTheme.canvas, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        case .offLight:
            StatusPixel(state: .off, size: 8)
                .padding(2)
                .background(PixelHandTheme.canvas, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        case .proLock:
            ProLockBadge()
        case .proLockSmall:
            ProLockBadge(side: 16)
        case .proLabel:
            ProBadge()
        case let .count(value):
            DotMatrixText(ControlBadgeKind.countText(value), pitch: 1.4, label: "\(value)", glows: false)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PixelHandTheme.accent, in: Capsule())
        }
    }
}

// MARK: - The layer

private struct ControlBadgeEntry {
    let kind: ControlBadgeKind
    let style: ControlBadgeStyle
    let bounds: Anchor<CGRect>
}

private struct ControlBadgeKey: PreferenceKey {
    static let defaultValue: [ControlBadgeEntry] = []
    static func reduce(value: inout [ControlBadgeEntry], nextValue: () -> [ControlBadgeEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ControlBadgeLayerKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a view that draws its controls' badges in a layer on
    /// top (`controlBadgeLayer()`).
    fileprivate var controlBadgeLayer: Bool {
        get { self[ControlBadgeLayerKey.self] }
        set { self[ControlBadgeLayerKey.self] = newValue }
    }
}

private struct ControlBadgeModifier: ViewModifier {
    let kind: ControlBadgeKind?
    let style: ControlBadgeStyle
    @Environment(\.controlBadgeLayer) private var hasLayer
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        if let kind {
            if hasLayer {
                content.anchorPreference(key: ControlBadgeKey.self, value: .bounds) { bounds in
                    [ControlBadgeEntry(kind: kind, style: style, bounds: bounds)]
                }
            } else {
                content
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .overlay(alignment: .topLeading) {
                        let frame = ControlBadgeLayout.frame(kind, in: size, style: style)
                        ControlBadgeView(kind: kind)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                    .zIndex(1)
            }
        } else {
            content
        }
    }
}

private struct ControlBadgeLayerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.controlBadgeLayer, true)
            .overlayPreferenceValue(ControlBadgeKey.self) { entries in
                GeometryReader { proxy in
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        let bounds = proxy[entry.bounds]
                        let frame = ControlBadgeLayout.frame(entry.kind, in: bounds.size, style: entry.style)
                        ControlBadgeView(kind: entry.kind)
                            .position(x: bounds.minX + frame.midX, y: bounds.minY + frame.midY)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(!ControlBadgeView.exposedForQA)
            }
            // Drawn here: an enclosing layer mustn't draw them again.
            .transformPreference(ControlBadgeKey.self) { $0 = [] }
    }
}

extension ControlBadgeKind {
    /// The badge's name in `ph.badge.<name>`.
    var qaName: String {
        switch self {
        case .dot: "dot"
        case .live: "live"
        case .needsYou: "needsYou"
        case .offLight: "offLight"
        case .proLock: "proLock"
        case .proLockSmall: "proLockSmall"
        case .proLabel: "proLabel"
        case .count: "count"
        }
    }
}

enum ControlBadgeLayout {
    static func frame(_ kind: ControlBadgeKind, in size: CGSize, style: ControlBadgeStyle) -> CGRect {
        let f = ControlBadgePlacement.frame(
            kind,
            control: .init(width: Double(size.width), height: Double(size.height)),
            shape: style.shape,
            corner: style.corner,
            anchor: style.anchor
        )
        return CGRect(x: f.x, y: f.y, width: f.width, height: f.height)
    }
}

extension View {
    /// A badge on this control, above its glass and outside its clip
    /// shape, at Core's frame (OT-14). `nil` shows none. Put it on the
    /// control's own frame (the glass circle, the tile), after its glass.
    func controlBadge(_ kind: ControlBadgeKind?, style: ControlBadgeStyle) -> some View {
        modifier(ControlBadgeModifier(kind: kind, style: style))
    }

    /// Draws the badges of the controls inside in one overlay above them
    /// (glass groups apply it; see `phGlassGroup`).
    func controlBadgeLayer() -> some View {
        modifier(ControlBadgeLayerModifier())
    }

    /// For presented content (a sheet from inside a glass group): its
    /// badges draw on their own controls, not in a layer they can't reach.
    func controlBadgeScope() -> some View {
        environment(\.controlBadgeLayer, false)
    }
}
