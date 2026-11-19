//
//  TrackpadGestureTests.swift
//  PixelHandCoreTests
//
//  S11: multi-finger swipes and pinches, decided at lift, natural Spaces
//  direction, and toggle-back.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct GestureClassifierTests {
    private let three = [TouchPoint(x: 100, y: 100), TouchPoint(x: 160, y: 100), TouchPoint(x: 220, y: 100)]

    private func moved(_ points: [TouchPoint], dx: Double, dy: Double) -> [TouchPoint] {
        points.map { TouchPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    private func scaled(_ points: [TouchPoint], by factor: Double) -> [TouchPoint] {
        let c = GestureClassifier.centroid(points)
        return points.map { TouchPoint(x: c.x + ($0.x - c.x) * factor, y: c.y + ($0.y - c.y) * factor) }
    }

    @Test("Swipes in all four directions")
    func swipes() {
        #expect(GestureClassifier.classify(start: three, end: moved(three, dx: -80, dy: 5)) == .swipe(.left))
        #expect(GestureClassifier.classify(start: three, end: moved(three, dx: 80, dy: -5)) == .swipe(.right))
        #expect(GestureClassifier.classify(start: three, end: moved(three, dx: 5, dy: -80)) == .swipe(.up))
        #expect(GestureClassifier.classify(start: three, end: moved(three, dx: 5, dy: 80)) == .swipe(.down))
    }

    @Test("Too short or taken back: nothing")
    func tooShort() {
        #expect(GestureClassifier.classify(start: three, end: moved(three, dx: 30, dy: 0)) == nil)
        #expect(GestureClassifier.classify(start: three, end: three) == nil)
    }

    @Test("Pinch and spread")
    func pinches() {
        let wide = scaled(three, by: 2.5) // radius 50 → 125
        #expect(GestureClassifier.classify(start: wide, end: three) == .pinch)
        #expect(GestureClassifier.classify(start: three, end: wide) == .spread)
    }

    @Test("A pinch that drifts is still a pinch")
    func pinchWithDrift() {
        let wide = scaled(three, by: 3)
        #expect(GestureClassifier.classify(start: wide, end: moved(three, dx: 20, dy: 10)) == .pinch)
    }

    @Test("Four fingers work too; two don't")
    func fingerCounts() {
        let four = three + [TouchPoint(x: 280, y: 110)]
        #expect(GestureClassifier.classify(start: four, end: moved(four, dx: 0, dy: -90)) == .swipe(.up))
        let two = Array(three.prefix(2))
        #expect(GestureClassifier.classify(start: two, end: moved(two, dx: 0, dy: -90)) == nil)
        #expect(GestureClassifier.classify(start: three, end: Array(three.prefix(2))) == nil, "mismatched")
    }
}

@Suite struct GestureStrokeTests {
    private func pts(_ dx: Double, _ dy: Double, count: Int = 3) -> [Int: TouchPoint] {
        var out: [Int: TouchPoint] = [:]
        for i in 0..<count { out[i] = TouchPoint(x: Double(i) * 60 + dx, y: 100 + dy) }
        return out
    }

    @Test("Decided at the first lift from net travel")
    func decidedAtLift() {
        var s = GestureStroke()
        s.fingers(pts(0, 0))
        #expect(s.isArmed)
        s.fingers(pts(0, -40))
        s.fingers(pts(0, -100))
        do { let r = s.lift(); #expect(r == .swipe(.up)) }
        #expect(s.isFinished)
        do { let r = s.lift(); #expect(r == nil, "once per stroke") }
    }

    @Test("A swipe taken back before lifting does nothing")
    func takenBack() {
        var s = GestureStroke()
        s.fingers(pts(0, 0))
        s.fingers(pts(-150, 0))
        s.fingers(pts(-10, 0))
        do { let r = s.lift(); #expect(r == nil) }
    }

    @Test("Fewer than three fingers never arm; a cancelled stroke sends nothing")
    func notArmedOrCancelled() {
        var two = GestureStroke()
        two.fingers(pts(0, 0, count: 2))
        two.fingers(pts(0, -200, count: 2))
        #expect(!two.isArmed)
        do { let r = two.lift(); #expect(r == nil) }

        var cancelled = GestureStroke()
        cancelled.fingers(pts(0, 0))
        cancelled.fingers(pts(0, -200))
        cancelled.cancel()
        do { let r = cancelled.lift(); #expect(r == nil) }
    }

    @Test("A fourth finger landing restarts the measurement")
    func fourthFinger() {
        var s = GestureStroke()
        s.fingers(pts(0, 0))
        s.fingers(pts(0, -30))
        s.fingers(pts(0, -30, count: 4))
        s.fingers(pts(0, -60, count: 4))
        do { let r = s.lift(); #expect(r == nil, "only 30 pt since the fourth finger") }
    }
}

@Suite struct GestureMapTests {
    @Test("The fixed map, natural direction for Spaces")
    func fixedMap() {
        #expect(GestureMap.command(for: .swipe(.left)) == .switchSpace(.next))
        #expect(GestureMap.command(for: .swipe(.right)) == .switchSpace(.previous))
        #expect(GestureMap.command(for: .swipe(.up)) == .system(.missionControl))
        #expect(GestureMap.command(for: .swipe(.down)) == .system(.appExpose))
        #expect(GestureMap.command(for: .pinch) == .system(.launchpad))
        #expect(GestureMap.command(for: .spread) == .system(.showDesktop))
        #expect(GestureCommand.switchSpace(.next).message == .system(.switchSpace(direction: .next, displayID: nil)))
        #expect(GestureCommand.system(.appExpose).message == .system(.run(action: .appExpose)))
    }

    @Test("The opposite gesture closes what this remote opened")
    func toggleBack() {
        var map = GestureMap()
        do { let r = map.resolve(.swipe(.up)); #expect(r == .system(.missionControl)) }
        do { let r = map.resolve(.swipe(.down)); #expect(r == .system(.missionControl), "closes Mission Control") }
        #expect(map.openView == nil)
        do { let r = map.resolve(.swipe(.down)); #expect(r == .system(.appExpose), "now opens App Exposé") }
        do { let r = map.resolve(.swipe(.up)); #expect(r == .system(.appExpose), "closes App Exposé") }
        do { let r = map.resolve(.pinch); #expect(r == .system(.launchpad)) }
        do { let r = map.resolve(.spread); #expect(r == .system(.launchpad), "closes Apps") }
        do { let r = map.resolve(.spread); #expect(r == .system(.showDesktop)) }
        do { let r = map.resolve(.pinch); #expect(r == .system(.showDesktop), "brings the windows back") }
        #expect(map.openView == nil)
    }

    @Test("The same gesture again does nothing once, then opens again")
    func repeatOnce() {
        var map = GestureMap()
        do { let r = map.resolve(.swipe(.up)); #expect(r == .system(.missionControl)) }
        do { let r = map.resolve(.swipe(.up)); #expect(r == nil) }
        do { let r = map.resolve(.swipe(.up)); #expect(r == .system(.missionControl)) }
        do { let r = map.resolve(.swipe(.up)); #expect(r == nil) }
    }

    @Test("Spaces leave an open view as it is")
    func spacesKeepView() {
        var map = GestureMap()
        _ = map.resolve(.swipe(.up))
        do { let r = map.resolve(.swipe(.left)); #expect(r == .switchSpace(.next)) }
        #expect(map.openView == .missionControl)
        do { let r = map.resolve(.swipe(.down)); #expect(r == .system(.missionControl)) }
    }

    @Test("A click or a key forgets what was open")
    func forget() {
        var map = GestureMap()
        _ = map.resolve(.swipe(.up))
        map.forget()
        do { let r = map.resolve(.swipe(.down)); #expect(r == .system(.appExpose), "opens, doesn't close") }
    }

    @Test("Opening another view replaces the open one")
    func replace() {
        var map = GestureMap()
        _ = map.resolve(.spread)
        do { let r = map.resolve(.swipe(.up)); #expect(r == .system(.missionControl)) }
        #expect(map.openView == .missionControl)
    }
}

@Suite struct HoverPointerTrackerTests {
    @Test("The first sample sets the origin; moves become scaled deltas")
    func deltas() throws {
        var t = HoverPointerTracker()
        do { let r = t.moved(to: TouchPoint(x: 10, y: 10), sensitivity: 2); #expect(r == nil) }
        #expect(t.isHovering)
        let moved = t.moved(to: TouchPoint(x: 13, y: 9), sensitivity: 2)
        let d = try #require(moved)
        #expect(d.dx == 6)
        #expect(d.dy == -2)
        do { let r = t.moved(to: TouchPoint(x: 13, y: 9), sensitivity: 2); #expect(r == nil, "no change") }
    }

    @Test("A leap or a re-entry doesn't jump the pointer")
    func leaps() {
        var t = HoverPointerTracker()
        _ = t.moved(to: TouchPoint(x: 0, y: 0), sensitivity: 1)
        do { let r = t.moved(to: TouchPoint(x: 500, y: 0), sensitivity: 1); #expect(r == nil) }
        do { let r = t.moved(to: TouchPoint(x: 505, y: 0), sensitivity: 1); #expect(r?.dx == 5) }
        t.ended()
        #expect(!t.isHovering)
        do { let r = t.moved(to: TouchPoint(x: 0, y: 0), sensitivity: 1); #expect(r == nil) }
    }

    @Test("Non-finite samples are ignored")
    func nonFinite() {
        var t = HoverPointerTracker()
        _ = t.moved(to: TouchPoint(x: 0, y: 0), sensitivity: 1)
        do { let r = t.moved(to: TouchPoint(x: .nan, y: 0), sensitivity: 1); #expect(r == nil) }
        do { let r = t.moved(to: TouchPoint(x: 1, y: 0), sensitivity: 1); #expect(r?.dx == 1) }
    }
}
