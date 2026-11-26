//
//  CaretJoystickTests.swift
//  PixelHandCoreTests
//
//  The arrow-key joystick (`RD-live-sync-and-caret.md` §1.5): hold an
//  arrow cap, then drag. Taps stay taps; the hold, dead zone, axis lock,
//  rate curve, unit switch, modifiers, terminals, haptic throttle and the
//  trail.
//

import Foundation
import Testing
@testable import PixelHandCore

private typealias J = CaretJoystick

/// Down on `key`, held past the delay; returns the engaged joystick.
private func engaged(_ key: RemoteKey = .right, held: [KeyModifier] = [], terminal: Bool = false) -> J {
    var joystick = J()
    joystick.touchDown(key: key, time: 0, held: held, isTerminal: terminal)
    let r1 = joystick.holdElapsed(time: 0.3)
    #expect(r1)
    return joystick
}

/// Holds the finger at (dx, dy) for `seconds`, ticking at 60 Hz from
/// `start`; returns every step sent.
private func run(_ joystick: inout J, dx: Double, dy: Double, from start: Double = 0.3, seconds: Double) -> [J.Step] {
    joystick.touchMoved(dx: dx, dy: dy, time: start)
    var steps: [J.Step] = []
    var time = start
    let end = start + seconds
    while time < end - 1e-9 {
        time += 1.0 / 60
        steps += joystick.tick(time: time).steps
    }
    return steps
}

@Suite("Caret joystick: taps and the hold")
struct CaretJoystickHoldTests {
    @Test("A quick tap sends one arrow and never engages")
    func tapIsTap() {
        var joystick = J()
        joystick.touchDown(key: .left, time: 0, held: [], isTerminal: false)
        let r2 = joystick.holdElapsed(time: 0.12)
        #expect(!r2)
        #expect(joystick.phase == .pressed)
        #expect(joystick.trail.isEmpty, "no morph, no flicker on a tap")
        let r3 = joystick.touchUp(time: 0.12)
        #expect(r3 == .tap(.left))
    }

    @Test("A tap with a little jitter is still a tap")
    func jitterTap() {
        var joystick = J()
        joystick.touchDown(key: .up, time: 0, held: [], isTerminal: false)
        let r4 = joystick.touchMoved(dx: 4, dy: -5, time: 0.05)
        #expect(r4 == nil)
        let r5 = joystick.touchUp(time: 0.1)
        #expect(r5 == .tap(.up))
    }

    @Test("Holding 300 ms engages; 299 ms doesn't")
    func holdDelay() {
        var joystick = J()
        joystick.touchDown(key: .down, time: 10, held: [], isTerminal: false)
        let r6 = joystick.holdElapsed(time: 10.299)
        #expect(!r6)
        let r7 = joystick.holdElapsed(time: 10.3)
        #expect(r7)
        #expect(joystick.phase == .engaged)
        let r8 = joystick.holdElapsed(time: 10.4)
        #expect(!r8, "engages once")
        #expect(joystick.trail == [J.TrailDot(x: 0, y: 0, role: .anchor, brightness: 1)], "the centre dot")
    }

    @Test("A move after the delay engages even if the timer is late")
    func moveFindsHoldDue() {
        var joystick = J()
        joystick.touchDown(key: .right, time: 0, held: [], isTerminal: false)
        let r9 = joystick.touchMoved(dx: 30, dy: 0, time: 0.35)
        #expect(r9 == .engaged)
        #expect(joystick.phase == .engaged)
    }

    @Test("Moving past the slop before the hold cancels: no tap, no joystick")
    func slopCancels() {
        var joystick = J()
        joystick.touchDown(key: .right, time: 0, held: [], isTerminal: false)
        let r10 = joystick.touchMoved(dx: 14, dy: 0, time: 0.1)
        #expect(r10 == .cancelled)
        let r11 = joystick.holdElapsed(time: 0.4)
        #expect(!r11)
        let r12 = joystick.touchUp(time: 0.5)
        #expect(r12 == .nothing)
    }

    @Test("Held still and released (a slow tap) sends one arrow")
    func slowTap() {
        var joystick = engaged(.left)
        let r13 = joystick.tick(time: 0.5)
        #expect(r13.steps.isEmpty)
        let r14 = joystick.touchUp(time: 0.6)
        #expect(r14 == .tap(.left))
    }

