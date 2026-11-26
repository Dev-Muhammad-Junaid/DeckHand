//
//  ArrowJoystick.swift
//  DeckHandiOS – Keyboard
//
//  The arrow-key joystick on the Type panel's arrow cluster
//  (`Product/Design/RD-live-sync-and-caret.md` §1.5, approved
//  2026-11-27). Press and hold any arrow cap for 300 ms, then drag: the
//  held cap turns accent with a centre dot, and a dot-matrix trail runs
//  from it along the locked axis to the finger, its lit dots showing the
//  speed, with a readout ("14/S · CHAR"). Release stops. A shorter press
//  is a normal tap: one arrow, no morph.
//
//      ┌───┐
//      │ ↑ │                 ┌──────────────┐
//  ┌───┼───┼───┐             │ → 14/S · CHAR│
//  │ ← │ ↓ │ ● ▪ ▪ ▪ ▫ ▫ ▪ ■ └──────────────┘
//  └───┴───┴───┘  anchor → trail → head (finger)
//
//  The maths (hold, dead zone, axis lock, rate, words, ⇧/⌥, terminals,
//  haptic throttle, trail) is Core's `CaretJoystick`; this file feeds it
//  touches and a 60 Hz clock and sends the presses as ordinary
//  `input.keyboardShortcut` messages, so it works in every Mac app.
//
//  VoiceOver: the caps stay buttons (one arrow each, plus "Move by words"
//  / "Move by paragraphs"); "Move the caret" is an adjustable element
//  whose swipe up/down steps by a unit picked from its actions.
//

import PixelHandCore
import SwiftUI

@MainActor
@Observable
final class ArrowJoystickModel {
    /// What a press needs from the panel, captured at touch-down.
    struct Context {
        /// The latched modifiers now (not consumed).
        var held: [KeyModifier]
        var isTerminal: Bool
        /// A normal tap: the panel sends the arrow as any key.
        var tap: (RemoteKey) -> Void
        /// The joystick engaged (the panel marks activity).
        var engaged: () -> Void
        /// Send one press.
        var send: (CaretJoystick.Step) -> Void
        /// The joystick ran and sent presses: consume once-latched
        /// modifiers.
        var finished: () -> Void
    }

    /// Core's state: phase, trail, readout.
    private(set) var engine = CaretJoystick()
    /// The cap under the finger (for the tap's pressed look).
    private(set) var pressedKey: RemoteKey?
    /// The held cap's centre in the cluster's coordinates.
    private(set) var anchor: CGPoint = .zero
    /// The trail fades for 300 ms after release (not with Reduce Motion).
    private(set) var fadingTrail: [CaretJoystick.TrailDot] = []
    private(set) var fadingAnchor: CGPoint = .zero
    private(set) var fadeStart: TimeInterval = 0
    /// VoiceOver's unit for "Move the caret".
    var stepperUnit: CaretJoystick.Unit = .character
    /// The last gesture, for the UI walk (`-qa.exposeJoystick YES`).
    private(set) var lastRun = "none"

    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    static let fade: TimeInterval = 0.3
    static let exposedForQA = UserDefaults.standard.bool(forKey: "qa.exposeJoystick")

    var isEngaged: Bool { engine.phase == .engaged }
    var heldKey: RemoteKey? { isEngaged ? engine.key : nil }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Touches

    func down(key: RemoteKey, anchor: CGPoint, context: Context) {
        stop()
        self.context = context
        self.anchor = anchor
        pressedKey = key
        engine.touchDown(key: key, time: Self.now, held: context.held, isTerminal: context.isTerminal)
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CaretJoystick.Tuning.standard.holdDelay))
            guard !Task.isCancelled, let self else { return }
            if self.engine.holdElapsed(time: Self.now) { self.didEngage() }
        }
    }

    func moved(_ translation: CGSize) {
        guard engine.phase == .pressed || engine.phase == .engaged else { return }
        let change = engine.touchMoved(dx: Double(translation.width), dy: Double(translation.height), time: Self.now)
        switch change {
        case .some(.engaged): didEngage()
        case .some(.cancelled): pressedKey = nil
        default: break
        }
    }

    func up(reduceMotion: Bool) {
        let trail = engine.trail
        let release = engine.touchUp(time: Self.now)
        let context = self.context
        stop()
        if !reduceMotion, !trail.isEmpty {
            fadingTrail = trail
            fadingAnchor = anchor
            fadeStart = Self.now
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.fade + 0.05))
                guard let self, self.fadeStart <= Self.now - Self.fade else { return }
                self.fadingTrail = []
            }
        }
        switch release {
        case let .tap(key):
            lastRun = "tap \(key.wireName)"
            context?.tap(key)
        case let .finished(steps):
            lastRun = "joystick \(steps)"
            context?.finished()
        case .nothing:
            lastRun = "cancelled"
        }
    }

    /// The touch went away without an end (the panel closed, a system
    /// gesture took it): nothing more is sent.
    func cancel() {
        guard engine.phase != .idle else { return }
        engine.cancel()
        stop()
    }

    // MARK: Private

    private func didEngage() {
        holdTask?.cancel()
        GestureHaptic.light.trigger()
        context?.engaged()
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self, self.isEngaged else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let tick = engine.tick(time: Self.now)
        guard !tick.steps.isEmpty else { return }
        if tick.haptic { GestureHaptic.selection.trigger() }
        for step in tick.steps { context?.send(step) }
    }

    private func stop() {
        holdTask?.cancel()
        tickTask?.cancel()
        holdTask = nil
        tickTask = nil
        pressedKey = nil
        context = nil
    }
}

