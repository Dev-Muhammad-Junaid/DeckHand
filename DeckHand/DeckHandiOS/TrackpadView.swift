//
//  TrackpadView.swift
//  DeckHandiOS
//

import QuartzCore
import SwiftUI
import UIKit

/// The classic layout's trackpad, with the gesture bar and the inline
/// sensitivity slider. The Pixel Hand shell shows `PointerSurface` instead;
/// both drive the Mac through `TrackpadInputLayer`.
struct TrackpadView: View {
    let sender: TrackpadSender
    let colorScheme: ColorScheme
    /// Clipboard sync state (S10), shown in the keyboard panel.
    var clipboard: RemoteClipboard?

    // Sensitivity lives in settings so the inline slider and the settings
    // page stay in step, and the choice survives relaunch.
    @EnvironmentObject private var settings: DeckHandSettings
    @State private var scrollMode: Bool = false
    @State private var activeGesture: TrackpadGestureKind?
    /// Finger positions for the dot field. Only `DotField` reads it, so
    /// touches don't re-render the rest of this view.
    @State private var dots = DotFieldModel()
    /// Gesture → Mac view, with toggle-back (S11). A click, key or text
    /// forgets what a gesture opened.
    @State private var gestureMap = GestureMap()
    /// The keyboard panel (typing, special keys, Paste to Mac).
    @State private var showKeyboard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bg: Color { PixelHandTheme.color(PaletteTokens.canvas, for: colorScheme) }
    private var surfaceShadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.3) : PixelHandTheme.Brand.screen.opacity(0.22)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Trackpad surface ──────────────────────────────────────
            // Always the icon's dark screen, in both appearances, so the
            // surface reads as a device rather than a page.
            ZStack {
                // Background glass
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous)
                    .fill(PixelHandTheme.Brand.screenSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous)
                            .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: 1)
                    )
                    .shadow(color: surfaceShadowColor, radius: 16, y: 8)

                // The icon's dot screen and the multi-touch surface: lights
                // under fingers and on taps.
                TrackpadInputLayer(
                    sender: sender,
                    dots: dots,
                    gestureMap: $gestureMap,
                    scrollMode: scrollMode,
                    onGestureChanged: { gesture in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeGesture = gesture
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
                // A direct-touch area for VoiceOver, with the clicks as actions.
                .accessibilityElement()
                .accessibilityLabel("Trackpad")
                .accessibilityHint("Touch directly to move the pointer. Actions has clicks and Mac gestures.")
                .accessibilityAddTraits(.allowsDirectInteraction)
                .accessibilityIdentifier("ph.trackpad")
                .accessibilityAction(named: "Click") { gestureMap.forget(); Task { await sender.sendClick(.left) } }
                .accessibilityAction(named: "Double-click") { gestureMap.forget(); Task { await sender.sendDoubleClick(.left) } }
                .accessibilityAction(named: "Right-click") { gestureMap.forget(); Task { await sender.sendClick(.right) } }
                .accessibilityAction(named: "Mission Control") { gestureMap.forget(); Task { await sender.sendSystemAction(.missionControl) } }
                .accessibilityAction(named: "Show Desktop") { gestureMap.forget(); Task { await sender.sendSystemAction(.showDesktop) } }
                .accessibilityAction(named: "Find the pointer") { Task { await sender.locateCursor() } }
                .accessibilityAction(named: scrollMode ? "Turn off one-finger scrolling" : "Turn on one-finger scrolling") { scrollMode.toggle() }

                // ── Gesture indicator (top-left corner) ──────────────
                VStack {
                    HStack {
                        if let gesture = activeGesture {
                            GestureIndicator(gesture: gesture, colorScheme: .dark)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85)))
                        }
                        Spacer()

                        // Mode hint label
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(scrollMode ? "Scroll mode" : "Trackpad")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.secondary.opacity(0.7))
                            Text("Tap to click · Hold to right-click · Hold, then move to drag · Two fingers to scroll · Three fingers for Spaces and Mission Control")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                        }
                        .padding(12)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // ── Keyboard panel: typing, special keys, Paste to Mac ────
            if showKeyboard {
                RemoteKeyboardPanel(
                    sender: sender,
                    clipboard: clipboard,
                    colorScheme: colorScheme,
                    onActivity: { gestureMap.forget() }
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .transition(.opacity) // Glyph rule: panels fade, never slide.
            }

            // ── Sensitivity slider ────────────────────────────────────
            // Index-driven over a small set of labeled anchors (WID-405):
            // every notch is a distinct, recognizable speed and the tick
            // labels make the current level readable at a glance.
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "tortoise")
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                    Slider(
                        value: Binding(
                            get: { Double(TrackpadSensitivity.nearestIndex(to: settings.pointerSensitivity)) },
                            set: { settings.pointerSensitivity = TrackpadSensitivity.anchors[Int($0.rounded())] }
                        ),
                        in: TrackpadSensitivity.indexRange,
                        step: 1
                    )
                    .tint(Color.primary.opacity(0.6))
                    .accessibilityLabel("Pointer speed")
                    .accessibilityValue(TrackpadSensitivity.label(for: settings.pointerSensitivity))
                    Image(systemName: "hare")
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                    Text(TrackpadSensitivity.label(for: settings.pointerSensitivity))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                        .frame(width: 36, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                // Tick labels aligned under the slider track.
                HStack {
                    ForEach(TrackpadSensitivity.anchors, id: \.self) { anchor in
                        Text(TrackpadSensitivity.label(for: anchor))
                            .font(.system(size: 9, weight: anchor == settings.pointerSensitivity ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(anchor == settings.pointerSensitivity ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.6))
                        if anchor != TrackpadSensitivity.anchors.last {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .accessibilityHidden(true)
                .padding(.leading, 26)   // clear the tortoise icon
                .padding(.trailing, 70)  // clear the hare icon + readout
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)

            // ── Gesture button bar ────────────────────────────────────
            GestureButtonBar(sender: sender, scrollMode: $scrollMode, showKeyboard: $showKeyboard, colorScheme: colorScheme)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
        .background(bg)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.28, dampingFraction: 0.85), value: showKeyboard)
    }
}

