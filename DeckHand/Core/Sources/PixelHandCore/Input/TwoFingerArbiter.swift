//
//  TwoFingerArbiter.swift
//  PixelHandCore – Input
//
//  OR-16: when the mirror picture works as a trackpad, two fingers can mean
//  three things, and the picture must tell them apart before acting:
//
//  - **Scroll** (goes to the Mac): both fingers travel together, the gap
//    between them nearly constant.
//  - **Pinch** (zooms the picture, stays on this device): the gap between
//    the fingers opens or closes while their midpoint stays roughly put.
//    Once a touch is a pinch, moving the midpoint **pans** the zoomed
//    picture, so pan is "pinch, then slide", never a separate two-finger
//    gesture that could be mistaken for a scroll.
//  - **Tap** (a right click on the Mac): both fingers lift quickly without
//    travelling or changing their gap.
//
//  Nothing is sent while the touch is undecided (a few points of travel),
//  and once decided it stays decided until the fingers lift: a scroll never
//  turns into a zoom halfway, and the reverse. The scroll travel buffered
//  while undecided is delivered with the first scroll step, so no movement
//  is lost. Pure value type, tested in `TwoFingerArbiterTests`.
//
//  Distances are points on the touch surface; times are seconds on any
//  monotonic clock.
//

import Foundation

/// Thresholds for `TwoFingerArbiter`.
public enum TwoFingerPolicy {
    /// Midpoint travel (points) after which fingers that kept their gap
    /// are a scroll.
    public static let scrollTravel: Double = 10
    /// Change in the gap between the fingers (points) after which, if it
    /// outweighs the travel, the touch is a pinch.
    public static let pinchSpan: Double = 20
    /// A pinch needs its gap change above this share of the midpoint's
    /// travel; a scroll needs it at or below. One cut-off, so no movement
    /// can satisfy both.
    public static let spanToTravel: Double = 0.5
    /// The longest two-finger touch that still counts as a tap.
    public static let tapMaxDuration: TimeInterval = DragPolicy.tapMaxDuration
    /// Travel and gap change a tap may have and still be a tap.
    public static let tapSlop: Double = 8
}

public struct TwoFingerArbiter: Equatable, Sendable {
    /// What the touch has been decided to be.
    public enum Decision: Equatable, Sendable {
        case undecided
        case scroll
        case pinch
    }

    /// What to do after a move.
    public enum Step: Equatable, Sendable {
        /// Nothing yet (undecided, or no change).
        case none
        /// Scroll the Mac by this much (points of midpoint travel).
        case scroll(dx: Double, dy: Double)
        /// Zoom the picture by `scale` (relative to the last step) around
        /// `anchor` (where the fingers' midpoint was), then pan it by `dx`,
        /// `dy` (how far the midpoint moved): the content under the fingers
        /// stays under them.
        case zoom(scale: Double, anchor: TouchPoint, dx: Double, dy: Double)
    }

    /// What the touch was, once its fingers lift.
    public enum Ending: Equatable, Sendable {
        /// Undecided and too slow or too far to be a tap: nothing.
        case nothing
        /// A quick two-finger tap: right-click.
        case tap
        /// A scroll ended: send the scroll's end phase.
        case scrollEnded
        /// A pinch ended: settle the picture's zoom.
        case pinchEnded
    }

    public private(set) var decision: Decision = .undecided
    /// Whether a pinch may be chosen at all. Off, every two-finger move is
    /// a scroll (the plain trackpad).
    public var allowsPinch: Bool

    private var isActive = false
    private var startedAt: TimeInterval = 0
    private var startMid = TouchPoint(x: 0, y: 0)
    private var startSpan: Double = 0
    private var lastMid = TouchPoint(x: 0, y: 0)
    private var lastSpan: Double = 0
    /// Furthest the midpoint and the gap strayed: a tap must stay inside.
    private var maxTravel: Double = 0
    private var maxSpanChange: Double = 0

    public init(allowsPinch: Bool = true) {
        self.allowsPinch = allowsPinch
    }

    /// Whether a two-finger touch is in progress.
    public var isTracking: Bool { isActive }