    @Test("Release stops at once and reports the steps")
    func releaseStops() {
        var joystick = engaged()
        let steps = run(&joystick, dx: 60, dy: 0, seconds: 1)
        let r15 = joystick.touchUp(time: 1.3)
        #expect(r15 == .finished(steps: steps.count))
        let r16 = joystick.tick(time: 1.4)
        #expect(r16.steps.isEmpty, "no inertia")
        #expect(joystick.trail.isEmpty)
    }

    @Test("⌘, ⌃ or fn latched keeps the press a plain tap")
    func blockingModifiers() {
        for modifier in [KeyModifier.command, .control, .function] {
            var joystick = J()
            joystick.touchDown(key: .left, time: 0, held: [modifier], isTerminal: false)
            let r17 = joystick.holdElapsed(time: 0.5)
            #expect(!r17)
            let r18 = joystick.touchUp(time: 0.6)
            #expect(r18 == .tap(.left))
        }
    }

    @Test("Only arrow caps drive the joystick")
    func onlyArrows() {
        var joystick = J()
        joystick.touchDown(key: .return, time: 0, held: [], isTerminal: false)
        #expect(joystick.phase == .idle)
        let r19 = joystick.holdElapsed(time: 1)
        #expect(!r19)
        let r20 = joystick.touchUp(time: 1)
        #expect(r20 == .nothing)
    }
}

@Suite("Caret joystick: dead zone, axis and rate")
struct CaretJoystickMotionTests {
    @Test("Inside the 12 pt dead zone nothing is sent")
    func deadZone() {
        var joystick = engaged()
        #expect(run(&joystick, dx: 11, dy: 0, seconds: 1).isEmpty)
        #expect(joystick.readout?.rate == 0)
        #expect(joystick.readout?.label == "CHAR")
    }

    @Test("Leaving the dead zone sends the first step at once")
    func leadingEdge() {
        var joystick = engaged()
        joystick.touchMoved(dx: 13, dy: 0, time: 0.3)
        let r21 = joystick.tick(time: 0.31)
        #expect(r21.steps == [J.Step(key: .right, modifiers: [])])
    }

    @Test("The first 10 pt pick the axis by the larger component")
    func axisLock() {
        var joystick = engaged(.up)
        joystick.touchMoved(dx: 4, dy: -9, time: 0.31)
        #expect(joystick.axis == nil)
        joystick.touchMoved(dx: 5, dy: -11, time: 0.32)
        #expect(joystick.axis == .vertical)
        // Wandering sideways later doesn't change the axis.
        joystick.touchMoved(dx: 60, dy: -20, time: 0.33)
        #expect(joystick.axis == .vertical)
        #expect(joystick.distance == 20)
        let r22 = joystick.tick(time: 0.34)
        #expect(r22.steps.first?.key == .up)
    }

    @Test("Back near the anchor, the axis is free again")
    func axisRelease() {
        var joystick = engaged()
        joystick.touchMoved(dx: 30, dy: 0, time: 0.31)
        #expect(joystick.axis == .horizontal)
        joystick.touchMoved(dx: 7, dy: 0, time: 0.32)
        #expect(joystick.axis == .horizontal, "outside 6 pt: still locked")
        joystick.touchMoved(dx: 3, dy: 2, time: 0.33)
        #expect(joystick.axis == nil)
        joystick.touchMoved(dx: 2, dy: 30, time: 0.34)
        #expect(joystick.axis == .vertical)
        let r23 = joystick.tick(time: 0.35)
        #expect(r23.steps.first?.key == .down)
    }

    @Test("Rate: 4/s at 12 pt rising linearly to 30/s at 120 pt, flat after")
    func rateCurve() {
        let joystick = J()
        #expect(joystick.rate(distance: 11.9, axis: .horizontal) == 0)
        #expect(joystick.rate(distance: 12, axis: .horizontal) == 4)
        #expect(abs(joystick.rate(distance: 66, axis: .horizontal) - 17) < 1e-9)
        #expect(joystick.rate(distance: 120, axis: .horizontal) == 30)
        #expect(joystick.rate(distance: 300, axis: .vertical) == 30)
        // The board's examples: 52 pt → 14/s, 96 pt → 24/s.
        #expect(Int(joystick.rate(distance: 52, axis: .horizontal).rounded()) == 14)
        #expect(Int(joystick.rate(distance: 96, axis: .horizontal).rounded()) == 24)
    }

    @Test("Steps per second follow the rate and grow with distance")
    func stepsGrowWithDistance() {
        var near = engaged()
        let slow = run(&near, dx: 20, dy: 0, seconds: 2).count
        var far = engaged()
        let fast = run(&far, dx: 120, dy: 0, seconds: 2).count
        // 20 pt ≈ 5.9/s, 120 pt = 30/s; one leading step each.
        #expect((11...13).contains(slow), "\(slow)")
        #expect((59...61).contains(fast), "\(fast)")
    }