// MARK: - Trackpad input layer

/// The dot field and the multi-touch surface, wired to the Mac. Shared by
/// the classic `TrackpadView` and the shell's `PointerSurface` (UX-004), so
/// typing, drags, S11 gestures and S12 Pencil hover behave the same in both.
struct TrackpadInputLayer: View {
    let sender: TrackpadSender
    let dots: DotFieldModel
    /// Gesture → Mac view, with toggle-back (S11). A click forgets what a
    /// gesture opened.
    @Binding var gestureMap: GestureMap
    var scrollMode = false
    /// Draws the dot field under the touch surface. Off when the host lays
    /// the field out itself (the Pointer surface runs it under its click
    /// strip too); both start at the same top-leading origin.
    var drawsDotField = true
    var onGestureChanged: (TrackpadGestureKind?) -> Void = { _ in }
    /// A three- or four-finger gesture reached the Mac.
    var onSystemGesture: (MultiFingerGesture) -> Void = { _ in }
    /// OR-16: multiplies the pointer sensitivity (the mirror picture passes
    /// 1 / zoom, `PicturePointerMapping`). The Pointer surface leaves it at 1.
    var sensitivityScale: Float = 1
    /// OR-16: set on the mirror picture. Two fingers are arbitrated
    /// (`TwoFingerArbiter`): pinch zooms and pans the picture through these,
    /// two fingers still scroll the Mac, a two-finger tap right-clicks.
    var picture: PictureGestureHandlers?

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        ZStack {
            if drawsDotField {
                DotField(model: dots)
            }
            MultiTouchTrackpad(
                callbacks: callbacks,
                sensitivity: settings.pointerSensitivity * sensitivityScale,
                scrollMode: scrollMode,
                naturalScrolling: settings.naturalScrolling,
                systemGestures: settings.trackpadGestures,
                pencilHover: settings.pencilHoverPointer,
                arbitratesTwoFingers: picture != nil
            )
        }
    }

    private var callbacks: TrackpadCallbacks {
        let sender = self.sender
        let dots = self.dots
        let gestureMap = self.$gestureMap
        let onGestureChanged = self.onGestureChanged
        let onSystemGesture = self.onSystemGesture
        let picture = self.picture
        return TrackpadCallbacks(
            onCursorDelta: { dx, dy in
                Task { await sender.sendMouseDelta(dx: dx, dy: dy) }
            },
            onScrollDelta: { dx, dy in
                Task { await sender.sendScroll(dx: dx, dy: dy) }
            },
            onScrollEnded: {
                Task { await sender.endScroll() }
            },
            onSystemGesture: { gesture in
                if MacSwitcher.shared.handleTrackpadGesture(gesture) { return } // Multi-Mac lane: three fingers sideways switch Macs
                // Toggle-back: the opposite gesture closes what this one
                // opened; the same one again waits.
                guard let command = gestureMap.wrappedValue.resolve(gesture) else { return }
                onSystemGesture(gesture)
                Task { await sender.sendGesture(command) }
            },
            onTap: { pos in
                gestureMap.wrappedValue.forget()
                Task { await sender.sendClick(.left) }
                dots.pulse(at: pos)
            },
            onDoubleTap: { pos in
                gestureMap.wrappedValue.forget()
                Task { await sender.sendDoubleClick(.left) }
                dots.pulse(at: pos)
            },
            onLongPress: { pos in
                gestureMap.wrappedValue.forget()
                Task { await sender.sendClick(.right) }
                // Filled ring: a right-click reads differently from a tap.
                dots.pulse(at: pos, filled: true)
            },
            onDragButton: { isDown in
                gestureMap.wrappedValue.forget()
                Task {
                    if isDown {
                        await sender.sendMouseDown(.left)
                    } else {
                        await sender.sendMouseUp(.left)
                    }
                }
            },
            onGestureChanged: onGestureChanged,
            onTouchesChanged: { points in
                dots.setTouches(points)
            },
            onPictureZoom: { scale, anchor, pan in
                picture?.onZoom(scale, anchor, pan)
            },
            onPictureZoomEnded: {
                picture?.onZoomEnded()
            },
            onTwoFingerTap: { pos in
                gestureMap.wrappedValue.forget()
                Task { await sender.sendClick(.right) }
                dots.pulse(at: pos, filled: true)
            }
        )
    }
}

