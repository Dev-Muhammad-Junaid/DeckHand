//
//  PointerSurface.swift
//  DeckHandiOS – Surfaces
//
//  The Pointer surface (UX-004): the trackpad as a navy `PixelSurface` with
//  the dot field, a dot-matrix caption that names what the Mac is doing, a
//  Click | Right-click strip (hideable in Settings, and hidden when the pad
//  gets too short), a keyboard button, and a first-use coach mark for drags
//  and three-finger gestures. The 7-button gesture bar and the sensitivity
//  slider are gone: Mission Control and Show Desktop are three-finger
//  gestures and deck keys, sensitivity is in Settings › Pointer and
//  gestures. Every gesture keeps a VoiceOver action on the pad.
//
//  Input runs through `TrackpadInputLayer`, the same wiring as the classic
//  layout's `TrackpadView`: typing, drags, S11 gestures and S12 Pencil hover
//  behave the same in both.
//  Spec: `Product/Design/04-Interaction-Model.md` §2 (Pointer),
//  `06-Pixel-Identity.md`, `07-Polish-Spec.md`; board "Control surface ·
//  Pointer".
//

import SwiftUI

/// `@AppStorage` keys for the Pointer surface. The Settings toggle and the
/// surface read the same key.
enum PointerSurfaceSettings {
    static let showsClickStripKey = "pixelhand.pointer.showsClickStrip"
    static let coachMarkSeenKey = "pixelhand.pointer.coachMarkSeen"
}

