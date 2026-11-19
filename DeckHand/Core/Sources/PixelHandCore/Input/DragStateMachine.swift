//
//  DragStateMachine.swift
//  PixelHandCore
//
//  Click-drag from the remote's trackpad, and the Mac's safety release.
//
//  On the remote (`DragStateMachine`):
//
//  - **Press, hold, move.** One finger rests for `DragPolicy.holdDelay`:
//    the drag arms (a haptic says so). Moving it now presses the left
//    button (`input.mouseDown`) and the movement that follows drags.
//    Lifting ends the drag (`input.mouseUp`). An armed finger lifted
//    without moving right-clicks, as the long press did before.
//  - **Two-finger drag lock.** While dragging, a second finger landing
//    locks the button down: lift every finger, put one back and keep
//    dragging (to cross a large screen in several strokes). A quick tap
//    ends the lock and releases the button; so does
//    `DragPolicy.lockTimeout` with no finger on the glass.
//  - **Safety.** A cancelled touch (a system gesture, a call) releases the
//    button at once.
//
//  On the Mac (`HeldButtonWatchdog`): a held button is released when the
//  remote that pressed it disconnects, or when it hasn't refreshed it for
//  `DragPolicy.hostReleaseAfter` (the remote repeats `mouseDown` every
//  `DragPolicy.keepDownInterval` while the button is down), so a remote
//  that vanishes mid-drag never leaves the Mac's button stuck.
//
//  Times are seconds on any monotonic clock (`CACurrentMediaTime` on iOS);
//  distances are points on the trackpad.
//

import Foundation

public enum DragPolicy {
    /// How long a still finger rests before the drag arms. The long press
    /// (right-click) used the same delay.
    public static let holdDelay: TimeInterval = 0.4
    /// Movement (points from where the finger landed) that counts as a
    /// move rather than a rest.
    public static let slop: Double = 6
    /// How long a locked drag waits with no finger on the glass before it
    /// releases the button by itself.
    public static let lockTimeout: TimeInterval = 4
    /// The longest touch that still counts as a tap (ends a lock).
    public static let tapMaxDuration: TimeInterval = 0.3
    /// While a button is down the remote repeats `mouseDown` this often.
    public static let keepDownInterval: TimeInterval = 1
    /// The Mac releases a held button nobody refreshed for this long.
    public static let hostReleaseAfter: TimeInterval = 5
}