/// OR-16: what the mirror picture does with a pinch while it works as a
/// trackpad (`TrackpadInputLayer.picture`).
struct PictureGestureHandlers {
    /// Zoom by `scale` (relative) around `anchor`, pan by `pan`; points in
    /// the input layer's coordinates.
    var onZoom: (_ scale: CGFloat, _ anchor: CGPoint, _ pan: CGSize) -> Void
    var onZoomEnded: () -> Void = { }
}

// MARK: - Gesture Indicator Overlay

private struct GestureIndicator: View {
    let gesture: TrackpadGestureKind
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
        .padding(12)
    }

    private var iconName: String {
        switch gesture {
        case .cursor: "hand.point.up.left"
        case .scroll: "arrow.up.and.down"
        case .dragArmed: "hand.raised"
        case .dragging: "hand.draw"
        case .dragLocked: "lock"
        case .pencilHover: "applepencil"
        case .system(let g):
            switch g {
            case .swipe(.left):  "arrow.left"
            case .swipe(.right): "arrow.right"
            case .swipe(.up):    "arrow.up"
            case .swipe(.down):  "arrow.down"
            case .pinch:         "arrow.down.right.and.arrow.up.left"
            case .spread:        "arrow.up.left.and.arrow.down.right"
            }
        }
    }

    private var label: String {
        switch gesture {
        case .cursor: "Cursor"
        case .scroll: "Scrolling"
        case .dragArmed: "Move to drag"
        case .dragging: "Dragging"
        case .dragLocked: "Drag locked · tap to drop"
        case .pencilHover: "Pencil"
        case .system(let g):
            switch g {
            case .swipe(.left), .swipe(.right): "Spaces"
            case .swipe(.up):   "Mission Control"
            case .swipe(.down): "App Exposé"
            case .pinch:        "Apps"
            case .spread:       "Desktop"
            }
        }
    }

    private var iconColor: Color {
        switch gesture {
        case .cursor, .pencilHover: PixelHandTheme.Brand.glow
        case .scroll: PixelHandTheme.Brand.mint
        case .dragArmed, .dragging, .dragLocked: PixelHandTheme.accent
        case .system: PixelHandTheme.Brand.sky
        }
    }
}

