//
//  CaretJoystick.swift
//  PixelHandCore
//
//  The arrow-key joystick (`Product/Design/RD-live-sync-and-caret.md`
//  §1.5, approved 2026-11-27): press and hold an arrow cap of the Type
//  panel for 300 ms, then drag without lifting. Left and right drags send
//  ←/→ (characters), up and down drags send ↑/↓ (lines), faster the
//  further the finger goes. Past 60 pt it moves by words (⌥←/→) or
//  paragraphs (⌥↑/↓). ⇧ latched selects; ⌥ latched moves by words from
//  the start. Release stops at once. A shorter press is a normal tap.
//
//  It only sends arrow keys, so it works in every app, terminals
//  included. In a terminal ↑/↓ walk the shell history, so they are named
//  HISTORY and go slower.
//
//  Pure maths: the iPad feeds it touches and clock ticks and sends the
//  steps it returns. All the numbers are in `Tuning`, with why.
//

import Foundation

public struct CaretJoystick: Sendable {

    // MARK: Tuning

    /// The numbers, from the R&D doc unless noted.
    public struct Tuning: Sendable, Hashable {
        /// How long a press must last before it becomes the joystick. 300 ms
        /// is longer than any deliberate tap (taps land in 80–150 ms) and
        /// shorter than iOS's own long-press (500 ms), so it feels quick
        /// without stealing slow taps.
        public var holdDelay: Double = 0.30
        /// How far the finger may wander before the hold fires and still
        /// count as a press. 10 pt is UIKit's tap slop; a finger that
        /// travels further before 300 ms is going somewhere else.
        public var tapSlop: Double = 10
        /// The first 10 pt of movement picks the axis (larger component).
        public var axisLock: Double = 10
        /// Back within 6 pt of the anchor, the axis is free again, so you
        /// can go right, come back and go down without lifting. Below the
        /// lock distance, so the lock doesn't flap at its own edge.
        public var axisRelease: Double = 6
        /// 0–12 pt along the axis sends nothing: a resting thumb shifts
        /// 4–8 pt, and 12 pt is about a quarter of a 44 pt cap.
        public var deadZone: Double = 12
        /// Full speed at 120 pt: about two and a half caps away, still
        /// inside the panel on an iPhone.
        public var fullSpeed: Double = 120
        /// 4 steps/s at the dead zone's edge: slow enough to stop on the
        /// exact character (one step per 250 ms, above reaction time).
        public var minRate: Double = 4
        /// 30 steps/s at full speed: the Mac's key repeat at its fastest
        /// setting is 30/s, so the caret never moves faster than a held
        /// key could, and the link (one key message per step) has room.
        public var maxRate: Double = 30
        /// Past 60 pt the unit becomes words or paragraphs.
        public var wordDistance: Double = 60
        /// …and goes back to characters or lines below 54 pt, so a finger
        /// resting on the boundary doesn't flip the unit (and its label).
        public var wordHysteresis: Double = 6
        /// Terminal history: 2–8 entries/s. Each ↑ redraws the shell line
        /// over the link; above about 8/s you can't read what you pass.
        public var historyMinRate: Double = 2
        public var historyMaxRate: Double = 8
        /// At most 15 step haptics a second: the Taptic Engine blurs
        /// faster taps into a buzz.
        public var hapticMaxRate: Double = 15
        /// A tick never sends more than 3 steps, so a hitch in the clock
        /// doesn't fire a burst.
        public var maxStepsPerTick: Int = 3
        /// Dot-matrix trail: one dot every 6 pt.
        public var trailPitch: Double = 6

        public init() {}

        public static let standard = Tuning()
    }

    // MARK: Types

    public enum Axis: Sendable, Hashable {
        case horizontal, vertical
    }

    /// What one step moves by.
    public enum Unit: String, Sendable, Hashable, CaseIterable {
        case character, word, line, paragraph
        /// ↑/↓ in a terminal: the shell's history, not lines of text.
        case history