struct PointerSurface: View {
    let sender: TrackpadSender
    /// Clipboard sync state (S10), shown in the keyboard panel.
    var clipboard: RemoteClipboard?
    /// The canvas margin from `LayoutMetrics`.
    var margin: CGFloat = PixelHandTheme.Space.lg

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PointerSurfaceSettings.showsClickStripKey) private var showsClickStrip = true
    @AppStorage(PointerSurfaceSettings.coachMarkSeenKey) private var coachMarkSeen = false

    /// Finger positions for the dot field; only `DotField` reads them.
    @State private var dots = DotFieldModel()
    /// Gesture → Mac view, with toggle-back (S11).
    @State private var gestureMap = GestureMap()
    @State private var activeGesture: TrackpadGestureKind?
    /// The last three-finger gesture, held briefly so the caption can name it
    /// (the gesture is decided at lift, when the pad goes idle).
    @State private var recentSystemGesture: MultiFingerGesture?
    @State private var systemGestureClear: Task<Void, Never>?
    /// One finger scrolls (an accessibility fallback; from the strip's menu
    /// and the VoiceOver actions).
    @State private var scrollMode = false
    @State private var showKeyboard = false

    private var caption: PointerCaption {
        PointerCaption.caption(for: activity)
    }

    private var activity: PointerActivity {
        if let gesture = activeGesture {
            return gesture.pointerActivity
        }
        if let recent = recentSystemGesture {
            return .system(recent)
        }
        return .idle(scrollMode: scrollMode)
    }

    var body: some View {
        VStack(spacing: PixelHandTheme.Space.sm) {
            GeometryReader { proxy in
                pad(height: proxy.size.height)
            }

            if showKeyboard {
                RemoteKeyboardPanel(
                    sender: sender,
                    clipboard: clipboard,
                    colorScheme: colorScheme,
                    onActivity: { gestureMap.forget() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, margin)
        .padding(.bottom, PixelHandTheme.Space.sm)
        .animation(PixelHandMotion.reduced(PixelHandMotion.spring, reduceMotion: reduceMotion), value: showKeyboard)
    }

    // MARK: Pad

    @ViewBuilder
    private func pad(height: CGFloat) -> some View {
        let stripShown = PointerSurfaceLayout.showsClickStrip(enabled: showsClickStrip, padHeight: Double(height))
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous)

        PixelSurface(cornerRadius: PixelHandTheme.Radius.pane, showsGrid: false) {
            // The dot field runs under the strip too, so the grid reads as one
            // screen; touches and the field share the top-leading origin.
            ZStack(alignment: .top) {
                DotField(model: dots)

                VStack(spacing: 0) {
                    ZStack {
                        touchSurface
                        captionLayer
                        chromeLayer
                        if !coachMarkSeen && height >= 300 {
                            PointerCoachMark { dismissCoachMark() }
                                .padding(PixelHandTheme.Space.lg)
                                .transition(.opacity)
                        }
                    }

                    if stripShown {
                        ClickStrip(
                            scrollMode: $scrollMode,
                            onClick: { click(.left) },
                            onRightClick: { click(.right) },
                            onDoubleClick: { doubleClick() },
                            onLocate: { locatePointer() }
                        )
                        .mirrorTileKeepOut(.clickStrip, owner: sender)
                        .transition(.opacity)
                    }
                }
            }
            .clipShape(shape)
        }
        // The floating screen tile anchors to the pad and keeps clear of the
        // strip, caption and keyboard button (`MirrorTileKeepOut`).
        .mirrorTileKeepOut(.pad, owner: sender)
        .animation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion), value: stripShown)
        .animation(PixelHandMotion.reduced(PixelHandMotion.quick, reduceMotion: reduceMotion), value: caption)
    }

    private var touchSurface: some View {
        TrackpadInputLayer(
            sender: sender,
            dots: dots,
            gestureMap: $gestureMap,
            scrollMode: scrollMode,
            drawsDotField: false,
            onGestureChanged: { gesture in
                activeGesture = gesture
                if case .dragging = gesture { dismissCoachMark() }
                // A new touch replaces the held gesture name.
                switch gesture {
                case .none, .system: break
                case .some: recentSystemGesture = nil
                }
            },
            onSystemGesture: { gesture in
                dismissCoachMark()
                showSystemGesture(gesture)
            }
        )
        // A direct-touch area for VoiceOver, with every gesture as an action.
        .accessibilityElement()
        .accessibilityLabel("Trackpad")
        .accessibilityValue(caption.spoken)
        .accessibilityHint("Touch directly to move the pointer. Actions has clicks, scrolling and Mac gestures.")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction(named: "Click") { click(.left) }
        .accessibilityAction(named: "Double-click") { doubleClick() }
        .accessibilityAction(named: "Right-click") { click(.right) }
        .accessibilityAction(named: "Mission Control") { systemAction(.missionControl) }
        .accessibilityAction(named: "App Exposé") { systemAction(.appExpose) }
        .accessibilityAction(named: "Show Desktop") { systemAction(.showDesktop) }
        .accessibilityAction(named: "Next Space") { spaceGesture(.left) }
        .accessibilityAction(named: "Previous Space") { spaceGesture(.right) }
        .accessibilityAction(named: "Find the pointer") { locatePointer() }
        .accessibilityAction(named: scrollMode ? "Turn off one-finger scrolling" : "Turn on one-finger scrolling") {
            scrollMode.toggle()
        }
        .accessibilityAction(named: showKeyboard ? "Hide keyboard" : "Show keyboard") {
            showKeyboard.toggle()
        }
    }

    /// The caption pill at the pad's bottom-leading corner, 12 pt above the
    /// strip (board: `pad__cap2`).
    private var captionLayer: some View {
        PointerCaptionPill(caption: caption)
            .mirrorTileKeepOut(.caption, owner: sender)
            .padding(PixelHandTheme.Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The keyboard button, top-leading (the floating screen tile takes the
    /// trailing side). Moves to the app dock with UX-005.
    private var chromeLayer: some View {
        GlassCircleButton(
            glyph: PixelGlyphs.keyboard,
            label: showKeyboard ? "Hide keyboard" : "Keyboard",
            isOn: showKeyboard
        ) {
            GestureHaptic.selection.trigger()
            showKeyboard.toggle()
        }
        .mirrorTileKeepOut(.keyboard, owner: sender)
        .padding(PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Actions

    private func click(_ button: MouseButton) {
        gestureMap.forget()
        Task { await sender.sendClick(button) }
    }

    private func doubleClick() {
        gestureMap.forget()
        Task { await sender.sendDoubleClick(.left) }
    }

    private func locatePointer() {
        Task { await sender.locateCursor() }
    }

    private func systemAction(_ action: SystemMacro) {
        gestureMap.forget()
        Task { await sender.sendSystemAction(action) }
    }

    private func spaceGesture(_ direction: MultiFingerGesture.Direction) {
        let command = GestureMap.command(for: .swipe(direction))
        showSystemGesture(.swipe(direction))
        Task { await sender.sendGesture(command) }
    }

    private func showSystemGesture(_ gesture: MultiFingerGesture) {
        recentSystemGesture = gesture
        systemGestureClear?.cancel()
        systemGestureClear = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            recentSystemGesture = nil
        }
    }

    private func dismissCoachMark() {
        guard !coachMarkSeen else { return }
        coachMarkSeen = true
    }
}

// MARK: - Gesture → caption

extension TrackpadGestureKind {
    /// The Core activity the caption reads.
    var pointerActivity: PointerActivity {
        switch self {
        case .cursor: .cursor
        case .scroll: .scroll
        case .dragArmed: .dragArmed
        case .dragging: .dragging
        case .dragLocked: .dragLocked
        case .pencilHover: .pencilHover
        case .system(let gesture): .system(gesture)
        }
    }
}

// MARK: - Caption pill

/// A glyph and a dot-matrix word on a quiet plate (board `pad__cap2`):
/// 24 pt tall, radius 8. Lights phosphor while a finger works.
struct PointerCaptionPill: View {
    let caption: PointerCaption

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
        HStack(spacing: 6) {
            PHGlyph(glyph: caption.glyph, pitch: 1.6, stepsWithType: true)
            DotMatrixText(caption.text, pitch: 1.3, label: caption.spoken, glows: caption.isActive)
        }
        .foregroundStyle(caption.isActive ? PixelHandTheme.Brand.phosphor : Color.white.opacity(0.72))
        .padding(.horizontal, PixelHandTheme.Space.sm)
        .frame(minHeight: PixelHandTheme.ControlHeight.strip)
        .background(shape.fill(Color.white.opacity(caption.isActive ? 0.1 : 0.06)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: PixelHandTheme.Stroke.hairline))
        .contentTransition(.identity)
    }
}

// MARK: - Click strip

/// Click | Right-click across the pad's foot (board `pad__clicks`): 52 pt,
/// hairline dividers, each half a full-height target. Touch and hold for
/// Double-click, Find the pointer and one-finger scrolling.
struct ClickStrip: View {
    @Binding var scrollMode: Bool
    let onClick: () -> Void
    let onRightClick: () -> Void
    let onDoubleClick: () -> Void
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            cell("Click", haptic: .medium, action: onClick)
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)
                .accessibilityHidden(true)
            cell("Right-click", haptic: .heavy, action: onRightClick)
        }
        .frame(minHeight: PointerSurfaceLayout.clickStripHeight)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .contextMenu {
            Button("Double-click", action: onDoubleClick)
            Button("Find the pointer", action: onLocate)
            Toggle("One-finger scrolling", isOn: $scrollMode)
        }
    }

    private func cell(_ title: String, haptic: GestureHaptic, action: @escaping () -> Void) -> some View {
        Button {
            haptic.trigger()
            action()
        } label: {
            Text(title)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, PixelHandTheme.Space.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(ClickCellStyle())
        .accessibilityLabel(title)
    }
}

