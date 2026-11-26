//
//  ControlBadgePlacement.swift
//  PixelHandCore – Design
//
//  Where a badge sits on a control (owner testing, build 27, OT-14). A
//  badge (the unseen dot, the Pro lock, the PRO label, a count, a live
//  dot) is drawn in an overlay above the control's glass, never inside its
//  clip shape: on iOS 26 the header's glass group drew the Send button's
//  dot under the glass circle, cut off, and the free plan's Pro lock the
//  same way. This file only says *where*: the badge's frame in the
//  control's own coordinates, on the 4 pt grid.
//
//  Two anchors:
//  - `rim`: the badge's centre sits on the control's outline at 45° from
//    the corner (a circle's rim, a capsule's end, a rounded rectangle's
//    corner arc), so it straddles the edge, half on the glass and half
//    outside it. Header circles and glass pills.
//  - `inset(d)`: the badge sits inside the corner, `d` from both edges.
//    Tiles inside cards, where a badge hanging out would cover the name.
//
//  The frame's origin is rounded to the 4 pt grid (`07-Polish-Spec.md` §1)
//  and every badge kind has a size on the grid, so the badge's edges land
//  on it too.
//

import Foundation

/// What a control's badge shows.
public enum ControlBadgeKind: Equatable, Hashable, Sendable {
    /// The app's one dot (a rounded square): unseen items, a new state.
    case dot
    /// The live light (mint, breathing): a Mac that's talking.
    case live
    /// The amber "needs you" pixel: a dialog waiting on the Mac.
    case needsYou
    /// The unlit light: a Mac that's offline.
    case offLight
    /// The small lock tile on a locked Pro control.
    case proLock
    /// The same lock on a small tile (the Macs sidebar's 44 × 28).
    case proLockSmall
    /// The PRO label (dot-matrix on the tile gradient).
    case proLabel
    /// A dot-matrix count (1…99, "99+" past that).
    case count(Int)

    /// The badge's size on the 4 pt grid.
    public var size: ControlBadgePlacement.Size {
        switch self {
        case .dot: return .init(width: 8, height: 8)
        // An 8 pt light in a 2 pt ring of the canvas colour.
        case .live, .needsYou, .offLight: return .init(width: 12, height: 12)
        case .proLock: return .init(width: 20, height: 20)
        case .proLockSmall: return .init(width: 16, height: 16)
        case .proLabel: return .init(width: 40, height: 20)
        case let .count(value): return .init(width: Self.countText(value).count > 1 ? 28 : 20, height: 20)
        }
    }

    /// The count's text: the number up to 99, then "99+".
    public static func countText(_ value: Int) -> String {
        value > 99 ? "99+" : "\(max(0, value))"
    }
}

public enum ControlBadgePlacement {
    /// The grid every badge sits on.
    public static let grid = 4.0

    public struct Size: Equatable, Hashable, Sendable {
        public var width: Double
        public var height: Double
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public struct Frame: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        public func contains(x px: Double, y py: Double) -> Bool {
            px >= x && px <= maxX && py >= y && py <= maxY
        }
    }

    /// The control's outline.
    public enum Shape: Equatable, Hashable, Sendable {
        case circle
        case capsule
        case roundedRect(radius: Double)
        case rect
    }

    public enum Corner: Equatable, Hashable, Sendable, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var isTrailing: Bool { self == .topTrailing || self == .bottomTrailing }
        var isTop: Bool { self == .topLeading || self == .topTrailing }
    }

    public enum Anchor: Equatable, Hashable, Sendable {
        /// Centred on the outline at 45° from the corner: half over the
        /// glass, half outside it.
        case rim
        /// Inside the corner, this far from both edges.
        case inset(Double)
    }

    /// The point on the outline at 45° from `corner`, in the control's
    /// coordinates (origin top-leading).
    public static func rimPoint(control: Size, shape: Shape, corner: Corner) -> (x: Double, y: Double) {
        let w = max(0, control.width)
        let h = max(0, control.height)
        let radius: Double
        switch shape {
        case .circle, .capsule: radius = min(w, h) / 2
        case let .roundedRect(r): radius = min(max(0, r), min(w, h) / 2)
        case .rect: radius = 0
        }
        // A circle in a non-square frame is centred in it.
        let left: Double
        let top: Double
        let right: Double
        let bottom: Double
        if shape == .circle {
            let d = min(w, h)
            left = (w - d) / 2
            top = (h - d) / 2
            right = left + d
            bottom = top + d
        } else {
            left = 0
            top = 0
            right = w
            bottom = h
        }
        let cx = corner.isTrailing ? right - radius : left + radius
        let cy = corner.isTop ? top + radius : bottom - radius
        let step = radius / 2.squareRoot()
        return (corner.isTrailing ? cx + step : cx - step, corner.isTop ? cy - step : cy + step)
    }

    /// The badge's frame in the control's coordinates, origin on the grid.
    public static func frame(
        _ kind: ControlBadgeKind,
        control: Size,
        shape: Shape,
        corner: Corner = .topTrailing,
        anchor: Anchor = .rim
    ) -> Frame {
        frame(badge: kind.size, control: control, shape: shape, corner: corner, anchor: anchor)
    }

    public static func frame(
        badge: Size,
        control: Size,
        shape: Shape,
        corner: Corner = .topTrailing,
        anchor: Anchor = .rim
    ) -> Frame {
        let x: Double
        let y: Double
        switch anchor {
        case .rim:
            let point = rimPoint(control: control, shape: shape, corner: corner)
            x = point.x - badge.width / 2
            y = point.y - badge.height / 2
        case let .inset(distance):
            x = corner.isTrailing ? control.width - distance - badge.width : distance
            y = corner.isTop ? distance : control.height - distance - badge.height
        }
        return Frame(x: onGrid(x), y: onGrid(y), width: badge.width, height: badge.height)
    }

    /// Rounds to the nearest grid step.
    public static func onGrid(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value / grid).rounded() * grid
    }
}
