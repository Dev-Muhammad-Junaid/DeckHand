//
//  PicturePointerGuardTests.swift
//  PixelHandCoreTests
//
//  Build 23 (VQ-095): with pointer control on the picture, a quick 210 pt
//  flick moved the Mac's pointer about 3,250 pt, off the mirrored display.
//

import Testing
@testable import PixelHandCore

@Suite("MacPointerAcceleration: the Mac's curve and its inverse")
struct MacPointerAccelerationTests {
    @Test("Matches the Mac's curve: 1:1 under 3 pt, then +0.12 gain per point")
    func curve() {
        #expect(MacPointerAcceleration.apply(2) == 2)
        #expect(MacPointerAcceleration.apply(-2.5) == -2.5)
        #expect(MacPointerAcceleration.apply(3) == 3)
        #expect(abs(MacPointerAcceleration.apply(13) - 13 * 2.2) < 1e-9)
        #expect(abs(MacPointerAcceleration.apply(-13) + 13 * 2.2) < 1e-9)
        #expect(MacPointerAcceleration.apply(.nan) == 0)
    }

    @Test("inverse undoes apply across the range, both signs")
    func roundTrip() {
        for delta in stride(from: -400.0, through: 400.0, by: 0.75) {
            let back = MacPointerAcceleration.inverse(MacPointerAcceleration.apply(delta))
            #expect(abs(back - delta) < 1e-6)
        }
        #expect(MacPointerAcceleration.inverse(.infinity) == 0)
    }
}

@Suite("PicturePointerGuard: a flick on the picture stays on the mirrored display")
struct PicturePointerGuardTests {
    /// A 1512 × 982 pt MacBook display, pointer in the middle.
    func centred() -> PicturePointerGuard {
        var guardrail = PicturePointerGuard(displayWidth: 1512, displayHeight: 982)
        guardrail.sync(x: 0.5, y: 0.5, isOnMirroredDisplay: true)
        return guardrail
    }

    /// Where the Mac puts the pointer after these deltas, from `start`.
    func macMoves(_ deltas: [(dx: Double, dy: Double)], from start: (x: Double, y: Double)) -> (x: Double, y: Double) {
        deltas.reduce(start) { point, delta in
            (point.x + MacPointerAcceleration.apply(delta.dx), point.y + MacPointerAcceleration.apply(delta.dy))
        }
    }

    @Test("Build 23's flick: ~210 pt of finger in 8 big messages stops at the display's edge")
    func flickStopsAtEdge() throws {
        var guardrail = centred()
        // 210 pt of finger at the Pointer surface's sensitivity (≈3.64,
        // from the 50 pt → 182 pt slow drag) in 8 coalesced messages.
        let flick = Array(repeating: (dx: 95.0, dy: -12.0), count: 8)
        let unguarded = macMoves(flick, from: (756, 491))
        #expect(unguarded.x > 1512 + 3000) // far off the display, as in build 23
        let sent = flick.map { guardrail.limit(dx: $0.dx, dy: $0.dy) }
        let landed = macMoves(sent, from: (756, 491))
        #expect(landed.x <= 1512 - PicturePointerGuard.edgeInset + 1e-6)
        #expect(landed.x >= 1512 - PicturePointerGuard.edgeInset - 1e-6) // reaches the edge
        #expect(landed.y >= 0 && landed.y < 982)
        let estimate = try #require(guardrail.estimate)
        #expect(abs(estimate.x - landed.x) < 1e-6 && abs(estimate.y - landed.y) < 1e-6)
    }

    @Test("Every flick direction and size lands on the display")
    func everyDirection() {
        for dx in stride(from: -300.0, through: 300.0, by: 37.5) {
            for dy in stride(from: -300.0, through: 300.0, by: 37.5) {
                var guardrail = centred()
                let sent = (0 ..< 6).map { _ in guardrail.limit(dx: dx, dy: dy) }
                let landed = macMoves(sent, from: (756, 491))
                #expect(landed.x >= -1e-6 && landed.x <= 1511 + 1e-6)
                #expect(landed.y >= -1e-6 && landed.y <= 981 + 1e-6)
            }
        }
    }

    @Test("A slow drag is untouched: same deltas, same feel as the Pointer surface")
    func slowDragUnchanged() {
        var guardrail = centred()
        for _ in 0 ..< 30 {
            let sent = guardrail.limit(dx: 6, dy: 1.5)
            #expect(sent.dx == 6 && sent.dy == 1.5)
        }
    }

    @Test("The gain is capped at 2× once the Mac accelerates")
    func gainCap() {
        for delta in stride(from: 0.5, through: 400, by: 0.5) {
            let sent = PicturePointerGuard.capGain(delta)
            let moved = MacPointerAcceleration.apply(sent)
            #expect(moved <= PicturePointerGuard.maximumGain * delta + 1e-6)
            #expect(moved >= delta - 1e-6) // never slower than 1:1
            #expect(PicturePointerGuard.capGain(-delta) == -sent)
        }
        // Under the knee (gain ≤ 2 up to 11⅓ pt) nothing changes.
        #expect(PicturePointerGuard.capGain(11) == 11)
    }

    @Test("Off the mirrored display, or with no size, only the gain cap applies")
    func capOnly() {
        var off = PicturePointerGuard(displayWidth: 1512, displayHeight: 982)
        off.sync(x: 1.4, y: 0.5, isOnMirroredDisplay: false)
        #expect(off.estimate == nil)
        let sent = off.limit(dx: 95, dy: 0)
        #expect(abs(MacPointerAcceleration.apply(sent.dx) - 190) < 1e-6)

        var unknown = PicturePointerGuard(displayWidth: 0, displayHeight: 0)
        unknown.sync(x: 0.5, y: 0.5, isOnMirroredDisplay: true)
        #expect(unknown.estimate == nil)
        #expect(abs(MacPointerAcceleration.apply(unknown.limit(dx: 95, dy: 0).dx) - 190) < 1e-6)
    }

    @Test("A new display size drops the estimate until the next cursor update")
    func resize() {
        var guardrail = centred()
        guardrail.resize(width: 1512, height: 982)
        #expect(guardrail.estimate != nil) // same size: kept
        guardrail.resize(width: 2560, height: 1440)
        #expect(guardrail.estimate == nil)
        guardrail.sync(x: 1, y: 1, isOnMirroredDisplay: true)
        #expect(guardrail.estimate?.x == 2559 && guardrail.estimate?.y == 1439)
        guardrail.resize(width: .nan, height: 900)
        #expect(guardrail.displayWidth == 0)
    }

    @Test("A cursor update that lags the deltas in flight is ignored until the pointer rests")
    func lateCursorUpdate() {
        var guardrail = centred()
        _ = guardrail.limit(dx: 95, dy: 0, now: 10.00)
        let afterFirst = guardrail.estimate
        // The Mac's update from before that delta arrives 40 ms later.
        guardrail.sync(x: 0.5, y: 0.5, isOnMirroredDisplay: true, now: 10.04)
        #expect(guardrail.estimate?.x == afterFirst?.x)
        // Rested: the Mac's word wins again.
        guardrail.sync(x: 0.25, y: 0.5, isOnMirroredDisplay: true, now: 10.40)
        #expect(guardrail.estimate?.x == 378)
    }

    @Test("Bad input never becomes a move")
    func badInput() {
        var guardrail = centred()
        let sent = guardrail.limit(dx: .nan, dy: .infinity)
        #expect(sent.dx == 0 && sent.dy == 0)
    }
}