    /// The second finger landed (or the touch has exactly two again).
    public mutating func begin(_ a: TouchPoint, _ b: TouchPoint, at now: TimeInterval) {
        isActive = true
        decision = .undecided
        startedAt = now
        startMid = Self.midpoint(a, b)
        startSpan = Self.distance(a, b)
        lastMid = startMid
        lastSpan = startSpan
        maxTravel = 0
        maxSpanChange = 0
    }

    /// The two fingers moved.
    public mutating func move(_ a: TouchPoint, _ b: TouchPoint) -> Step {
        guard isActive else { return .none }
        let mid = Self.midpoint(a, b)
        let span = Self.distance(a, b)
        let travel = Self.distance(mid, startMid)
        let spanChange = abs(span - startSpan)
        maxTravel = max(maxTravel, travel)
        maxSpanChange = max(maxSpanChange, spanChange)

        if decision == .undecided {
            decision = Self.decide(travel: travel, spanChange: spanChange, allowsPinch: allowsPinch)
            switch decision {
            case .undecided:
                return .none
            case .scroll:
                // Deliver everything since the fingers landed.
                lastMid = mid
                lastSpan = span
                return .scroll(dx: mid.x - startMid.x, dy: mid.y - startMid.y)
            case .pinch:
                let step = Step.zoom(
                    scale: startSpan > 0 ? span / startSpan : 1,
                    anchor: startMid,
                    dx: mid.x - startMid.x,
                    dy: mid.y - startMid.y
                )
                lastMid = mid
                lastSpan = span
                return step
            }
        }

        let dx = mid.x - lastMid.x
        let dy = mid.y - lastMid.y
        let scale = lastSpan > 0 ? span / lastSpan : 1
        let anchor = lastMid
        lastMid = mid
        lastSpan = span
        switch decision {
        case .scroll:
            return dx == 0 && dy == 0 ? .none : .scroll(dx: dx, dy: dy)
        case .pinch:
            return dx == 0 && dy == 0 && scale == 1 ? .none : .zoom(scale: scale, anchor: anchor, dx: dx, dy: dy)
        case .undecided:
            return .none
        }
    }

    /// A finger lifted, leaving fewer than two: the two-finger touch is over.
    public mutating func end(at now: TimeInterval) -> Ending {
        guard isActive else { return .nothing }
        isActive = false
        let decided = decision
        decision = .undecided
        switch decided {
        case .scroll:
            return .scrollEnded
        case .pinch:
            return .pinchEnded
        case .undecided:
            let quick = now - startedAt <= TwoFingerPolicy.tapMaxDuration
            let still = maxTravel <= TwoFingerPolicy.tapSlop && maxSpanChange <= TwoFingerPolicy.tapSlop
            return quick && still ? .tap : .nothing
        }
    }

    /// The touch was taken (a third finger, a system gesture, a cancel):
    /// forget it without a tap. Returns what must be closed.
    public mutating func cancel() -> Ending {
        guard isActive else { return .nothing }
        isActive = false
        let decided = decision
        decision = .undecided
        switch decided {
        case .scroll: return .scrollEnded
        case .pinch: return .pinchEnded
        case .undecided: return .nothing
        }
    }

    // MARK: Rules

    /// The arbitration rule on its own: pinch when the gap changed by at
    /// least `pinchSpan` and more than `spanToTravel` × travel; scroll once
    /// the midpoint travelled `scrollTravel` with the gap within that share;
    /// else undecided. The undecided band is bounded: past
    /// `pinchSpan / spanToTravel` of travel, one of the two always holds.
    public static func decide(travel: Double, spanChange: Double, allowsPinch: Bool) -> Decision {
        let pinchLike = spanChange > travel * TwoFingerPolicy.spanToTravel
        if allowsPinch, pinchLike, spanChange >= TwoFingerPolicy.pinchSpan {
            return .pinch
        }
        if !allowsPinch, travel >= TwoFingerPolicy.scrollTravel {
            return .scroll
        }
        if travel >= TwoFingerPolicy.scrollTravel, !pinchLike {
            return .scroll
        }
        return .undecided
    }

    static func midpoint(_ a: TouchPoint, _ b: TouchPoint) -> TouchPoint {
        TouchPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    static func distance(_ a: TouchPoint, _ b: TouchPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