/// A strip half: quiet white text; pressed, a phosphor wash and lit text
/// (the press flash).
private struct ClickCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? PixelHandTheme.Brand.phosphor : Color.white.opacity(0.6))
            .background(configuration.isPressed ? PixelHandTheme.Brand.glow.opacity(0.12) : Color.clear)
            .animation(.easeOut(duration: PixelHandMotion.pressFlash), value: configuration.isPressed)
    }
}

// MARK: - Coach mark

/// First use only: how to drag and what three fingers do. Dismissed by
/// "Got it", the first drag or the first three-finger gesture.
struct PointerCoachMark: View {
    let onDismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
            row(PixelGlyphs.pointer, "Rest a finger until it buzzes, then move to drag.")
            row(PixelGlyphs.missionControl, "Three fingers: swipe up for Mission Control, sideways for Spaces.")
            Button("Got it", action: onDismiss)
                .buttonStyle(.ph(.secondary, size: .small))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(PixelHandTheme.Space.lg)
        .frame(maxWidth: 320)
        .background(shape.fill(PixelHandTheme.Brand.screenRaised))
        .overlay(shape.strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline))
        .accessibilityElement(children: .contain)
    }

    private func row(_ glyph: GlyphBitmap, _ text: String) -> some View {
        HStack(alignment: .top, spacing: PixelHandTheme.Space.md) {
            PHGlyph(glyph: glyph, pitch: 2, stepsWithType: true)
                .foregroundStyle(PixelHandTheme.Brand.phosphor)
                .padding(.top, 1)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Caption pills") {
    VStack(alignment: .leading, spacing: 12) {
        PointerCaptionPill(caption: .caption(for: .idle(scrollMode: false)))
        PointerCaptionPill(caption: .caption(for: .dragging))
        PointerCaptionPill(caption: .caption(for: .dragLocked))
        PointerCaptionPill(caption: .caption(for: .system(.swipe(.up))))
    }
    .padding(24)
    .background(PixelHandTheme.Brand.screen)
    .pixelOnNavy()
}

#Preview("Click strip and coach mark") {
    PixelSurface {
        VStack(spacing: 0) {
            PointerCoachMark {}
                .padding(16)
                .frame(maxHeight: .infinity)
            ClickStrip(scrollMode: .constant(false), onClick: {}, onRightClick: {}, onDoubleClick: {}, onLocate: {})
        }
    }
    .frame(height: 520)
    .padding(16)
    .background(.phCanvas)
}