// MARK: - Gesture Button Bar

struct GestureButtonBar: View {
    let sender: TrackpadSender
    @Binding var scrollMode: Bool
    @Binding var showKeyboard: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Scroll mode toggle — highlighted when active
            ScrollToggleButton(isActive: $scrollMode, colorScheme: colorScheme)

            // Keyboard panel toggle: type on the Mac.
            GestureButton(
                label: showKeyboard ? "Hide keys" : "Keyboard",
                icon: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard",
                color: PixelHandTheme.accent,
                haptic: .selection,
                colorScheme: colorScheme
            ) {
                showKeyboard.toggle()
            }
            .accessibilityLabel(showKeyboard ? "Hide keyboard" : "Show keyboard")

            GestureButton(label: "Click",        icon: "cursorarrow.click",              color: PixelHandTheme.accent, haptic: .medium, colorScheme: colorScheme) {
                Task { await sender.sendClick(.left) }
            }
            GestureButton(label: "Right-click",  icon: "cursorarrow.click.2",            color: PixelHandTheme.accent, haptic: .heavy,  colorScheme: colorScheme) {
                Task { await sender.sendClick(.right) }
            }
            GestureButton(label: "Double-click", icon: "cursorarrow.click.badge.clock",  color: PixelHandTheme.accent, haptic: .double, colorScheme: colorScheme) {
                Task { await sender.sendDoubleClick(.left) }
            }
            // Locate / Find Cursor — pulses a cobalt crosshair on whichever
            // Mac display currently holds the cursor. Helpful on multi-display
            // setups when the cursor is buried off-screen for the iPad user.
            GestureButton(label: "Locate", icon: "scope", color: PixelHandTheme.accent, haptic: .selection, colorScheme: colorScheme) {
                Task { await sender.locateCursor() }
            }
            .accessibilityLabel("Find the pointer")
            GestureButton(label: "Mission", icon: "macwindow.on.rectangle", color: PixelHandTheme.accent, haptic: .light, colorScheme: colorScheme) {
                Task { await sender.sendSystemAction(.missionControl) }
            }
            .accessibilityLabel("Mission Control")
            GestureButton(label: "Desktop", icon: "menubar.rectangle",       color: PixelHandTheme.accent, haptic: .light, colorScheme: colorScheme) {
                // fn+F11 is a symbolic hot key a posted shortcut never fires;
                // the host runs Show Desktop itself.
                Task { await sender.sendSystemAction(.showDesktop) }
            }
            .accessibilityLabel("Show Desktop")
        }
    }
}

/// Dedicated scroll toggle with active state highlight.
private struct ScrollToggleButton: View {
    @Binding var isActive: Bool
    let colorScheme: ColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7)) {
                isActive.toggle()
            }
            GestureHaptic.medium.trigger()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: isActive ? "scroll.fill" : "scroll")
                    .font(.system(size: 28, weight: .thin))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? PixelHandTheme.success : PixelHandTheme.success.opacity(0.6))
                    .frame(height: 34)
                Text("Scroll")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? PixelHandTheme.success : Color.secondary.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                    .fill(isActive ? PixelHandTheme.success.opacity(colorScheme == .dark ? 0.15 : 0.1) : Color.clear)
            )
            .scaleEffect(isActive ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("One-finger scrolling")
        .accessibilityValue(isActive ? "On" : "Off")
    }
}

