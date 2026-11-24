//
//  PixelTransitionPlanTests.swift
//  PixelHandCoreTests
//
//  The pixel transitions' timings, Reduce Motion fallbacks and dissolve
//  maths (`06-Pixel-Identity.md` §7, UX-017).
//

import Testing
@testable import PixelHandCore

@Suite("Pixel transitions")
struct PixelTransitionPlanTests {
    @Test("Each transition runs at its spec timing")
    func specTimings() {
        #expect(PixelTransitionPlan.timing(.dissolve, reduceMotion: false)
            == PixelTransitionTiming(effect: .pixel, duration: 0.28, curve: .linear))
        #expect(PixelTransitionPlan.timing(.scanline, reduceMotion: false)
            == PixelTransitionTiming(effect: .pixel, duration: 0.36, curve: .easeOut))
        #expect(PixelTransitionPlan.timing(.powerOn, reduceMotion: false).duration == 0.6)
    }

    @Test("Reduce Motion: dissolve and scanline cross-fade in 160 ms, power-on is instant")
    func reduceMotionFallbacks() {
        for transition in [PixelTransition.dissolve, .scanline] {
            let timing = PixelTransitionPlan.timing(transition, reduceMotion: true)
            #expect(timing.effect == .fade)
            #expect(timing.duration == 0.16)
        }
        let powerOn = PixelTransitionPlan.timing(.powerOn, reduceMotion: true)
        #expect(powerOn.effect == .instant)
        #expect(powerOn.duration == 0)
        for transition in PixelTransition.allCases {
            #expect(PixelTransitionPlan.timing(transition, reduceMotion: true).effect != .pixel)
        }
    }

    @Test("Cells are 8 pt, 6 pt on compact widths")
    func cellSize() {
        #expect(PixelTransitionPlan.dissolveCell(isCompact: false) == 8)
        #expect(PixelTransitionPlan.dissolveCell(isCompact: true) == 6)
    }

    @Test("Ranks are stable, in 0..<1 and spread out")
    func ranks() {
        var buckets = Array(repeating: 0, count: 10)
        for x in 0..<64 {
            for y in 0..<64 {
                let r = PixelTransitionPlan.rank(column: x, row: y)
                #expect(r >= 0 && r < 1)
                #expect(r == PixelTransitionPlan.rank(column: x, row: y))
                buckets[Int(r * 10)] += 1
            }
        }
        // 4096 cells over 10 buckets: each within ±40 % of 410.
        for count in buckets { #expect(count > 246 && count < 574) }
        #expect(PixelTransitionPlan.rank(column: 3, row: 4, seed: 1) != PixelTransitionPlan.rank(column: 3, row: 4, seed: 2))
    }

    @Test("Incoming and outgoing cells never overlap or leave a hole")
    func cellsPartition() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
            for rank in stride(from: 0.0, to: 1.0, by: 0.01) {
                let incoming = PixelTransitionPlan.cellState(rank: rank, progress: progress, isOutgoing: false)
                let outgoing = PixelTransitionPlan.cellState(rank: rank, progress: progress, isOutgoing: true)
                #expect((incoming == .hidden) == (outgoing == .shown))
            }
        }
    }

    @Test("The edge band trails the threshold and is gone when the dissolve ends")
    func edgeBand() {
        #expect(PixelTransitionPlan.cellState(rank: 0.45, progress: 0.5, isOutgoing: false) == .edge)
        #expect(PixelTransitionPlan.cellState(rank: 0.2, progress: 0.5, isOutgoing: false) == .shown)
        #expect(PixelTransitionPlan.cellState(rank: 0.6, progress: 0.5, isOutgoing: false) == .hidden)
        #expect(PixelTransitionPlan.cellState(rank: 0.95, progress: 1, isOutgoing: false) == .shown)
        #expect(PixelTransitionPlan.cellState(rank: 0, progress: 0, isOutgoing: true) == .shown)
    }

    @Test("Power-on peaks at 115 % and dot jitter stays within 180 ms")
    func powerOn() {
        #expect(PixelTransitionPlan.powerOnBrightness == [0, 1.15, 1.0])
        #expect(PixelTransitionPlan.powerOnPeakTime < PixelTransitionPlan.powerOnDuration)
        for index in 0..<200 {
            let delay = PixelTransitionPlan.powerOnDelay(index: index)
            #expect(delay >= 0 && delay <= 0.18)
        }
    }
}