public struct DragStateMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// No finger, no button.
        case idle
        /// One finger down and still since `downAt`; not armed yet.
        case pressing(downAt: TimeInterval)
        /// Held still long enough: moving now starts a drag.
        case armed
        /// This touch can't become a drag (it moved early, or more fingers
        /// landed). Nothing happens until every finger lifts.
        case passive
        /// The button is down and the fingers drag.
        case dragging
        /// The button is down and locked; fingers are still on the glass.
        case lockedHolding
        /// The button is down and locked with no finger on the glass,
        /// since `since`.
        case locked(since: TimeInterval)
        /// A finger came back during a lock at `downAt`; `moved` once it
        /// travels past the slop.
        case lockedTouch(downAt: TimeInterval, moved: Bool)
    }

    /// What the remote does in answer to an event.
    public enum Output: Equatable, Sendable {
        /// The hold delay passed: give a haptic.
        case armed
        /// Send `input.mouseDown(.left)`.
        case buttonDown
        /// Send `input.mouseUp(.left)`.
        case buttonUp
        /// Send a right click (an armed press lifted without moving).
        case rightClick
        /// The drag is locked: give a haptic.
        case lockEngaged
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    /// Whether the Mac's button is down because of this machine.
    public var isButtonDown: Bool {
        switch phase {
        case .dragging, .lockedHolding, .locked, .lockedTouch: true
        case .idle, .pressing, .armed, .passive: false
        }
    }

    /// While true, finger movement (any number of fingers) moves the
    /// pointer and nothing scrolls or swipes: the button is down.
    public var routesMovementToPointer: Bool { isButtonDown }

    /// While true the touch's tap, double-tap and long-press handling is
    /// this machine's, and the view must not click on its own.
    public var ownsTouch: Bool {
        switch phase {
        case .idle, .pressing, .passive: false
        case .armed, .dragging, .lockedHolding, .locked, .lockedTouch: true
        }
    }

    // MARK: Events

    /// Fingers landed; `fingerCount` is how many are on the glass now.
    public mutating func touchBegan(fingerCount: Int, at now: TimeInterval) -> [Output] {
        switch phase {
        case .idle:
            phase = fingerCount == 1 ? .pressing(downAt: now) : .passive
        case .pressing, .armed:
            if fingerCount > 1 { phase = .passive }
        case .passive:
            break
        case .dragging:
            if fingerCount >= 2 {
                phase = .lockedHolding
                return [.lockEngaged]
            }
        case .lockedHolding, .lockedTouch:
            break
        case .locked:
            phase = .lockedTouch(downAt: now, moved: false)
        }
        return []
    }

    /// The fingers moved; `distance` is how far (points) the touch has
    /// travelled from where it landed.
    public mutating func touchMoved(distance: Double, at now: TimeInterval) -> [Output] {
        let beyondSlop = distance > DragPolicy.slop
        switch phase {
        case .pressing:
            if beyondSlop { phase = .passive }
        case .armed:
            if beyondSlop {
                phase = .dragging
                return [.buttonDown]
            }
        case let .lockedTouch(downAt, moved):
            if beyondSlop, !moved { phase = .lockedTouch(downAt: downAt, moved: true) }
        case .idle, .passive, .dragging, .lockedHolding, .locked:
            break
        }
        return []
    }

    /// Fingers lifted; `remaining` is how many are still on the glass.
    public mutating func touchEnded(remaining: Int, at now: TimeInterval) -> [Output] {
        guard remaining == 0 else { return [] }
        switch phase {
        case .idle, .pressing, .passive:
            phase = .idle
        case .armed:
            phase = .idle
            return [.rightClick]
        case .dragging:
            phase = .idle
            return [.buttonUp]
        case .lockedHolding:
            phase = .locked(since: now)
        case .locked:
            break
        case let .lockedTouch(downAt, moved):
            if !moved, now - downAt <= DragPolicy.tapMaxDuration {
                phase = .idle
                return [.buttonUp]
            }
            phase = .locked(since: now)
        }
        return []
    }

    /// The system cancelled the touches: release whatever is held.
    public mutating func touchesCancelled() -> [Output] {
        let wasDown = isButtonDown
        phase = .idle
        return wasDown ? [.buttonUp] : []
    }

    /// Call while a finger rests or a lock waits (every frame or on a
    /// short timer): arms a held press and times out an idle lock.
    public mutating func tick(at now: TimeInterval) -> [Output] {
        switch phase {
        case let .pressing(downAt) where now - downAt >= DragPolicy.holdDelay:
            phase = .armed
            return [.armed]
        case let .locked(since) where now - since >= DragPolicy.lockTimeout:
            phase = .idle
            return [.buttonUp]
        default:
            return []
        }
    }

    /// The connection went away or the trackpad left the screen: forget
    /// everything. Returns `.buttonUp` if the button was down, for a remote
    /// that can still send it.
    public mutating func reset() -> [Output] {
        touchesCancelled()
    }
}

/// The Mac's record of buttons remotes hold down, so none stays stuck.
/// Generic over the connection key (the Mac uses the connection's `UUID`).
public struct HeldButtonWatchdog<Key: Hashable & Sendable>: Sendable {
    public struct Held: Equatable, Sendable {
        public var key: Key
        public var button: MouseButton

        public init(key: Key, button: MouseButton) {
            self.key = key
            self.button = button
        }
    }

    private var refreshed: [Key: [MouseButton: TimeInterval]] = [:]

    public init() {}

    /// `button` went down (or was refreshed) for `key`. Returns `true` if it
    /// was not already held, so the Mac posts a mouse-down only once.
    @discardableResult
    public mutating func pressed(_ button: MouseButton, by key: Key, at now: TimeInterval) -> Bool {
        let isNew = refreshed[key]?[button] == nil
        refreshed[key, default: [:]][button] = now
        return isNew
    }

    /// `button` was released by `key`. Returns `true` if it was held.
    @discardableResult
    public mutating func released(_ button: MouseButton, by key: Key) -> Bool {
        guard refreshed[key]?.removeValue(forKey: button) != nil else { return false }
        if refreshed[key]?.isEmpty == true { refreshed.removeValue(forKey: key) }
        return true
    }

    /// Whether `button` is held by anyone (moves become drags).
    public func isHeld(_ button: MouseButton) -> Bool {
        refreshed.values.contains { $0[button] != nil }
    }

    /// Any button held by anyone.
    public var anyHeld: Bool { !refreshed.isEmpty }

    /// The buttons held by `key`, now forgotten (the remote disconnected).
    public mutating func releaseAll(for key: Key) -> [MouseButton] {
        guard let buttons = refreshed.removeValue(forKey: key) else { return [] }
        return buttons.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Buttons not refreshed for `DragPolicy.hostReleaseAfter`, now
    /// forgotten. The Mac posts a mouse-up for each.
    public mutating func expired(at now: TimeInterval) -> [Held] {
        var out: [Held] = []
        for (key, buttons) in refreshed {
            for (button, at) in buttons where now - at >= DragPolicy.hostReleaseAfter {
                out.append(Held(key: key, button: button))
            }
        }
        for held in out { released(held.button, by: held.key) }
        return out
    }
}
