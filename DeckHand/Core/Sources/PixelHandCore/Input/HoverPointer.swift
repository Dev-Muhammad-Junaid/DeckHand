//
//  HoverPointer.swift
//  PixelHandCore
//
//  S12: Apple Pencil hover moves the Mac's pointer. On an iPad that senses
//  a hovering Pencil (`UIHoverGestureRecognizer`), the tip's movement above
//  the trackpad moves the pointer like a finger would, without touching
//  the glass, so the person can aim and then tap with the Pencil to click.
//
//  `HoverPointerTracker` turns hover positions into pointer deltas: the
//  first position after the Pencil arrives only sets the origin (no jump),
//  a sudden leap (the Pencil left and came back elsewhere between two
//  samples) is treated the same way, and the deltas are scaled like the
//  finger's.
//

import Foundation

public enum HoverPointerPolicy {
    /// A move longer than this between two hover samples (points) is a
    /// re-entry, not motion.
    public static let maxStep: Double = 120
    /// Pencil movement is more precise than a finger's, so it moves the
    /// pointer at this fraction of the trackpad sensitivity.
    public static let sensitivityScale: Double = 1
}

public struct HoverPointerTracker: Equatable, Sendable {
    private var last: TouchPoint?

    public init() {}

    /// Whether the Pencil is hovering (an origin is set).
    public var isHovering: Bool { last != nil }

    /// A new hover position. Returns the pointer delta to send, or `nil`
    /// when there is nothing to move (first sample, a leap, or no change).
    public mutating func moved(to point: TouchPoint, sensitivity: Double) -> (dx: Double, dy: Double)? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        defer { last = point }
        guard let last else { return nil }
        let dx = point.x - last.x
        let dy = point.y - last.y
        guard (dx * dx + dy * dy).squareRoot() <= HoverPointerPolicy.maxStep else { return nil }
        guard dx != 0 || dy != 0 else { return nil }
        let scale = sensitivity * HoverPointerPolicy.sensitivityScale
        return (dx * scale, dy * scale)
    }

    /// The Pencil left hover range (or touched down): the next sample sets
    /// a new origin.
    public mutating func ended() {
        last = nil
    }
}