// MARK: - The gesture on one cap

extension View {
    /// Makes an arrow cap the joystick's handle. The cap stays a Button
    /// for VoiceOver, Full Keyboard Access and pointer focus; a touch is
    /// taken by this gesture first, which taps or drives the joystick.
    func arrowJoystick(
        key: RemoteKey,
        column: Int,
        row: Int,
        model: ArrowJoystickModel,
        context: @escaping () -> ArrowJoystickModel.Context
    ) -> some View {
        modifier(ArrowJoystickGesture(key: key, column: column, row: row, model: model, context: context))
    }
}

private struct ArrowJoystickGesture: ViewModifier {
    let key: RemoteKey
    let column: Int
    let row: Int
    let model: ArrowJoystickModel
    let context: () -> ArrowJoystickModel.Context

    @Environment(\.typeKeyCell) private var cell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var touching = false
    /// This cap's touch is under way (its first change came in).
    @State private var began = false

    func body(content: Content) -> some View {
        content
            // The tap's pressed look, as `ChipPressStyle` (the Button
            // doesn't see the touch any more). No morph until the hold.
            .opacity(model.pressedKey == key && model.engine.phase == .pressed ? 0.75 : 1)
            .animation(PixelHandMotion.quick, value: model.pressedKey == key)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        if !began {
                            began = true
                            let anchor = CGPoint(x: (CGFloat(column) + 0.5) * cell.width, y: (CGFloat(row) + 0.5) * cell.height)
                            model.down(key: key, anchor: anchor, context: context())
                        } else {
                            model.moved(value.translation)
                        }
                    }
                    .onEnded { _ in
                        began = false
                        model.up(reduceMotion: reduceMotion)
                    }
            )
            .onChange(of: touching) { _, isTouching in
                guard !isTouching else { return }
                // The gesture state resets on an end and on a cancel; only
                // a cancel leaves `began` set once `onEnded` had its turn.
                Task { @MainActor in
                    guard began else { return }
                    began = false
                    model.cancel()
                }
            }
    }
}

// MARK: - Trail and readout

/// The joystick's dot-matrix trail and speed readout, drawn over the
/// cluster (and past it) while engaged; never takes touches.
struct ArrowJoystickOverlay: View {
    let model: ArrowJoystickModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// The trail may run this far past the cluster.
    private static let reach: CGFloat = 220

