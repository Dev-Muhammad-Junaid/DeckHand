//
//  PicturePointerGuard.swift
//  PixelHandCore
//
//  Build 23 (VQ-095): with pointer control on the mirror picture, a quick
//  210 pt flick threw the Mac's pointer about 3,250 pt, off the mirrored
//  display and onto another screen the picture can't show. The Mac's curve
//  (`MacPointerAcceleration`) grows with each message's size, so a flick's
//  big coalesced deltas multiplied many times over.
//
//  While the picture drives the pointer, each delta that leaves the remote:
//  1. is capped at `maximumGain` × its size once the Mac accelerates it
//     (a slow drag, under the curve's knee, is untouched);
//  2. is shortened so the pointer stops at the mirrored display's edge,
//     predicted from the Mac's cursor stream plus what was sent since.
//
//  `mouseDelta` names no display, so the clamp runs here, where the
//  mirrored display and the pointer's position are known; the protocol is
//  unchanged. When the pointer isn't on the mirrored display (or the remote
//  doesn't know where it is) only the gain cap applies.
//

import Foundation

public struct PicturePointerGuard: Equatable, Sendable {
    /// The most the Mac may multiply a picture delta by.
    public static let maximumGain = 2.0
    /// How far inside the display's right and bottom edges the pointer
    /// stops (those edges belong to the next display, as in CoreGraphics).
    public static let edgeInset = 1.0

    /// The mirrored display's size in points.
    public private(set) var displayWidth: Double
    public private(set) var displayHeight: Double
    /// Where the pointer is predicted to be, in the display's points;
    /// nil when it is elsewhere or unknown.
    public private(set) var estimate: (x: Double, y: Double)? {
        get { estimateX.flatMap { x in estimateY.map { (x, $0) } } }
        set { estimateX = newValue?.x; estimateY = newValue?.y }
    }
    private var estimateX: Double?
    private var estimateY: Double?
    /// When the last delta went out (seconds, any monotonic clock).
    private var lastSentAt: Double?
    /// The cursor stream lags the deltas in flight, so while deltas are
    /// going out the estimate follows the Mac's maths alone; a cursor
    /// update is taken once the pointer has rested this long.
    public static let syncQuietPeriod = 0.15

    public init(displayWidth: Double, displayHeight: Double) {
        self.displayWidth = max(0, displayWidth.isFinite ? displayWidth : 0)
        self.displayHeight = max(0, displayHeight.isFinite ? displayHeight : 0)
    }

    /// A new display size (another display picked, or it changed). The
    /// estimate waits for the next cursor update. A size of 0 (a window,
    /// or not known yet) keeps only the gain cap.
    public mutating func resize(width: Double, height: Double) {
        let width = max(0, width.isFinite ? width : 0)
        let height = max(0, height.isFinite ? height : 0)
        guard width != displayWidth || height != displayHeight else { return }
        displayWidth = width
        displayHeight = height
        estimate = nil
    }

    /// The Mac's cursor stream: `x`, `y` are 0…1 across the mirrored
    /// display (`MirrorCursorState`). Off that display, the estimate is
    /// dropped and only the gain cap applies. With `now`, an update that
    /// arrives while deltas are still going out (within `syncQuietPeriod`
    /// of the last) is ignored when there is an estimate: it shows where
    /// the pointer was, before the deltas in flight.
    public mutating func sync(x: Double, y: Double, isOnMirroredDisplay: Bool, now: Double? = nil) {
        if let now, let lastSentAt, estimate != nil, now - lastSentAt < Self.syncQuietPeriod { return }
        guard isOnMirroredDisplay, x.isFinite, y.isFinite, displayWidth > 0, displayHeight > 0 else {
            estimate = nil
            return
        }
        estimate = (
            Self.clamp(x * displayWidth, upper: displayWidth),
            Self.clamp(y * displayHeight, upper: displayHeight)
        )
    }

    /// The delta to send instead of (`dx`, `dy`), at `now` (see `sync`).
    public mutating func limit(dx: Double, dy: Double, now: Double? = nil) -> (dx: Double, dy: Double) {
        if let now { lastSentAt = now }
        var outX = Self.capGain(dx)
        var outY = Self.capGain(dy)
        if let current = estimate {
            let x = limitAxis(outX, at: current.x, extent: displayWidth)
            let y = limitAxis(outY, at: current.y, extent: displayHeight)
            outX = x.delta
            outY = y.delta
            estimate = (x.landing, y.landing)
        }
        return (outX, outY)
    }

    // MARK: - Internals

    /// The delta whose accelerated move is at most `maximumGain` × it.
    static func capGain(_ delta: Double) -> Double {
        guard delta.isFinite else { return 0 }
        let moved = MacPointerAcceleration.apply(delta)
        let capped = maximumGain * delta
        guard abs(moved) > abs(capped) else { return delta }
        return MacPointerAcceleration.inverse(capped)
    }

    private func limitAxis(_ delta: Double, at position: Double, extent: Double) -> (delta: Double, landing: Double) {
        let moved = MacPointerAcceleration.apply(delta)
        let landing = Self.clamp(position + moved, upper: extent)
        let allowed = landing - position
        guard abs(allowed - moved) > 1e-9 else { return (delta, landing) }
        let sent = MacPointerAcceleration.inverse(allowed)
        return (sent, position + MacPointerAcceleration.apply(sent))
    }

    private static func clamp(_ value: Double, upper extent: Double) -> Double {
        min(max(value, 0), max(0, extent - edgeInset))
    }

    public static func == (lhs: PicturePointerGuard, rhs: PicturePointerGuard) -> Bool {
        lhs.displayWidth == rhs.displayWidth && lhs.displayHeight == rhs.displayHeight
            && lhs.estimateX == rhs.estimateX && lhs.estimateY == rhs.estimateY
            && lhs.lastSentAt == rhs.lastSentAt
    }
}
