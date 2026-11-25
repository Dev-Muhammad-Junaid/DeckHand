//
//  PicturePointerTests.swift
//  PixelHandCoreTests
//
//  OR-16, pointer control on the mirror picture: the relative mapping
//  through zoom and pan, the gesture arbitration (pinch vs two-finger
//  scroll vs pan, and the two-finger tap), and the per-Mac default and
//  memory.
//

import Foundation
import Testing
@testable import PixelHandCore

private func approx(_ a: Double, _ b: Double, _ tolerance: Double = 0.0001) -> Bool {
    abs(a - b) <= tolerance
}

private func point(_ x: Double, _ y: Double) -> TouchPoint { TouchPoint(x: x, y: y) }

/// An iPad pane, 1000 × 700, showing a 16:10 Mac (1000 × 625, centred).
private let frame = PictureFrame.fitted(viewWidth: 1000, viewHeight: 700, aspect: 16.0 / 10.0)

@Suite("Picture pointer · relative mapping through zoom and pan")
struct PicturePointerMappingTests {
    @Test("The picture fits and centres in the pane")
    func fittedFrame() {
        #expect(approx(frame.pictureWidth, 1000))
        #expect(approx(frame.pictureHeight, 625))
        #expect(approx(frame.pictureMinY, 37.5))
        let tall = PictureFrame.fitted(viewWidth: 400, viewHeight: 800, aspect: 0.5)
        #expect(approx(tall.pictureWidth, 400) && approx(tall.pictureHeight, 800))
        let short = PictureFrame.fitted(viewWidth: 900, viewHeight: 300, aspect: 16.0 / 10.0)
        #expect(approx(short.pictureHeight, 300) && approx(short.pictureWidth, 480))
        #expect(approx(short.pictureMinX, 210))
    }

    @Test("Unzoomed, the finger moves the pointer exactly as the Pointer surface does")
    func unzoomedIsThePointerSurface() {
        let delta = PicturePointerMapping.pointerDelta(dx: 12, dy: -5, zoom: .identity)
        #expect(approx(delta.dx, 12) && approx(delta.dy, -5))
        #expect(approx(PicturePointerMapping.sensitivity(1.8, zoom: .identity), 1.8))
    }

    @Test("Zoomed in, the same finger travel moves the pointer less, by the zoom")
    func zoomDividesTheDelta() {
        var zoom = PictureZoom.identity
        zoom.zoom(by: 2, anchor: point(500, 350), in: frame)
        let delta = PicturePointerMapping.pointerDelta(dx: 20, dy: 10, zoom: zoom)
        #expect(approx(delta.dx, 10) && approx(delta.dy, 5))
        #expect(approx(PicturePointerMapping.sensitivity(1.8, zoom: zoom), 0.9))
    }

    @Test("Pan never changes the pointer's movement: it is relative")
    func panDoesNotChangeTheDelta() {
        var zoom = PictureZoom.identity
        zoom.zoom(by: 3, anchor: point(500, 350), in: frame)
        let before = PicturePointerMapping.pointerDelta(dx: 9, dy: 9, zoom: zoom)
        zoom.pan(dx: 120, dy: -80, in: frame)
        let after = PicturePointerMapping.pointerDelta(dx: 9, dy: 9, zoom: zoom)
        #expect(approx(before.dx, after.dx) && approx(before.dy, after.dy))
    }

    @Test("The Mac's pointer is drawn through the zoom and pan, and back")
    func pointerThroughZoomAndPan() {
        // Unzoomed: the display's centre is the pane's centre.
        let centre = PictureZoom.identity.pointerOnScreen(normalizedX: 0.5, normalizedY: 0.5, in: frame)
        #expect(approx(centre.x, 500) && approx(centre.y, 350))
        // The top-leading corner of the display at 1×.
        let corner = PictureZoom.identity.pointerOnScreen(normalizedX: 0, normalizedY: 0, in: frame)
        #expect(approx(corner.x, 0) && approx(corner.y, 37.5))

        var zoom = PictureZoom.identity
        zoom.zoom(by: 2, anchor: point(500, 350), in: frame)
        let quarter = zoom.pointerOnScreen(normalizedX: 0.25, normalizedY: 0.5, in: frame)
        // 250 from the centre at 1× is 500 from it at 2×: the left edge.
        #expect(approx(quarter.x, 0) && approx(quarter.y, 350))

        zoom.pan(dx: 100, dy: 0, in: frame)
        let panned = zoom.pointerOnScreen(normalizedX: 0.25, normalizedY: 0.5, in: frame)
        #expect(approx(panned.x, 100))
        // And the inverse maps it back.
        let content = zoom.toContent(panned, in: frame)
        let expected = frame.point(normalizedX: 0.25, normalizedY: 0.5)
        #expect(approx(content.x, expected.x) && approx(content.y, expected.y))
    }

