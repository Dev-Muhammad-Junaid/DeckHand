//
//  MirrorWindowTests.swift
//  PixelHandCoreTests
//
//  S14 single-window mirror: when a start replaces the capture, the
//  capture size that follows the window, the pointer mapped into the
//  window, the display a window falls back to, the Mac's window tracker
//  (resize debounce, closed / minimised / hidden / locked), the copy, and
//  the remote's window selection.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorTargetTests {
    @Test("A start with a window ID asks for that window, else a display")
    func requested() {
        #expect(MirrorTarget.requested(displayID: 2, windowID: 9) == .window(9))
        #expect(MirrorTarget.requested(displayID: 2, windowID: nil) == .display(2))
        #expect(MirrorTarget.requested(displayID: nil, windowID: 0) == .display(nil))
        #expect(MirrorTarget.window(9).windowID == 9)
        #expect(MirrorTarget.display(1).windowID == nil)
    }

    @Test("Only a different window or display replaces the capture")
    func needsNewCapture() {
        #expect(MirrorTarget.needsNewCapture(current: nil, requested: .display(nil)))
        #expect(!MirrorTarget.needsNewCapture(current: .window(4), requested: .window(4)))
        #expect(MirrorTarget.needsNewCapture(current: .window(4), requested: .window(5)))
        #expect(MirrorTarget.needsNewCapture(current: .window(4), requested: .display(nil)))
        #expect(MirrorTarget.needsNewCapture(current: .window(4), requested: .display(1)))
        #expect(MirrorTarget.needsNewCapture(current: .display(1), requested: .window(4)))
        #expect(!MirrorTarget.needsNewCapture(current: .display(1), requested: .display(nil)))
        #expect(!MirrorTarget.needsNewCapture(current: .display(1), requested: .display(1)))
        #expect(MirrorTarget.needsNewCapture(current: .display(1), requested: .display(2)))
    }
}

@Suite struct MirrorWindowGeometryTests {
    @Test("The capture follows the window's aspect, bounded by the asked width and the window's pixels")
    func captureSize() throws {
        // 800×500 pt at 2×: 1600 px wide, so 960 asked → 960×600.
        let a = try #require(MirrorWindowGeometry.captureSize(width: 800, height: 500, pixelScale: 2, maxWidth: 960))
        #expect(a.width == 960 && a.height == 600)
        // Small window at 1×: never upscaled past 300 px.
        let b = try #require(MirrorWindowGeometry.captureSize(width: 300, height: 200, pixelScale: 1, maxWidth: 1440))
        #expect(b.width == 300 && b.height == 200)
        // Odd sizes become even.
        let c = try #require(MirrorWindowGeometry.captureSize(width: 333, height: 211, pixelScale: 1, maxWidth: 2000))
        #expect(c.width % 2 == 0 && c.height % 2 == 0)
    }

    @Test("A tall window is capped in height, keeping its aspect")
    func tallWindow() throws {
        let size = try #require(MirrorWindowGeometry.captureSize(width: 400, height: 4000, pixelScale: 2, maxWidth: 800))
        #expect(size.height == MirrorWindowGeometry.maxHeight)
        #expect(size.width == 192)
    }

    @Test("Degenerate windows give no size; tiny ones get the minimum side")
    func degenerate() {
        #expect(MirrorWindowGeometry.captureSize(width: 0, height: 100, pixelScale: 2, maxWidth: 640) == nil)
        #expect(MirrorWindowGeometry.captureSize(width: .nan, height: 100, pixelScale: 2, maxWidth: 640) == nil)
        #expect(MirrorWindowGeometry.captureSize(width: 100, height: 100, pixelScale: 1, maxWidth: 0) == nil)
        let tiny = MirrorWindowGeometry.captureSize(width: 4, height: 2, pixelScale: 1, maxWidth: 640)
        #expect(tiny?.width == MirrorWindowGeometry.minSide && tiny?.height == MirrorWindowGeometry.minSide)
        // A bad scale reads as 1×.
        let bad = MirrorWindowGeometry.captureSize(width: 300, height: 200, pixelScale: .infinity, maxWidth: 1000)
        #expect(bad?.width == 300)
    }

    @Test("Sub-threshold size changes aren't resizes")
    func sizeChanged() {
        let a = MirrorRect(x: 0, y: 0, width: 800, height: 600)
        #expect(!MirrorWindowGeometry.sizeChanged(from: a, to: MirrorRect(x: 50, y: 50, width: 801, height: 600.5)))
        #expect(MirrorWindowGeometry.sizeChanged(from: a, to: MirrorRect(x: 0, y: 0, width: 802, height: 600)))
        #expect(MirrorWindowGeometry.sizeChanged(from: a, to: MirrorRect(x: 0, y: 0, width: 800, height: 590)))
    }

