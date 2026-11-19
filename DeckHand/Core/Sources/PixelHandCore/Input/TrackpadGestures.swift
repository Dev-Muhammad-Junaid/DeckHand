//
//  TrackpadGestures.swift
//  PixelHandCore
//
//  S11: three- and four-finger swipes and pinches on the remote's trackpad,
//  and the Mac actions they stand for. Re-implemented from Sill's
//  documented behaviour (no code copied):
//
//  - Three fingers are the target; four do the same where the system lets
//    them through (iPadOS keeps four-finger gestures for itself unless the
//    person turns them off).
//  - A stroke is **decided at lift** from the fingers' net travel, so a
//    swipe taken back before lifting does nothing, and a stroke the system
//    cancels sends nothing. One action per stroke, and no pointer motion,
//    click or scroll during it.
//  - **Natural direction**, as on a Mac: fingers moving left bring the
//    Space on the right (the next one).
//  - **The opposite gesture closes what this remote opened** (toggle-back):
//    a swipe down after its Mission Control closes it, a swipe up after its
//    App Exposé, a spread after its Apps (Launchpad), a pinch after its
//    Show Desktop. Each of these Mac views toggles with its own shortcut,
//    so closing runs the same action again. The same gesture again does
//    nothing (the view is open); once more straight after, it runs again
//    (the view was closed on the Mac itself). Spaces leave an open view as
//    it is. A click, a key, typed text or a drag forgets what was open.
//
//  The commands go out as the Mac system control lane's existing actions,
//  `system.run(action:)` and `system.switchSpace`, which press the Mac's own
//  shortcuts for these views (S7).
//

import Foundation

/// A point on the remote's trackpad, in points. (Core has no CoreGraphics.)
public struct TouchPoint: Equatable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A multi-finger stroke, decided at lift.
public enum MultiFingerGesture: Equatable, Sendable, Hashable {
    /// The fingers' direction of travel (screen directions: up is up).
    public enum Direction: String, Equatable, Sendable, Hashable, CaseIterable {
        case up, down, left, right
    }

    case swipe(Direction)
    /// The fingers came together (thumb and fingers on a Mac).
    case pinch
    /// The fingers spread apart.
    case spread
}

/// What a gesture asks the Mac to do.
public enum GestureCommand: Equatable, Sendable {
    case system(SystemMacro)
    case switchSpace(SpaceDirection)

    /// The message the remote sends.
    public var message: ControlMessage {
        switch self {
        case let .system(action): .system(.run(action: action))
        case let .switchSpace(direction): .system(.switchSpace(direction: direction, displayID: nil))
        }
    }
}

public enum GestureClassifier {
    /// Fewest fingers for a system gesture.
    public static let minimumFingers = 3
    /// Net travel of the fingers' centre (points) that makes a swipe.
    public static let swipeThreshold: Double = 60
    /// Change in the fingers' mean distance from their centre (points) that
    /// makes a pinch or a spread.
    public static let pinchThreshold: Double = 40

    /// The gesture a stroke made, from where its fingers were when it
    /// armed (`start`) and when the first of them lifted (`end`), finger
    /// for finger. `nil` when it made none: too few fingers, not far
    /// enough, or taken back.
    ///
    /// A pinch wins over a swipe when the spread changed by more than the
    /// centre travelled, because fingers closing on one side also move
    /// their centre.
    public static func classify(start: [TouchPoint], end: [TouchPoint]) -> MultiFingerGesture? {
        guard start.count == end.count, start.count >= minimumFingers else { return nil }
        let c0 = centroid(start)
        let c1 = centroid(end)
        let dx = c1.x - c0.x
        let dy = c1.y - c0.y
        let travel = (dx * dx + dy * dy).squareRoot()
        let spreadChange = meanRadius(end, around: c1) - meanRadius(start, around: c0)

        if abs(spreadChange) >= pinchThreshold, abs(spreadChange) > travel {
            return spreadChange < 0 ? .pinch : .spread
        }
        guard travel >= swipeThreshold else { return nil }
        if abs(dx) > abs(dy) {
            return .swipe(dx > 0 ? .right : .left)
        }
        // Screen coordinates: y grows downwards.
        return .swipe(dy > 0 ? .down : .up)
    }

    public static func centroid(_ points: [TouchPoint]) -> TouchPoint {
        guard !points.isEmpty else { return TouchPoint(x: 0, y: 0) }
        let n = Double(points.count)
        return TouchPoint(
            x: points.reduce(0) { $0 + $1.x } / n,
            y: points.reduce(0) { $0 + $1.y } / n
        )
    }