        /// The trail's dot-matrix word.
        public var readoutWord: String {
            switch self {
            case .character: "CHAR"
            case .word: "WORD"
            case .line: "LINE"
            case .paragraph: "PARA"
            case .history: "HISTORY"
            }
        }

        /// VoiceOver's name for the unit.
        public var spokenName: String {
            switch self {
            case .character: "Characters"
            case .word: "Words"
            case .line: "Lines"
            case .paragraph: "Paragraphs"
            case .history: "History"
            }
        }

        public var axis: Axis {
            switch self {
            case .character, .word: .horizontal
            case .line, .paragraph, .history: .vertical
            }
        }
    }

    /// One key press to send.
    public struct Step: Sendable, Hashable {
        public let key: RemoteKey
        public let modifiers: [KeyModifier]

        public init(key: RemoteKey, modifiers: [KeyModifier]) {
            self.key = key
            self.modifiers = KeyModifier.pressOrder.filter(modifiers.contains)
        }

        /// `input.keyboardShortcut(keys:)`.
        public var chord: [String] { key.chord(with: modifiers) }

        /// The step for a unit, forward (→ / ↓) or back (← / ↑).
        public init(unit: Unit, forward: Bool, selecting: Bool) {
            let key: RemoteKey = switch unit.axis {
            case .horizontal: forward ? .right : .left
            case .vertical: forward ? .down : .up
            }
            var modifiers: [KeyModifier] = []
            if selecting { modifiers.append(.shift) }
            if unit == .word || unit == .paragraph { modifiers.append(.option) }
            self.init(key: key, modifiers: modifiers)
        }
    }

    /// Where the gesture is.
    public enum Phase: Sendable, Hashable {
        case idle
        /// Down on a cap, not yet held long enough: a tap so far.
        case pressed
        /// Held: the cluster is the joystick.
        case engaged
        /// Moved too far before the hold: neither a tap nor the joystick.
        case cancelled
    }

    /// What the touch-up means.
    public enum Release: Sendable, Hashable {
        /// A normal tap: send the cap's arrow once (with the latched
        /// modifiers, as any key).
        case tap(RemoteKey)
        /// The joystick ran and sent `steps` presses.
        case finished(steps: Int)
        /// Nothing to send.
        case nothing
    }

    /// What the latched modifiers ask of the joystick.
    public struct Modifiers: Sendable, Hashable {
        public var selecting: Bool
        public var byWords: Bool
        /// ⌘, ⌃ or fn latched: the press stays a plain tap. ⌃← switches
        /// desktops and ⌘← jumps to the line start, neither of which
        /// should repeat 30 times a second.
        public var blocksJoystick: Bool

        public init(_ held: [KeyModifier]) {
            selecting = held.contains(.shift)
            byWords = held.contains(.option)
            blocksJoystick = held.contains(.command) || held.contains(.control) || held.contains(.function)
        }
    }

    /// A clock tick's output.
    public struct Tick: Sendable, Hashable {
        public var steps: [Step] = []
        /// Play the step haptic (throttled).
        public var haptic = false
    }

    /// The speed indication beside the trail.
    public struct Readout: Sendable, Hashable {
        public let key: RemoteKey
        public let unit: Unit
        /// Steps per second, 0 in the dead zone.
        public let rate: Double
        /// 0 (dead zone edge) … 1 (full speed); 0 when still.
        public let speed: Double
        public let selecting: Bool

        /// "⌥⇧", "⇧", "⌥" or "": the modifiers each step carries.
        public var chordGlyphs: String {
            Step(unit: unit, forward: true, selecting: selecting).modifiers.map { modifier in
                switch modifier {
                case .option: "⌥"
                case .shift: "⇧"
                case .command: "⌘"
                case .control: "⌃"
                case .function: "fn"
                }
            }.reversed().joined()
        }

        /// "14/S · CHAR", or the unit alone while still.
        public var label: String {
            rate > 0 ? "\(Int(rate.rounded()))/S · \(unit.readoutWord)" : unit.readoutWord
        }