    @Test("Zoom keeps the content under the fingers where it is")
    func anchoredZoom() {
        var zoom = PictureZoom.identity
        let anchor = point(700, 300)
        let under = zoom.toContent(anchor, in: frame)
        zoom.zoom(by: 2.5, anchor: anchor, in: frame)
        let after = zoom.toScreen(under, in: frame)
        #expect(approx(after.x, anchor.x) && approx(after.y, anchor.y))
    }

    @Test("A pinch that slides keeps the content under the fingers (zoom, then pan)")
    func pinchAndPanTracksTheFingers() {
        var arbiter = TwoFingerArbiter()
        arbiter.begin(point(450, 300), point(550, 300), at: 0)
        var zoom = PictureZoom.identity
        let grabbed = zoom.toContent(point(500, 300), in: frame)
        // Open to 1.5× and slide 60 pt right, in two moves.
        for (a, b) in [(point(425, 300), point(575, 300)), (point(485, 300), point(635, 300))] {
            if case let .zoom(scale, anchor, dx, dy) = arbiter.move(a, b) {
                zoom.zoom(by: scale, anchor: anchor, in: frame)
                zoom.pan(dx: dx, dy: dy, in: frame)
            }
        }
        let now = zoom.toScreen(grabbed, in: frame)
        #expect(approx(zoom.scale, 1.5))
        #expect(approx(now.x, 560) && approx(now.y, 300))
    }

    @Test("Zoom stays between 1× and 4×, and 1× snaps back to fit")
    func zoomLimits() {
        var zoom = PictureZoom.identity
        zoom.zoom(by: 10, anchor: point(500, 350), in: frame)
        #expect(zoom.scale == PictureZoom.maximumScale)
        zoom.zoom(by: 0.01, anchor: point(900, 100), in: frame)
        #expect(zoom == .identity)
        #expect(!zoom.isZoomed)
        // Panning an unzoomed picture does nothing.
        zoom.pan(dx: 50, dy: 50, in: frame)
        #expect(zoom == .identity)
    }

    @Test("Pan stops where the picture's edge meets the pane's")
    func panIsClamped() {
        var zoom = PictureZoom.identity
        zoom.zoom(by: 2, anchor: point(500, 350), in: frame)
        zoom.pan(dx: 10_000, dy: 10_000, in: frame)
        let limits = zoom.offsetLimits(in: frame)
        #expect(approx(limits.x, 500))       // (1000 × 2 − 1000) / 2
        #expect(approx(limits.y, 275))       // (625 × 2 − 700) / 2
        #expect(approx(zoom.offsetX, 500) && approx(zoom.offsetY, 275))
        let leftEdge = zoom.toScreen(point(frame.pictureMinX, 0), in: frame)
        #expect(approx(leftEdge.x, 0))
    }

    @Test("A letterboxed axis stays centred until the zoom fills it")
    func letterboxedAxisCentred() {
        var zoom = PictureZoom.identity
        zoom.zoom(by: 1.1, anchor: point(500, 350), in: frame)
        zoom.pan(dx: 0, dy: 200, in: frame)
        // 625 × 1.1 = 687.5 < 700: nothing to pan vertically.
        #expect(zoom.offsetY == 0)
    }

    @Test("A zoomed picture pans to keep the Mac's pointer in view")
    func followsThePointer() {
        var zoom = PictureZoom.identity
        zoom.zoom(by: 2, anchor: point(500, 350), in: frame)
        // The pointer at the display's left edge is off screen at 2×.
        let off = zoom.pointerOnScreen(normalizedX: 0.02, normalizedY: 0.5, in: frame)
        #expect(off.x < PictureZoom.followMargin)
        zoom.follow(off, in: frame)
        let now = zoom.pointerOnScreen(normalizedX: 0.02, normalizedY: 0.5, in: frame)
        #expect(approx(now.x, PictureZoom.followMargin))
        // Inside the margin already: nothing moves.
        let before = zoom
        zoom.follow(point(500, 350), in: frame)
        #expect(zoom == before)
        // Unzoomed never pans.
        var fit = PictureZoom.identity
        fit.follow(point(-50, -50), in: frame)
        #expect(fit == .identity)
    }
}

