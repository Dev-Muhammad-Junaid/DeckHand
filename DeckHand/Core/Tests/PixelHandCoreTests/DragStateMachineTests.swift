//
//  DragStateMachineTests.swift
//  PixelHandCoreTests
//
//  Click-drag on the remote's trackpad (press-hold-move, two-finger drag
//  lock) and the Mac's held-button watchdog.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct DragStateMachineTests {
    private let hold = DragPolicy.holdDelay

    /// One finger down at 0, held past the delay: armed.
    private func armed() -> DragStateMachine {
        var m = DragStateMachine()
        do { let r = m.touchBegan(fingerCount: 1, at: 0); #expect(r.isEmpty) }
        do { let r = m.tick(at: hold / 2); #expect(r.isEmpty) }
        do { let r = m.tick(at: hold); #expect(r == [.armed]) }
        #expect(m.phase == .armed)
        return m
    }

    @Test("Press, hold, move: the button goes down; lifting releases it")
    func pressHoldMove() {
        var m = armed()
        do { let r = m.touchMoved(distance: 3, at: 0.5); #expect(r.isEmpty, "inside the slop") }
        #expect(!m.isButtonDown)
        do { let r = m.touchMoved(distance: 10, at: 0.6); #expect(r == [.buttonDown]) }
        #expect(m.isButtonDown)
        #expect(m.routesMovementToPointer)
        do { let r = m.touchMoved(distance: 200, at: 0.7); #expect(r.isEmpty, "only one down") }
        do { let r = m.touchEnded(remaining: 0, at: 1); #expect(r == [.buttonUp]) }
        #expect(m.phase == .idle)
        #expect(!m.isButtonDown)
    }

    @Test("Armed and lifted without moving: a right click, as the long press was")
    func holdWithoutMoveRightClicks() {
        var m = armed()
        do { let r = m.touchEnded(remaining: 0, at: 0.8); #expect(r == [.rightClick]) }
        #expect(m.phase == .idle)
    }

    @Test("A finger that moves before the hold delay is a pointer move, never a drag")
    func earlyMoveIsPassive() {
        var m = DragStateMachine()
        _ = m.touchBegan(fingerCount: 1, at: 0)
        do { let r = m.touchMoved(distance: 20, at: 0.1); #expect(r.isEmpty) }
        #expect(m.phase == .passive)
        do { let r = m.tick(at: 2); #expect(r.isEmpty, "never arms once moved") }
        #expect(!m.ownsTouch)
        do { let r = m.touchEnded(remaining: 0, at: 2); #expect(r.isEmpty) }
        #expect(m.phase == .idle)
    }

    @Test("A quick tap is the view's: the machine stays out of it")
    func tapIsNotOwned() {
        var m = DragStateMachine()
        _ = m.touchBegan(fingerCount: 1, at: 0)
        #expect(!m.ownsTouch)
        do { let r = m.touchEnded(remaining: 0, at: 0.1); #expect(r.isEmpty) }
    }

    @Test("A second finger before the drag starts cancels it (no right click)")
    func secondFingerBeforeDrag() {
        var m = armed()
        do { let r = m.touchBegan(fingerCount: 2, at: 0.5); #expect(r.isEmpty) }
        #expect(m.phase == .passive)
        do { let r = m.touchEnded(remaining: 0, at: 0.6); #expect(r.isEmpty) }
    }

    @Test("Two-finger drag lock: lift, come back, keep dragging; a tap ends it")
    func dragLock() {
        var m = armed()
        do { let r = m.touchMoved(distance: 10, at: 0.5); #expect(r == [.buttonDown]) }
        do { let r = m.touchBegan(fingerCount: 2, at: 0.6); #expect(r == [.lockEngaged]) }
        do { let r = m.touchEnded(remaining: 1, at: 0.7); #expect(r.isEmpty) }
        do { let r = m.touchEnded(remaining: 0, at: 0.8); #expect(r.isEmpty, "locked: still down") }
        #expect(m.isButtonDown)
        #expect(m.phase == .locked(since: 0.8))
        // A finger comes back and drags further.
        do { let r = m.touchBegan(fingerCount: 1, at: 1.5); #expect(r.isEmpty) }
        do { let r = m.touchMoved(distance: 50, at: 1.6); #expect(r.isEmpty) }
        #expect(m.routesMovementToPointer)
        do { let r = m.touchEnded(remaining: 0, at: 2); #expect(r.isEmpty, "a move, not a tap") }
        #expect(m.isButtonDown)
        // A quick tap releases.
        do { let r = m.touchBegan(fingerCount: 1, at: 3); #expect(r.isEmpty) }
        #expect(m.ownsTouch, "the tap must not also click")
        do { let r = m.touchEnded(remaining: 0, at: 3.1); #expect(r == [.buttonUp]) }
        #expect(m.phase == .idle)
    }

    @Test("A long rest during a lock is not a tap: the lock stays")
    func slowTouchKeepsLock() {
        var m = armed()
        _ = m.touchMoved(distance: 10, at: 0.5)
        _ = m.touchBegan(fingerCount: 2, at: 0.6)
        _ = m.touchEnded(remaining: 0, at: 0.7)
        _ = m.touchBegan(fingerCount: 1, at: 1)
        do { let r = m.touchEnded(remaining: 0, at: 1 + DragPolicy.tapMaxDuration + 0.2); #expect(r.isEmpty) }
        #expect(m.isButtonDown)
    }

    @Test("A lock with no finger releases by itself after the timeout")
    func lockTimesOut() {
        var m = armed()
        _ = m.touchMoved(distance: 10, at: 0.5)
        _ = m.touchBegan(fingerCount: 2, at: 0.6)
        _ = m.touchEnded(remaining: 0, at: 1)
        do { let r = m.tick(at: 1 + DragPolicy.lockTimeout - 0.1); #expect(r.isEmpty) }
        do { let r = m.tick(at: 1 + DragPolicy.lockTimeout); #expect(r == [.buttonUp]) }
        #expect(m.phase == .idle)
    }

    @Test("Cancelled touches release a held button, and only then")
    func cancelReleases() {
        var dragging = armed()
        _ = dragging.touchMoved(distance: 10, at: 0.5)
        do { let r = dragging.touchesCancelled(); #expect(r == [.buttonUp]) }
        #expect(dragging.phase == .idle)

        var pressing = DragStateMachine()
        _ = pressing.touchBegan(fingerCount: 1, at: 0)
        do { let r = pressing.touchesCancelled(); #expect(r.isEmpty) }

        var locked = armed()
        _ = locked.touchMoved(distance: 10, at: 0.5)
        _ = locked.touchBegan(fingerCount: 2, at: 0.6)
        _ = locked.touchEnded(remaining: 0, at: 1)
        do { let r = locked.reset(); #expect(r == [.buttonUp]) }
    }

    @Test("Several fingers landing at once never arm")
    func multiFingerStart() {
        var m = DragStateMachine()
        _ = m.touchBegan(fingerCount: 3, at: 0)
        do { let r = m.tick(at: 1); #expect(r.isEmpty) }
        #expect(m.phase == .passive)
    }
}

@Suite struct HeldButtonWatchdogTests {
    @Test("A press is new once; refreshes keep it alive")
    func pressAndRefresh() {
        var w = HeldButtonWatchdog<Int>()
        do { let r = w.pressed(.left, by: 1, at: 0); #expect(r) }
        do { let r = w.pressed(.left, by: 1, at: 1); #expect(!r, "a refresh, not a new press") }
        #expect(w.isHeld(.left))
        #expect(!w.isHeld(.right))
        do { let r = w.expired(at: 1 + DragPolicy.hostReleaseAfter - 0.1); #expect(r.isEmpty) }
        do { let r = w.expired(at: 1 + DragPolicy.hostReleaseAfter); #expect(r == [.init(key: 1, button: .left)]) }
        #expect(!w.anyHeld)
    }

    @Test("Release is reported once; unknown releases do nothing")
    func release() {
        var w = HeldButtonWatchdog<Int>()
        w.pressed(.left, by: 1, at: 0)
        do { let r = w.released(.left, by: 1); #expect(r) }
        do { let r = w.released(.left, by: 1); #expect(!r) }
        do { let r = w.released(.right, by: 2); #expect(!r) }
        #expect(!w.anyHeld)
    }

    @Test("A disconnect releases that remote's buttons only")
    func disconnect() {
        var w = HeldButtonWatchdog<Int>()
        w.pressed(.left, by: 1, at: 0)
        w.pressed(.right, by: 1, at: 0)
        w.pressed(.left, by: 2, at: 0)
        do { let r = w.releaseAll(for: 1); #expect(r == [.left, .right]) }
        #expect(w.isHeld(.left), "remote 2 still holds it")
        do { let r = w.releaseAll(for: 1); #expect(r.isEmpty) }
    }

    @Test("The remote's keep-alive is well inside the Mac's release time")
    func keepAliveMargin() {
        #expect(DragPolicy.keepDownInterval * 3 <= DragPolicy.hostReleaseAfter)
        #expect(DragPolicy.lockTimeout < DragPolicy.hostReleaseAfter)
    }
}