    static func meanRadius(_ points: [TouchPoint], around c: TouchPoint) -> Double {
        guard !points.isEmpty else { return 0 }
        let total = points.reduce(0.0) { sum, p in
            let dx = p.x - c.x
            let dy = p.y - c.y
            return sum + (dx * dx + dy * dy).squareRoot()
        }
        return total / Double(points.count)
    }
}

/// The gesture → action map with toggle-back. One per connection on the
/// remote.
public struct GestureMap: Equatable, Sendable {
    /// A Mac view a gesture opens and the opposite gesture closes.
    public enum MacView: Equatable, Sendable {
        case missionControl, appExpose, apps, desktop

        var action: SystemMacro {
            switch self {
            case .missionControl: .missionControl
            case .appExpose: .appExpose
            case .apps: .launchpad
            case .desktop: .showDesktop
            }
        }
    }

    /// The view this remote last opened, if it is still open as far as the
    /// remote knows.
    public private(set) var openView: MacView?
    /// The same opening gesture was just ignored once.
    private var repeatIgnored = false

    public init() {}

    /// The fixed map, without toggle-back: the view each gesture opens.
    public static func command(for gesture: MultiFingerGesture) -> GestureCommand {
        switch gesture {
        // Natural direction: fingers left bring the Space on the right.
        case .swipe(.left): .switchSpace(.next)
        case .swipe(.right): .switchSpace(.previous)
        case .swipe(.up): .system(.missionControl)
        case .swipe(.down): .system(.appExpose)
        case .pinch: .system(.launchpad)
        case .spread: .system(.showDesktop)
        }
    }

    /// The command for `gesture`, or `nil` when it should do nothing (the
    /// view it opens is already open). Updates what is open.
    public mutating func resolve(_ gesture: MultiFingerGesture) -> GestureCommand? {
        let opens: MacView
        let closes: MacView
        switch gesture {
        case .swipe(.left), .swipe(.right):
            // Spaces leave an open view as it is.
            repeatIgnored = false
            return Self.command(for: gesture)
        case .swipe(.up): opens = .missionControl; closes = .appExpose
        case .swipe(.down): opens = .appExpose; closes = .missionControl
        case .pinch: opens = .apps; closes = .desktop
        case .spread: opens = .desktop; closes = .apps
        }

        if openView == closes {
            // Toggle back: the view's own shortcut closes it.
            openView = nil
            repeatIgnored = false
            return .system(closes.action)
        }
        if openView == opens, !repeatIgnored {
            // Already open: the same gesture again does nothing, once.
            repeatIgnored = true
            return nil
        }
        openView = opens
        repeatIgnored = false
        return .system(opens.action)
    }

    /// A click, key, typed text, drag, or a view picked on the Mac some
    /// other way: whatever this remote opened may be gone.
    public mutating func forget() {
        openView = nil
        repeatIgnored = false
    }
}

/// Follows one multi-finger stroke on the remote: when it arms, which
/// fingers it tracks, and the gesture at lift.
public struct GestureStroke: Equatable, Sendable {
    public private(set) var start: [Int: TouchPoint] = [:]
    public private(set) var latest: [Int: TouchPoint] = [:]
    /// Set once the stroke reached `GestureClassifier.minimumFingers`.
    public private(set) var isArmed = false
    /// Set once a finger lifted or the stroke was decided: the rest of the
    /// touch sends nothing.
    public private(set) var isFinished = false

    public init() {}

    /// The fingers on the glass now, keyed by a stable per-touch id.
    /// Arms the stroke when enough fingers are down; a finger landing after
    /// that restarts the measurement with every finger.
    public mutating func fingers(_ points: [Int: TouchPoint]) {
        guard !isFinished else { return }
        if points.count >= GestureClassifier.minimumFingers {
            if !isArmed || Set(points.keys) != Set(start.keys) {
                start = points
                isArmed = true
            }
            latest = points
        }
    }

    /// The first finger lifted (or the touch ended): the gesture, if any.
    public mutating func lift() -> MultiFingerGesture? {
        guard isArmed, !isFinished else {
            isFinished = isArmed
            return nil
        }
        isFinished = true
        let ids = start.keys.sorted()
        let s = ids.compactMap { start[$0] }
        let e = ids.compactMap { latest[$0] }
        return GestureClassifier.classify(start: s, end: e)
    }

    /// The system cancelled the touch: send nothing.
    public mutating func cancel() {
        isFinished = true
    }

    public mutating func reset() {
        self = GestureStroke()
    }
}