// MARK: - Sensitivity Snap

/// Discrete sensitivity stops + readout formatting. Centralized so the
/// slider, the label, and any future settings UI agree on the same set.
///
/// WID-405: the control snaps to a small set of labeled anchors instead of
/// a near-continuous 0.25 step, so the current level is readable at a
/// glance and each notch is a meaningfully different input feel.
enum TrackpadSensitivity {
    /// Recommended anchors per WID-405. Keep sorted ascending.
    static let anchors: [Float] = [0.75, 1.0, 1.5, 2.0, 3.0]
    static let defaultValue: Float = 1.5

    /// Index range for an index-driven Slider over `anchors`.
    static let indexRange: ClosedRange<Double> = 0...Double(anchors.count - 1)

    static func label(for value: Float) -> String {
        let snapped = anchors[nearestIndex(to: value)]
        if snapped == snapped.rounded() {
            return "\(Int(snapped))×"
        }
        return String(format: "%.2g×", snapped)
    }

    /// Index of the anchor closest to an arbitrary stored value, so old
    /// persisted sensitivities map onto the new stepped scale.
    static func nearestIndex(to value: Float) -> Int {
        var best = 0
        var bestDist = Float.greatestFiniteMagnitude
        for (i, anchor) in anchors.enumerated() {
            let d = abs(anchor - value)
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        return best
    }
}

// MARK: - Haptic style

enum GestureHaptic {
    case light, medium, heavy, double, selection
    /// Confirmation of a completed action (shortcut recorded, etc.).
    case success

    // Pre-allocated, process-lifetime generators. Constructing a
    // UIImpactFeedbackGenerator per trigger both churns the allocator and
    // skips the Taptic Engine warm-up, making the first pulse of each press
    // feel late. Every haptic in the app goes through here.
    @MainActor private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    @MainActor private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    @MainActor private static let selectionGen = UISelectionFeedbackGenerator()
    @MainActor private static let notificationGen = UINotificationFeedbackGenerator()

    /// The user's haptics preference, mirrored here by `DeckHandSettings`.
    /// Defaults to full so haptics work before settings are constructed.
    @MainActor static var strength: HapticStrength = .full

    @MainActor
    func trigger() {
        guard let scaled = Self.strength.resolve(self) else { return }
        scaled.play()
    }

    @MainActor
    private func play() {
        switch self {
        case .light:
            Self.lightGen.impactOccurred()
            Self.lightGen.prepare()
        case .medium:
            Self.mediumGen.impactOccurred()
            Self.mediumGen.prepare()
        case .heavy:
            Self.heavyGen.impactOccurred()
            Self.heavyGen.prepare()
        case .selection:
            Self.selectionGen.selectionChanged()
            Self.selectionGen.prepare()
        case .success:
            Self.notificationGen.notificationOccurred(.success)
            Self.notificationGen.prepare()
        case .double:
            Self.mediumGen.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Self.mediumGen.impactOccurred()
                Self.mediumGen.prepare()
            }
        }
    }
}

// MARK: - Gesture Button

struct GestureButton: View {
    let label: String
    let icon: String
    let color: Color
    var haptic: GestureHaptic = .medium
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            haptic.trigger()
            action()
        }) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .thin))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isPressed ? color : color.opacity(0.8))
                    .frame(height: 34)
                Text(label)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(isPressed ? 1.0 : 0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                    .fill(isPressed ? color.opacity(colorScheme == .dark ? 0.15 : 0.1) : Color.clear)
                    .animation(.easeOut(duration: 0.12), value: isPressed)
            )
            .scaleEffect(isPressed && !reduceMotion ? 0.90 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}