        /// VoiceOver / announcement text.
        public var spoken: String {
            let direction = switch key {
            case .left: "left"
            case .right: "right"
            case .up: "up"
            default: "down"
            }
            return "\(selecting ? "Selecting " : "")\(unit.spokenName) \(direction), \(Int(rate.rounded())) a second"
        }
    }

    /// One dot of the trail, in points from the anchor (the held cap's
    /// centre).
    public struct TrailDot: Sendable, Hashable {
        public enum Role: Sendable, Hashable {
            /// The centre dot on the held cap.
            case anchor
            /// A dot along the trail; `lit` dots show the speed.
            case trail(lit: Bool)
            /// The far dot, under the finger: phosphor.
            case head
        }

        public let x: Double
        public let y: Double
        public let role: Role
        /// 0 … 1, for the lit dots and the head (unlit dots draw as
        /// `dotOff`).
        public let brightness: Double
    }

    // MARK: State

    public let tuning: Tuning
    public private(set) var phase: Phase = .idle
    public private(set) var key: RemoteKey?
    public private(set) var isTerminal = false
    public private(set) var modifiers = Modifiers([])
    /// The finger's offset from where it went down.
    public private(set) var offset: (x: Double, y: Double) = (0, 0)
    public private(set) var axis: Axis?
    public private(set) var stepsSent = 0

    private var downTime: Double = 0
    private var active = false
    private var byWordsFromDistance = false
    private var accumulator: Double = 0
    private var lastTick: Double?
    private var lastHaptic: Double = -.infinity

    public init(tuning: Tuning = .standard) {
        self.tuning = tuning
    }

    public static let arrowKeys: Set<RemoteKey> = [.left, .right, .up, .down]

    // MARK: Touches

    /// A finger went down on `key`'s cap. `held` is the latched modifiers;
    /// `isTerminal` whether the Mac's front app is a terminal.
    public mutating func touchDown(key: RemoteKey, time: Double, held: [KeyModifier], isTerminal: Bool) {
        self = CaretJoystick(tuning: tuning)
        guard Self.arrowKeys.contains(key) else { return }
        self.key = key
        self.isTerminal = isTerminal
        modifiers = Modifiers(held)
        downTime = time
        phase = .pressed
    }

    /// The finger moved: `dx`, `dy` from where it went down. Returns
    /// `.engaged` when this move found the hold already due, `.cancelled`
    /// when it ended the press.
    @discardableResult
    public mutating func touchMoved(dx: Double, dy: Double, time: Double) -> Phase? {
        offset = (dx, dy)
        var changed: Phase?
        if phase == .pressed, holdElapsed(time: time) { changed = .engaged }
        if phase == .pressed, (dx * dx + dy * dy).squareRoot() > tuning.tapSlop {
            phase = .cancelled
            return .cancelled
        }
        if phase == .engaged { updateAxis() }
        return changed
    }

    /// The hold timer fired (or a move noticed it was due). Returns true
    /// when the joystick engages now: play the light haptic and morph.
    @discardableResult
    public mutating func holdElapsed(time: Double) -> Bool {
        guard phase == .pressed, time - downTime >= tuning.holdDelay - 1e-9 else { return false }
        // ⌘ ⌃ fn: stays a tap; a cap that already wandered: cancelled
        // on its next move.
        guard !modifiers.blocksJoystick else { return false }
        phase = .engaged
        lastTick = time
        updateAxis()
        return true
    }

    /// The finger lifted.
    public mutating func touchUp(time: Double) -> Release {
        defer { phase = .idle; active = false; axis = nil }
        switch phase {
        case .pressed:
            return key.map(Release.tap) ?? .nothing
        case .engaged:
            // Held but never dragged out of the dead zone: a slow tap is
            // still a tap.
            if stepsSent == 0, let key { return .tap(key) }
            return .finished(steps: stepsSent)
        case .idle, .cancelled:
            return .nothing
        }
    }

