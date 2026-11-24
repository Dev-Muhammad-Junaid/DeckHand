//
//  PixelTransitionPlan.swift
//  PixelHandCore – Design
//
//  The pixel transitions as data (`06-Pixel-Identity.md` §7, UX-017): how
//  long each runs, its curve, what it becomes under Reduce Motion, and the
//  dissolve's cell maths. The app's `PixelHandMotion` and the Metal
//  `pixelDissolve` shader read the same numbers, so tests here pin the
//  timings and the Reduce Motion fallbacks.
//

import Foundation

/// The three pixel transitions.
public enum PixelTransition: String, CaseIterable, Sendable {
    /// Switching surface, switching Mac, paywall → unlocked surface.
    case dissolve
    /// Mirror connects, display or desktop changes, capture taken.
    case scanline
    /// Launch, pairing success, connecting → connected, Pro unlocked.
    case powerOn
}

/// How a transition moves: its effect, duration and curve.
public struct PixelTransitionTiming: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        /// The transition's own pixel effect.
        case pixel
        /// A plain cross-fade.
        case fade
        /// No animation: the final state at once.
        case instant
    }

    public enum Curve: Equatable, Sendable {
        case linear, easeOut, easeInOut
    }

    public let effect: Effect
    public let duration: Double
    public let curve: Curve

    public init(effect: Effect, duration: Double, curve: Curve) {
        self.effect = effect
        self.duration = duration
        self.curve = curve
    }
}

public enum PixelTransitionPlan {
    /// Pixel dissolve: 280 ms, linear threshold.
    public static let dissolveDuration = 0.28
    /// Scanline sweep: 360 ms ease-out.
    public static let scanlineDuration = 0.36
    /// Power-on: 600 ms.
    public static let powerOnDuration = 0.6
    /// What movement becomes under Reduce Motion.
    public static let reducedFadeDuration = 0.16

    /// Dissolve cell: 8 pt, 6 pt on compact widths.
    public static let dissolveCell = 8.0
    public static let dissolveCellCompact = 6.0
    /// Cells within this much of the threshold edge draw as phosphor dots.
    public static let dissolveEdgeBand = 0.12

    /// Power-on brightness keyframes: 0 → 115 % at 210 ms → 100 % by 600 ms.
    public static let powerOnBrightness: [Double] = [0, 1.15, 1.0]
    public static let powerOnPeakTime = 0.21
    /// Per-dot start jitter of the power-on, 0–180 ms.
    public static let powerOnMaxJitter = 0.18

    /// The timing of `transition`, with Reduce Motion applied: the dissolve
    /// and the scanline become a 160 ms cross-fade, the power-on is instant.
    public static func timing(_ transition: PixelTransition, reduceMotion: Bool) -> PixelTransitionTiming {
        switch (transition, reduceMotion) {
        case (.dissolve, false):
            PixelTransitionTiming(effect: .pixel, duration: dissolveDuration, curve: .linear)
        case (.scanline, false):
            PixelTransitionTiming(effect: .pixel, duration: scanlineDuration, curve: .easeOut)
        case (.powerOn, false):
            PixelTransitionTiming(effect: .pixel, duration: powerOnDuration, curve: .easeOut)
        case (.dissolve, true), (.scanline, true):
            PixelTransitionTiming(effect: .fade, duration: reducedFadeDuration, curve: .easeInOut)
        case (.powerOn, true):
            PixelTransitionTiming(effect: .instant, duration: 0, curve: .linear)
        }
    }

    /// The dissolve cell for a width class.
    public static func dissolveCell(isCompact: Bool) -> Double {
        isCompact ? dissolveCellCompact : dissolveCell
    }

    /// A stable pseudo-random threshold in 0..<1 for a cell. The Metal
    /// shader (`PixelTransitions.metal`) uses the same hash.
    public static func rank(column: Int, row: Int, seed: UInt32 = 0) -> Double {
        var h = UInt32(truncatingIfNeeded: column) &* 73_856_093
        h ^= UInt32(truncatingIfNeeded: row) &* 19_349_663
        h ^= seed &* 83_492_791
        h ^= h >> 13
        h = h &* 0x5bd1_e995
        h ^= h >> 15
        return Double(h % 10_000) / 10_000
    }

    /// What a cell shows during a dissolve.
    public enum CellState: Equatable, Sendable {
        case hidden, shown, edge
    }

    /// The incoming view shows a cell once `progress` passes its rank; the
    /// newest band (within `dissolveEdgeBand`) draws as a phosphor dot. The
    /// outgoing view shows exactly the cells the incoming one doesn't, so
    /// the two never overlap or leave holes.
    public static func cellState(rank: Double, progress: Double, isOutgoing: Bool) -> CellState {
        let p = min(max(progress, 0), 1)
        if isOutgoing { return rank >= p ? .shown : .hidden }
        guard rank < p else { return .hidden }
        // A finished dissolve has no edge left.
        return p < 1 && rank >= p - dissolveEdgeBand ? .edge : .shown
    }

    /// Power-on start delay for dot `index`: 0–180 ms, seeded.
    public static func powerOnDelay(index: Int, seed: UInt32 = 0) -> Double {
        rank(column: index, row: 7, seed: seed) * powerOnMaxJitter
    }
}