    @Test("A hitch in the clock never fires more than 3 steps")
    func burstCap() {
        var joystick = engaged()
        joystick.touchMoved(dx: 120, dy: 0, time: 0.3)
        _ = joystick.tick(time: 0.31)
        let r24 = joystick.tick(time: 1.5)
        #expect(r24.steps.count == 3)
    }

    @Test("Left and right drags send ←/→; up and down send ↑/↓")
    func directions() {
        let cases: [(Double, Double, RemoteKey)] = [(-40, 0, .left), (40, 0, .right), (0, -40, .up), (0, 40, .down)]
        for (dx, dy, key) in cases {
            var joystick = engaged(.down)
            let steps = run(&joystick, dx: dx, dy: dy, seconds: 0.2)
            #expect(!steps.isEmpty)
            #expect(steps.allSatisfy { $0 == J.Step(key: key, modifiers: []) })
        }
    }
}

@Suite("Caret joystick: units and modifiers")
struct CaretJoystickUnitTests {
    @Test("Past 60 pt: words (⌥←/→) and paragraphs (⌥↑/↓)")
    func wordSwitch() {
        var joystick = engaged()
        joystick.touchMoved(dx: 59, dy: 0, time: 0.3)
        #expect(joystick.unit == .character)
        joystick.touchMoved(dx: 61, dy: 0, time: 0.3)
        #expect(joystick.unit == .word)
        let r25 = joystick.tick(time: 0.31)
        #expect(r25.steps == [J.Step(key: .right, modifiers: [.option])])

        var vertical = engaged(.up)
        vertical.touchMoved(dx: 0, dy: -70, time: 0.3)
        #expect(vertical.unit == .paragraph)
        let r26 = vertical.tick(time: 0.31)
        #expect(r26.steps.first?.chord == ["option", "up"])
    }

    @Test("The unit switch has 6 pt of hysteresis")
    func wordHysteresis() {
        var joystick = engaged()
        joystick.touchMoved(dx: 62, dy: 0, time: 0.3)
        #expect(joystick.unit == .word)
        joystick.touchMoved(dx: 56, dy: 0, time: 0.31)
        #expect(joystick.unit == .word, "stays words just under 60")
        joystick.touchMoved(dx: 53, dy: 0, time: 0.32)
        #expect(joystick.unit == .character)
    }

    @Test("⇧ latched selects: every step is ⇧+arrow, and the readout says so")
    func shiftSelects() {
        var joystick = engaged(held: [.shift])
        let steps = run(&joystick, dx: 30, dy: 0, seconds: 0.3)
        #expect(steps.allSatisfy { $0.chord == ["shift", "right"] })
        #expect(joystick.readout?.selecting == true)
        #expect(joystick.readout?.chordGlyphs == "⇧")
    }

    @Test("⌥ latched moves by words from the start; with ⇧ it's ⌥⇧ (board j2)")
    func optionWords() {
        var joystick = engaged(held: [.option])
        joystick.touchMoved(dx: 20, dy: 0, time: 0.3)
        #expect(joystick.unit == .word)
        let r27 = joystick.tick(time: 0.31)
        #expect(r27.steps.first?.chord == ["option", "right"])

        var both = engaged(held: [.shift, .option])
        both.touchMoved(dx: 96, dy: 0, time: 0.3)
        let r28 = both.tick(time: 0.31)
        #expect(r28.steps.first?.chord == ["shift", "option", "right"])
        #expect(both.readout?.chordGlyphs == "⌥⇧")
        #expect(both.readout?.label == "24/S · WORD")
    }
}

@Suite("Caret joystick: terminals")
struct CaretJoystickTerminalTests {
    @Test("In a terminal ↑/↓ are HISTORY: never paragraphs, 2–8 a second")
    func history() {
        var joystick = engaged(.up, terminal: true)
        joystick.touchMoved(dx: 0, dy: -100, time: 0.3)
        #expect(joystick.unit == .history)
        #expect(joystick.readout?.label.hasSuffix("HISTORY") == true)
        let r29 = joystick.tick(time: 0.31)
        #expect(r29.steps == [J.Step(key: .up, modifiers: [])])
        #expect(joystick.rate(distance: 12, axis: .vertical) == 2)
        #expect(joystick.rate(distance: 200, axis: .vertical) == 8)
        #expect(joystick.rate(distance: 120, axis: .horizontal) == 30, "←/→ keep full speed")
    }