    /// The touch was taken away (another gesture, the panel closed).
    public mutating func cancel() {
        phase = .cancelled
        active = false
        axis = nil
    }

    // MARK: Clock

    /// Advances to `time` (the iPad calls it about 60 times a second while
    /// engaged) and returns the presses due.
    public mutating func tick(time: Double) -> Tick {
        guard phase == .engaged else { return Tick() }
        updateAxis()
        let previous = lastTick ?? time
        lastTick = time
        let dt = max(0, time - previous)
        guard let (step, rate) = currentStep() else {
            active = false
            accumulator = 0
            return Tick()
        }
        var count = 0
        if !active {
            // Leading edge: the first press goes as soon as the finger
            // leaves the dead zone, not a period later.
            active = true
            accumulator = 0
            count = 1
        } else {
            accumulator += rate * dt
            count = Int(accumulator.rounded(.down))
            accumulator -= Double(count)
            if count > tuning.maxStepsPerTick {
                count = tuning.maxStepsPerTick
                accumulator = 0
            }
        }
        guard count > 0 else { return Tick() }
        stepsSent += count
        var tick = Tick(steps: Array(repeating: step, count: count))
        if time - lastHaptic >= 1 / tuning.hapticMaxRate - 1e-9 {
            lastHaptic = time
            tick.haptic = true
        }
        return tick
    }

    // MARK: Reading

    /// The distance along the locked axis (0 before the lock).
    public var distance: Double {
        switch axis {
        case .horizontal: abs(offset.x)
        case .vertical: abs(offset.y)
        case nil: 0
        }
    }

    /// The step rate for a distance along `axis`, in steps per second.
    public func rate(distance: Double, axis: Axis) -> Double {
        guard distance >= tuning.deadZone else { return 0 }
        let t = Self.clamp((distance - tuning.deadZone) / (tuning.fullSpeed - tuning.deadZone))
        if isTerminal, axis == .vertical {
            return tuning.historyMinRate + (tuning.historyMaxRate - tuning.historyMinRate) * t
        }
        return tuning.minRate + (tuning.maxRate - tuning.minRate) * t
    }

    /// The unit for the current distance and modifiers.
    public var unit: Unit {
        let vertical = axis == .vertical
        if vertical, isTerminal { return .history }
        let words = modifiers.byWords || byWordsFromDistance
        if vertical { return words ? .paragraph : .line }
        return words ? .word : .character
    }

    /// The speed indication while engaged (`nil` before the axis lock).
    public var readout: Readout? {
        guard phase == .engaged, let axis, let key = directionKey else { return nil }
        let rate = rate(distance: distance, axis: axis)
        let speed = rate > 0 ? Self.clamp((distance - tuning.deadZone) / (tuning.fullSpeed - tuning.deadZone)) : 0
        return Readout(key: key, unit: unit, rate: rate, speed: speed, selecting: modifiers.selecting)
    }

    /// The dot-matrix trail from the anchor along the locked axis to the
    /// finger's place on it; the anchor alone before the lock. The share
    /// of lit dots follows the speed, lit toward the finger.
    public var trail: [TrailDot] {
        guard phase == .engaged else { return [] }
        let anchor = TrailDot(x: 0, y: 0, role: .anchor, brightness: 1)
        guard let axis else { return [anchor] }
        let end: (x: Double, y: Double) = axis == .horizontal ? (offset.x, 0) : (0, offset.y)
        let length = distance
        let count = Int((length / tuning.trailPitch).rounded())
        guard count >= 1 else { return [anchor] }
        let speed = readout?.speed ?? 0
        var dots = [anchor]
        for index in 1...count {
            let t = Double(index) / Double(count)
            let x = end.x * t, y = end.y * t
            if index == count {
                dots.append(TrailDot(x: x, y: y, role: .head, brightness: 1))
            } else {
                // Lit from the finger back, as many as the speed.
                let lit = rate(distance: distance, axis: axis) > 0 && t >= 1 - speed - 1e-9
                let brightness = lit ? 0.25 + 0.75 * pow(t, 1.6) : 0
                dots.append(TrailDot(x: x, y: y, role: .trail(lit: lit), brightness: brightness))
            }
        }
        return dots
    }