@Suite("Picture pointer · gesture arbitration")
struct TwoFingerArbiterTests {
    /// Two fingers 100 pt apart around (500, 300).
    private func started(allowsPinch: Bool = true) -> TwoFingerArbiter {
        var arbiter = TwoFingerArbiter(allowsPinch: allowsPinch)
        arbiter.begin(point(450, 300), point(550, 300), at: 0)
        return arbiter
    }

    @Test("Fingers that travel together scroll the Mac, with nothing lost")
    func scroll() {
        var arbiter = started()
        #expect(arbiter.move(point(450, 304), point(550, 304)) == .none)
        let first = arbiter.move(point(450, 312), point(550, 312))
        #expect(first == .scroll(dx: 0, dy: 12))
        #expect(arbiter.decision == .scroll)
        #expect(arbiter.move(point(450, 320), point(550, 320)) == .scroll(dx: 0, dy: 8))
        #expect(arbiter.end(at: 0.5) == .scrollEnded)
    }

    @Test("Fingers that open apart pinch the picture, and the gesture stays a pinch")
    func pinch() {
        var arbiter = started()
        let step = arbiter.move(point(438, 300), point(562, 300))
        guard case let .zoom(scale, anchor, dx, dy) = step else {
            Issue.record("expected a zoom, got \(step)")
            return
        }
        #expect(approx(scale, 1.24))
        #expect(approx(anchor.x, 500) && approx(anchor.y, 300))
        #expect(approx(dx, 0) && approx(dy, 0))
        // Later the fingers slide together: still the pinch, now panning.
        let pan = arbiter.move(point(438, 340), point(562, 340))
        #expect(pan == .zoom(scale: 1, anchor: point(500, 300), dx: 0, dy: 40))
        #expect(arbiter.decision == .pinch)
        #expect(arbiter.end(at: 1) == .pinchEnded)
    }

    @Test("A lopsided pinch (one finger still) is still a pinch, not a scroll")
    func lopsidedPinch() {
        var arbiter = started()
        // Right finger moves 24 pt outward: gap +24, midpoint travels 12.
        let step = arbiter.move(point(450, 300), point(574, 300))
        if case .zoom = step {} else { Issue.record("expected a zoom, got \(step)") }
    }

    @Test("A scroll whose gap wobbles a little stays a scroll")
    func wobblyScroll() {
        var arbiter = started()
        // 30 pt of travel with 6 pt of gap change.
        let step = arbiter.move(point(450, 330), point(556, 330))
        if case .scroll = step {} else { Issue.record("expected a scroll, got \(step)") }
    }

    @Test("An ambiguous move waits, and the wait is bounded")
    func ambiguousWaits() {
        #expect(TwoFingerArbiter.decide(travel: 30, spanChange: 18, allowsPinch: true) == .undecided)
        #expect(TwoFingerArbiter.decide(travel: 30, spanChange: 20, allowsPinch: true) == .pinch)
        #expect(TwoFingerArbiter.decide(travel: 36, spanChange: 18, allowsPinch: true) == .scroll)
        // Past this much travel every move is decided one way or the other.
        let bound = TwoFingerPolicy.pinchSpan / TwoFingerPolicy.spanToTravel
        for change in stride(from: 0.0, through: 100, by: 0.5) {
            #expect(TwoFingerArbiter.decide(travel: bound, spanChange: change, allowsPinch: true) != .undecided)
        }
    }

    @Test("The rule: one cut-off, so nothing is both a pinch and a scroll")
    func decisionRule() {
        for travel in stride(from: 0.0, through: 60, by: 2) {
            for change in stride(from: 0.0, through: 60, by: 2) {
                let decision = TwoFingerArbiter.decide(travel: travel, spanChange: change, allowsPinch: true)
                if decision == .pinch {
                    #expect(change >= TwoFingerPolicy.pinchSpan)
                    #expect(change > travel * TwoFingerPolicy.spanToTravel)
                }
                if decision == .scroll {
                    #expect(change <= travel * TwoFingerPolicy.spanToTravel)
                }
            }
        }
    }