    @Test("The pointer maps to fractions of the window and says when it is over it")
    func cursor() {
        let window = MirrorRect(x: 100, y: 200, width: 400, height: 300)
        let mid = MirrorWindowGeometry.cursor(x: 300, y: 350, window: window)
        #expect(mid.x == 0.5 && mid.y == 0.5 && mid.inside)
        let corner = MirrorWindowGeometry.cursor(x: 100, y: 200, window: window)
        #expect(corner.x == 0 && corner.y == 0 && corner.inside)
        let outside = MirrorWindowGeometry.cursor(x: 50, y: 350, window: window)
        #expect(!outside.inside && outside.x < 0)
        // Right / bottom edges are outside (half-open).
        #expect(!MirrorWindowGeometry.cursor(x: 500, y: 350, window: window).inside)
        // A window on a display left of the main one (negative x).
        let left = MirrorWindowGeometry.cursor(x: -900, y: 100, window: MirrorRect(x: -1000, y: 0, width: 200, height: 200))
        #expect(left.inside && left.x == 0.5)
    }

    @Test("A window's home display is the one it overlaps most")
    func homeDisplay() {
        let displays: [(id: UInt32, bounds: MirrorRect)] = [
            (1, MirrorRect(x: 0, y: 0, width: 1440, height: 900)),
            (2, MirrorRect(x: 1440, y: 0, width: 2560, height: 1440)),
        ]
        #expect(MirrorWindowGeometry.homeDisplay(window: MirrorRect(x: 100, y: 100, width: 500, height: 400), displays: displays) == 1)
        // Straddling, mostly on 2.
        #expect(MirrorWindowGeometry.homeDisplay(window: MirrorRect(x: 1340, y: 100, width: 800, height: 400), displays: displays) == 2)
        // Off every display.
        #expect(MirrorWindowGeometry.homeDisplay(window: MirrorRect(x: 9000, y: 9000, width: 10, height: 10), displays: displays) == nil)
        #expect(MirrorWindowGeometry.homeDisplay(window: MirrorRect(x: 0, y: 0, width: 10, height: 10), displays: []) == nil)
    }
}

@Suite struct MirrorWindowTrackerTests {
    static let start = MirrorRect(x: 100, y: 100, width: 800, height: 600)

    @Test("Moving the window updates the pointer frame without a resize")
    func move() {
        var tracker = MirrorWindowTracker(frame: Self.start, now: 0)
        let moved = MirrorRect(x: 300, y: 50, width: 800, height: 600)
        #expect(tracker.observe(.onScreen(frame: moved), now: 1) == .none)
        #expect(tracker.frame == moved)
    }

    @Test("Resizes are applied at most every half second, the last size wins")
    func resizeDebounce() {
        var tracker = MirrorWindowTracker(frame: Self.start, now: 0)
        // Too soon after the start.
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: 100, y: 100, width: 900, height: 600)), now: 0.2) == .none)
        // Due: the latest size.
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: 100, y: 100, width: 950, height: 650)), now: 0.6) == .resize(width: 950, height: 650))
        // A drag continuing: held, then applied when due even if the size stops changing.
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: 100, y: 100, width: 1000, height: 700)), now: 0.8) == .none)
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: 100, y: 100, width: 1000, height: 700)), now: 1.2) == .resize(width: 1000, height: 700))
        // Same size again: nothing.
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: 100, y: 100, width: 1000, height: 700)), now: 2) == .none)
        #expect(tracker.capturedSize.width == 1000)
    }

    @Test("A window missing from two looks in a row has closed; one miss is forgiven")
    func closed() {
        var tracker = MirrorWindowTracker(frame: Self.start, now: 0)
        #expect(tracker.observe(.missing, now: 0.5) == .none)
        #expect(tracker.observe(.onScreen(frame: Self.start), now: 1) == .none)
        #expect(tracker.observe(.missing, now: 1.5) == .none)
        #expect(tracker.observe(.missing, now: 2) == .ended(.closed))
        // Ended: silent from now on.
        #expect(tracker.hasEnded)
        #expect(tracker.observe(.missing, now: 2.5) == .none)
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: 0, y: 0, width: 10, height: 10)), now: 3) == .none)
    }

    @Test("Minimised ends at once; another Space or a hidden app doesn't end")
    func offScreen() {
        var a = MirrorWindowTracker(frame: Self.start, now: 0)
        #expect(a.observe(.offScreen(frame: Self.start, minimized: true), now: 1) == .ended(.minimized))

        var b = MirrorWindowTracker(frame: Self.start, now: 0)
        for t in stride(from: 1.0, through: 20, by: 0.5) {
            #expect(b.observe(.offScreen(frame: Self.start, minimized: false), now: t) == .none)
        }
        #expect(!b.hasEnded)
    }

    @Test("Off screen for an unknown reason ends after the grace period, unless it comes back")
    func hidden() {
        var tracker = MirrorWindowTracker(frame: Self.start, now: 0)
        #expect(tracker.observe(.offScreen(frame: Self.start, minimized: nil), now: 1) == .none)
        #expect(tracker.observe(.offScreen(frame: Self.start, minimized: nil), now: 3) == .none)
        // Back on screen: the clock restarts.
        #expect(tracker.observe(.onScreen(frame: Self.start), now: 3.5) == .none)
        #expect(tracker.observe(.offScreen(frame: Self.start, minimized: nil), now: 4) == .none)
        #expect(tracker.observe(.offScreen(frame: Self.start, minimized: nil), now: 6.9) == .none)
        #expect(tracker.observe(.offScreen(frame: Self.start, minimized: nil), now: 7) == .ended(.hidden))
    }

    @Test("Locking or a capture failure ends the window mirror once")
    func endOnce() {
        var tracker = MirrorWindowTracker(frame: Self.start, now: 0)
        #expect(tracker.end(.locked) == .ended(.locked))
        #expect(tracker.end(.captureFailed) == .none)
    }

    @Test("Broken frames are ignored")
    func brokenFrames() {
        var tracker = MirrorWindowTracker(frame: Self.start, now: 0)
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: .nan, y: 0, width: 10, height: 10)), now: 5) == .none)
        #expect(tracker.observe(.onScreen(frame: MirrorRect(x: 0, y: 0, width: 0, height: 10)), now: 6) == .none)
        #expect(tracker.frame == Self.start)
    }
}