    var body: some View {
        let engine = model.engine
        let live = engine.trail
        ZStack(alignment: .topLeading) {
            if !live.isEmpty {
                dots(live, anchor: model.anchor, opacity: 1, selecting: engine.modifiers.selecting)
            } else if !model.fadingTrail.isEmpty, !reduceMotion {
                TimelineView(.animation) { _ in
                    let elapsed = ProcessInfo.processInfo.systemUptime - model.fadeStart
                    let left = max(0, 1 - elapsed / ArrowJoystickModel.fade)
                    dots(model.fadingTrail, anchor: model.fadingAnchor, opacity: left, selecting: false)
                }
            }
            if let readout = engine.readout, let head = live.last {
                readoutChip(readout)
                    .fixedSize()
                    .position(readoutPosition(head: head, axis: engine.axis))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dots(_ trail: [CaretJoystick.TrailDot], anchor: CGPoint, opacity: Double, selecting: Bool) -> some View {
        let reach = Self.reach
        let pitch = CaretJoystick.Tuning.standard.trailPitch
        let geometry = DotGeometry.glyph
        let side = CGFloat(geometry.dotSide(pitch: pitch))
        let radius = CGFloat(geometry.cornerRadius(pitch: pitch))
        let litColor = selecting ? PixelHandTheme.accent : (scheme == .dark ? PixelHandTheme.Brand.glow : PixelHandTheme.accent)
        let headColor = scheme == .dark ? PixelHandTheme.Brand.phosphor : PixelHandTheme.Brand.cobalt
        return Canvas { context, _ in
            for dot in trail {
                let center = CGPoint(x: anchor.x + reach + CGFloat(dot.x), y: anchor.y + reach + CGFloat(dot.y))
                let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                let path = Path(roundedRect: rect, cornerRadius: radius)
                switch dot.role {
                case .anchor:
                    // The centre dot sits on the accent cap: white.
                    context.fill(path, with: .color(.white))
                case .head:
                    context.fill(path, with: .color(headColor))
                case let .trail(lit):
                    if lit {
                        context.fill(path, with: .color(litColor.opacity(dot.brightness)))
                    } else {
                        context.fill(path, with: .color(PixelHandTheme.Brand.dotOff))
                    }
                }
            }
        }
        .frame(width: 2 * reach, height: 2 * reach)
        .offset(x: -reach, y: -reach)
        .opacity(opacity)
    }

    private func readoutChip(_ readout: CaretJoystick.Readout) -> some View {
        HStack(spacing: 6) {
            if !readout.chordGlyphs.isEmpty {
                Text(readout.chordGlyphs)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            PHGlyph(glyph: glyph(readout.key), pitch: 1.3)
            DotMatrixText(readout.label, pitch: 1.4, label: readout.spoken, glows: true, stepsWithType: false)
        }
        .foregroundStyle(PixelHandTheme.Brand.phosphor)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(PixelHandTheme.Brand.screen.opacity(0.92), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .environment(\.pixelOnNavy, true)
    }

    /// Above the finger for ←/→, beside it for ↑/↓, so the finger never
    /// covers it.
    private func readoutPosition(head: CaretJoystick.TrailDot, axis: CaretJoystick.Axis?) -> CGPoint {
        let point = CGPoint(x: model.anchor.x + CGFloat(head.x), y: model.anchor.y + CGFloat(head.y))
        return axis == .vertical
            ? CGPoint(x: point.x + 78, y: point.y)
            : CGPoint(x: point.x, y: point.y - 40)
    }

    private func glyph(_ key: RemoteKey) -> GlyphBitmap {
        switch key {
        case .left: PixelGlyphs.keyLeft
        case .right: PixelGlyphs.keyRight
        case .up: PixelGlyphs.keyUp
        default: PixelGlyphs.keyDown
        }
    }
}

// MARK: - VoiceOver

/// "Move the caret": swipe up to step forward, down to step back, by the
/// unit its actions pick. Sits behind the caps, as big as the cluster,
/// so touch exploration finds the caps first and swiping reaches it.
struct CaretStepperElement: View {
    @Bindable var model: ArrowJoystickModel
    let isTerminal: Bool
    let held: () -> [KeyModifier]
    let send: (CaretJoystick.Step) -> Void

    var body: some View {
        let unit = CaretStepper.coerce(model.stepperUnit, isTerminal: isTerminal)
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Move the caret")
            .accessibilityValue(CaretStepper.spokenValue(unit: unit, held: held()))
            .accessibilityHint("Swipe up to move forward, down to move back. Actions choose what a step moves by.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: send(CaretStepper.step(unit: unit, increment: true, held: held()))
                case .decrement: send(CaretStepper.step(unit: unit, increment: false, held: held()))
                @unknown default: break
                }
            }
            .accessibilityActions {
                ForEach(CaretStepper.units(isTerminal: isTerminal), id: \.self) { choice in
                    Button("By \(choice.spokenName.lowercased())") { model.stepperUnit = choice }
                }
            }
            .accessibilityIdentifier("ph.type.joystick")
    }
}

/// The last joystick gesture for the UI walk (`-qa.exposeJoystick YES`):
/// "tap left", "joystick 23", "cancelled".
struct ArrowJoystickQAProbe: View {
    let model: ArrowJoystickModel

    var body: some View {
        if ArrowJoystickModel.exposedForQA {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Joystick")
                .accessibilityValue(model.lastRun)
                .accessibilityIdentifier("ph.type.joystick.last")
        }
    }
}