    @Test("Without pinch, every two-finger move scrolls")
    func pinchDisabled() {
        var arbiter = started(allowsPinch: false)
        // Even fingers that open apart scroll once they travel.
        #expect(arbiter.move(point(430, 300), point(570, 300)) == .none)
        let step = arbiter.move(point(430, 315), point(570, 315))
        if case .scroll = step {} else { Issue.record("expected a scroll, got \(step)") }
    }

    @Test("A quick still two-finger touch is a tap (right-click)")
    func twoFingerTap() {
        var arbiter = started()
        _ = arbiter.move(point(451, 302), point(551, 301))
        #expect(arbiter.end(at: 0.15) == .tap)
    }

    @Test("Too slow, or moved, and it isn't a tap")
    func notATap() {
        var slow = started()
        #expect(slow.end(at: 0.6) == .nothing)
        var moved = started()
        _ = moved.move(point(450, 309), point(550, 309))
        #expect(moved.end(at: 0.1) == .nothing)
    }

    @Test("Cancelling never taps, and closes what was open")
    func cancel() {
        var undecided = started()
        #expect(undecided.cancel() == .nothing)
        var scrolling = started()
        _ = scrolling.move(point(450, 330), point(550, 330))
        #expect(scrolling.cancel() == .scrollEnded)
        #expect(!scrolling.isTracking)
        #expect(scrolling.end(at: 1) == .nothing)
    }
}

@Suite("Picture pointer · default and memory per Mac")
struct PicturePointerMemoryTests {
    let studio = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    let laptop = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    @Test("Off the first time, for every Mac")
    func offByDefault() {
        let memory = PicturePointerMemory()
        #expect(!memory.isOn(for: studio))
        #expect(!memory.isOn(for: nil))
        #expect(!PicturePointerMemory(json: "").isOn(for: studio))
        #expect(!PicturePointerMemory(json: "not json").isOn(for: studio))
    }

    @Test("Then the last choice, per Mac")
    func remembersPerMac() {
        var memory = PicturePointerMemory()
        memory.set(true, for: studio)
        #expect(memory.isOn(for: studio))
        #expect(!memory.isOn(for: laptop))
        memory.set(false, for: studio)
        #expect(!memory.isOn(for: studio))
        memory.set(true, for: laptop)
        #expect(memory.isOn(for: laptop))
    }

    @Test("It survives the round trip through storage")
    func roundTrip() {
        var memory = PicturePointerMemory()
        memory.set(true, for: studio)
        memory.set(false, for: laptop)
        let restored = PicturePointerMemory(json: memory.json)
        #expect(restored == memory)
        #expect(restored.isOn(for: studio))
    }

    @Test("Bounded: the oldest Mac is forgotten past the capacity")
    func bounded() {
        var memory = PicturePointerMemory()
        memory.set(true, for: studio)
        for _ in 0..<PicturePointerMemory.capacity {
            memory.set(true, for: UUID())
        }
        #expect(memory.entries.count == PicturePointerMemory.capacity)
        #expect(!memory.isOn(for: studio))
    }

    @Test("Offered only where the picture has no trackpad, active only with a picture")
    func offeredAndActive() {
        #expect(PicturePointerControl.isOffered(screenOnly: true, showsTrackpad: false))
        #expect(!PicturePointerControl.isOffered(screenOnly: true, showsTrackpad: true))
        #expect(!PicturePointerControl.isOffered(screenOnly: false, showsTrackpad: false))
        #expect(PicturePointerControl.isActive(offered: true, isOn: true, mirrorAllowed: true, hasPicture: true))
        #expect(!PicturePointerControl.isActive(offered: true, isOn: true, mirrorAllowed: false, hasPicture: true))
        #expect(!PicturePointerControl.isActive(offered: true, isOn: true, mirrorAllowed: true, hasPicture: false))
        #expect(!PicturePointerControl.isActive(offered: false, isOn: true, mirrorAllowed: true, hasPicture: true))
        #expect(PicturePointerControl.toggleIdentifier == "ph.mirror.pointerControl")
        #expect(PicturePointerControl.toggleLabel == "Control the pointer from the picture")
    }
}