    @Test("Terminal bundle IDs and names are recognized")
    func detection() {
        #expect(TerminalApps.isTerminal(bundleID: "com.apple.Terminal", name: "Terminal"))
        #expect(TerminalApps.isTerminal(bundleID: "com.googlecode.iterm2", name: nil))
        #expect(TerminalApps.isTerminal(bundleID: "com.mitchellh.ghostty", name: "Ghostty"))
        #expect(!TerminalApps.isTerminal(bundleID: "com.apple.TextEdit", name: "Terminal"), "the bundle ID wins")
        #expect(TerminalApps.isTerminal(bundleID: nil, name: "iTerm2"))
        #expect(!TerminalApps.isTerminal(bundleID: nil, name: "Safari"))
        #expect(!TerminalApps.isTerminal(bundleID: nil, name: nil))
    }
}

@Suite("Caret joystick: haptics and trail")
struct CaretJoystickFeedbackTests {
    @Test("Step haptics are throttled to 15 a second")
    func hapticThrottle() {
        var joystick = engaged()
        joystick.touchMoved(dx: 120, dy: 0, time: 0.3)
        var haptics = 0
        var steps = 0
        var time = 0.3
        while time < 1.3 - 1e-9 {
            time += 1.0 / 120
            let tick = joystick.tick(time: time)
            steps += tick.steps.count
            if tick.haptic { haptics += 1 }
        }
        #expect(steps >= 29)
        #expect((14...16).contains(haptics), "\(haptics)")
    }

    @Test("The trail runs along the locked axis, a dot every 6 pt, the head last")
    func trailShape() {
        var joystick = engaged()
        joystick.touchMoved(dx: 60, dy: 9, time: 0.3)
        let dots = joystick.trail
        #expect(dots.first?.role == .anchor)
        #expect(dots.last?.role == .head)
        #expect(dots.last?.x == 60 && dots.last?.y == 0, "projected on the axis")
        #expect(dots.count == 11)
        #expect(dots.allSatisfy { $0.y == 0 })
    }

    @Test("More speed lights more dots, toward the finger")
    func trailLights() {
        func litShare(_ distance: Double) -> Double {
            var joystick = engaged()
            joystick.touchMoved(dx: distance, dy: 0, time: 0.3)
            let middle = joystick.trail.filter { if case .trail = $0.role { true } else { false } }
            let lit = middle.filter { $0.role == .trail(lit: true) }
            // The lit dots are the far ones.
            if let firstLit = middle.firstIndex(where: { $0.role == .trail(lit: true) }) {
                #expect(middle[firstLit...].allSatisfy { $0.role == .trail(lit: true) })
            }
            return Double(lit.count) / Double(max(1, middle.count))
        }
        let slow = litShare(30), fast = litShare(110)
        #expect(slow < fast)
        #expect(fast > 0.8)
        var still = engaged()
        still.touchMoved(dx: 11, dy: 0, time: 0.3)
        #expect(still.trail.allSatisfy { $0.role != .trail(lit: true) }, "nothing lit in the dead zone")
    }
}

@Suite("Caret joystick: VoiceOver stepper")
struct CaretStepperTests {
    @Test("Adjusting steps forward and back by the chosen unit")
    func steps() {
        #expect(CaretStepper.step(unit: .character, increment: true, held: []).chord == ["right"])
        #expect(CaretStepper.step(unit: .word, increment: false, held: []).chord == ["option", "left"])
        #expect(CaretStepper.step(unit: .line, increment: true, held: [.shift]).chord == ["shift", "down"])
        #expect(CaretStepper.step(unit: .paragraph, increment: false, held: []).chord == ["option", "up"])
        #expect(CaretStepper.step(unit: .history, increment: false, held: []).chord == ["up"])
        #expect(CaretStepper.spokenValue(unit: .word, held: [.shift]) == "Selecting words")
    }

    @Test("Terminals offer history instead of lines and paragraphs")
    func terminalUnits() {
        #expect(CaretStepper.units(isTerminal: true) == [.character, .word, .history])
        #expect(CaretStepper.units(isTerminal: false) == [.character, .word, .line, .paragraph])
        #expect(CaretStepper.coerce(.paragraph, isTerminal: true) == .history)
        #expect(CaretStepper.coerce(.history, isTerminal: false) == .line)
        #expect(CaretStepper.coerce(.word, isTerminal: true) == .word)
    }
}