    // MARK: Private

    private var directionKey: RemoteKey? {
        switch axis {
        case .horizontal: offset.x < 0 ? .left : .right
        case .vertical: offset.y < 0 ? .up : .down
        case nil: nil
        }
    }

    private mutating func updateAxis() {
        let radius = (offset.x * offset.x + offset.y * offset.y).squareRoot()
        if axis != nil, radius <= tuning.axisRelease {
            axis = nil
            active = false
            byWordsFromDistance = false
        }
        if axis == nil, max(abs(offset.x), abs(offset.y)) >= tuning.axisLock {
            axis = abs(offset.x) >= abs(offset.y) ? .horizontal : .vertical
        }
        // Words/paragraphs past 60 pt, back below 54 pt.
        if byWordsFromDistance {
            if distance < tuning.wordDistance - tuning.wordHysteresis { byWordsFromDistance = false }
        } else if distance >= tuning.wordDistance {
            byWordsFromDistance = true
        }
    }

    private func currentStep() -> (Step, Double)? {
        guard let axis, let key = directionKey else { return nil }
        let rate = rate(distance: distance, axis: axis)
        guard rate > 0 else { return nil }
        let forward = key == .right || key == .down
        return (Step(unit: unit, forward: forward, selecting: modifiers.selecting), rate)
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

// MARK: - VoiceOver

/// The joystick for VoiceOver: one adjustable element ("Move the caret")
/// whose swipe up and down steps forward and back by a chosen unit, and
/// custom actions to pick the unit. The arrow caps stay their own buttons.
public enum CaretStepper {
    /// The units on offer: in a terminal, ↑/↓ are history and there are
    /// no paragraphs.
    public static func units(isTerminal: Bool) -> [CaretJoystick.Unit] {
        isTerminal ? [.character, .word, .history] : [.character, .word, .line, .paragraph]
    }

    /// The press for one adjustment: increment moves forward (→ / ↓, or
    /// to newer history), decrement back.
    public static func step(unit: CaretJoystick.Unit, increment: Bool, held: [KeyModifier]) -> CaretJoystick.Step {
        CaretJoystick.Step(unit: unit, forward: increment, selecting: held.contains(.shift))
    }

    /// The element's value: "Words", "Selecting words".
    public static func spokenValue(unit: CaretJoystick.Unit, held: [KeyModifier]) -> String {
        held.contains(.shift) ? "Selecting \(unit.spokenName.lowercased())" : unit.spokenName
    }

    /// The unit to keep when the front app changes (a terminal has no
    /// lines or paragraphs; anything else has no history).
    public static func coerce(_ unit: CaretJoystick.Unit, isTerminal: Bool) -> CaretJoystick.Unit {
        if units(isTerminal: isTerminal).contains(unit) { return unit }
        return unit.axis == .vertical ? (isTerminal ? .history : .line) : .character
    }
}

// MARK: - Terminals

/// Mac terminal apps, where ↑/↓ mean shell history (R&D doc §1.1: matched
/// by bundle ID, an app-side list). The Mac's front-app report carries
/// the bundle ID; the name is the fallback when it doesn't.
public enum TerminalApps {
    public static let bundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "io.alacritty",
        "co.zeit.hyper",
        "com.raphaelamorim.rio",
        "org.tabby",
    ]

    public static let names: Set<String> = [
        "terminal", "iterm", "iterm2", "ghostty", "warp", "wezterm", "kitty", "alacritty", "hyper", "rio", "tabby",
    ]

    public static func isTerminal(bundleID: String?, name: String?) -> Bool {
        if let bundleID { return bundleIDs.contains(bundleID) }
        guard let name else { return false }
        return names.contains(name.lowercased())
    }
}