@Suite struct MirrorWindowCopyAndSelectionTests {
    @Test("Every end reason names the window and the display it falls back to")
    func copy() {
        for reason in MirrorWindowTracker.EndReason.allCases {
            let text = MirrorWindowCopy.ended(reason, appName: "Notes", displayName: "Built-in")
            #expect(text.hasSuffix("Showing Built-in instead."))
            if reason != .locked { #expect(text.hasPrefix("The Notes window")) }
        }
        #expect(MirrorWindowCopy.ended(.closed, appName: "", displayName: "Main") == "The window closed. Showing Main instead.")
        #expect(MirrorWindowCopy.notFound(displayName: "Main").contains("Main"))
    }

    @Test("Window labels for the picker chip and VoiceOver")
    func labels() {
        let w = MirroredWindow(windowID: 1, title: "Shopping", appName: "Notes", width: 800, height: 600)
        #expect(w.shortLabel == "Notes")
        #expect(w.longLabel == "Notes — Shopping")
        let long = MirroredWindow(windowID: 1, title: "", appName: "A Very Long Application Name", width: 1, height: 1)
        #expect(long.shortLabel == "A Very Long …")
        #expect(long.longLabel == "A Very Long Application Name")
        #expect(MirroredWindow(windowID: 1, title: "", appName: "", width: 1, height: 1).shortLabel == "Window")
        #expect(MirroredWindow(windowID: 1, title: "Doc", appName: "", width: 1, height: 1).longLabel == "Doc")
    }

    @Test("The remote's selection: request, confirmation, display pick and fallback")
    func selection() {
        var s = MirrorWindowSelection()
        #expect(!s.isActive)
        s.selectWindow(7)
        #expect(s.isActive && s.requestedWindowID == 7 && s.window == nil)
        // An earlier start's display list: the request stands.
        s.hostReported(window: nil)
        #expect(s.requestedWindowID == 7)
        let w = MirroredWindow(windowID: 7, title: "T", appName: "A", width: 640, height: 480)
        s.hostReported(window: w)
        #expect(s.window == w)
        #expect(s.pointWidth(displayWidth: 1440) == 640)
        // The window ended: back to a display.
        s.windowEnded()
        #expect(!s.isActive && s.pointWidth(displayWidth: 1440) == 1440)
        // Another remote picked a window on the shared capture.
        s.hostReported(window: w)
        #expect(s.isActive && s.requestedWindowID == nil)
        s.selectDisplay()
        #expect(!s.isActive)
        // Picking another window forgets the old one's details.
        s.hostReported(window: w)
        s.selectWindow(8)
        #expect(s.window == nil && s.requestedWindowID == 8)
    }

    @Test("A window mirror shows no 'Cursor on …' display badge")
    func chrome() {
        let displays = [
            DisplayInfo(displayID: 1, name: "Built-in", isMain: true, width: 1440, height: 900),
            DisplayInfo(displayID: 2, name: "Studio", isMain: false, width: 2560, height: 1440),
        ]
        let display = MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: 1, cursorDisplayID: 2, followsCursor: false)
        #expect(display.cursorElsewhere?.displayID == 2)
        let window = MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: 1, cursorDisplayID: 2, followsCursor: false, mirroringWindow: true)
        #expect(window.cursorElsewhere == nil)
    }
}
