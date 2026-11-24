//
//  MirrorPictureInPictureTests.swift
//  PixelHandCoreTests
//
//  UX-041: the PiP state machine, the pointer drawn into PiP frames, the
//  frame pacer and the PiP decoder's recovery.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorPiPStateTests {
    private func ready(autoStart: Bool = true) -> MirrorPiPState {
        var state = MirrorPiPState()
        state.setAutoStartEnabled(autoStart)
        _ = state.setEntitled(true)
        _ = state.setMirrorActive(true)
        return state
    }

    @Test("PiP is available only with Pro and an open mirror; auto start also needs the setting")
    func availability() {
        var state = MirrorPiPState()
        #expect(!state.isAvailable)
        _ = state.setMirrorActive(true)
        #expect(!state.isAvailable) // free tier
        _ = state.setEntitled(true)
        #expect(state.isAvailable)
        #expect(!state.canStartAutomatically)
        state.setAutoStartEnabled(true)
        #expect(state.canStartAutomatically)
        _ = state.setMirrorActive(false)
        #expect(!state.canStartAutomatically)
    }

    @Test("Starting PiP holds the session; stopping releases it")
    func holdsSession() {
        var state = ready()
        #expect(!state.holdsSession)
        do { let r = state.didStart(); #expect(r == [.sessionHoldChanged, .audioChanged]) }
        #expect(state.holdsSession)
        #expect(state.allowsBackgroundAudio)
        do { let r = state.didStart(); #expect(r == []) }
        do { let r = state.didStop(); #expect(r == [.sessionHoldChanged, .audioChanged]) }
        #expect(!state.holdsSession)
        do { let r = state.didStop(); #expect(r == []) }
    }

    @Test("Pause freezes: the Mac drops to keep-alive frames, sound stops, play restores")
    func pauseFreezes() {
        var state = ready()
        do { let r = state.setPaused(true, now: 0); #expect(r == []) } // not showing yet
        _ = state.didStart()
        #expect(state.requestedFPS(settingsFPS: 30) == 30)
        do { let r = state.setPaused(true, now: 10); #expect(r == [.renegotiate, .audioChanged]) }
        #expect(state.isPaused)
        #expect(!state.allowsBackgroundAudio)
        #expect(state.holdsSession) // paused still keeps the connection
        #expect(state.requestedFPS(settingsFPS: 30) == MirrorPiPState.pausedFPS)
        do { let r = state.setPaused(true, now: 11); #expect(r == []) }
        do { let r = state.setPaused(false, now: 12); #expect(r == [.renegotiate, .audioChanged]) }
        #expect(state.requestedFPS(settingsFPS: 20) == 20)
    }

    @Test("Closing while paused asks for the full frame rate again")
    func stopWhilePaused() {
        var state = ready()
        _ = state.didStart()
        _ = state.setPaused(true, now: 0)
        do { let r = state.didStop(); #expect(r == [.sessionHoldChanged, .audioChanged, .renegotiate]) }
        #expect(!state.isPaused)
        #expect(state.requestedFPS(settingsFPS: 30) == 30)
    }

    @Test("Ten minutes paused closes PiP")
    func pausedTimeout() {
        var state = ready()
        _ = state.didStart()
        _ = state.setPaused(true, now: 100)
        do { let r = state.tick(now: 100 + MirrorPiPState.pausedTimeout - 1); #expect(r == []) }
        do { let r = state.tick(now: 100 + MirrorPiPState.pausedTimeout); #expect(r == [.close]) }
        #expect(state.closeReason == .pausedTooLong)
        // Playing never times out.
        var playing = ready()
        _ = playing.didStart()
        do { let r = playing.tick(now: 1_000_000); #expect(r == []) }
    }

    @Test("Mirror stop, session end, device lock and Pro ending close an open PiP")
    func closeReasons() {
        var a = ready()
        _ = a.didStart()
        do { let r = a.setMirrorActive(false); #expect(r == [.close]) }
        #expect(a.closeReason == .mirrorStopped)

        var b = ready()
        _ = b.didStart()
        do { let r = b.sessionEnded(); #expect(r == [.close]) }
        #expect(b.closeReason == .sessionEnded)
        #expect(!b.mirrorActive)

        var c = ready()
        _ = c.didStart()
        do { let r = c.deviceLocked(); #expect(r == [.close]) }
        #expect(c.closeReason == .deviceLocked)

        var d = ready()
        _ = d.didStart()
        do { let r = d.setEntitled(false); #expect(r == [.close]) }
        #expect(d.closeReason == .notEntitled)

        // Nothing to close when PiP isn't showing.
        var e = ready()
        do { let r = e.deviceLocked(); #expect(r == []) }
        do { let r = e.setMirrorActive(false); #expect(r == []) }
    }

    @Test("A new start clears the last close reason")
    func restartClearsReason() {
        var state = ready()
        _ = state.didStart()
        _ = state.deviceLocked()
        _ = state.didStop()
        _ = state.didStart()
        #expect(state.closeReason == nil)
    }
}

@Suite struct MirrorPiPFrameMathTests {
    static let arrow = MirrorCursorShape(id: 7, hotSpotX: 4, hotSpotY: 2, width: 20, height: 30, png: Data([1]))

    private func state(x: Double, y: Double, onDisplay: Bool = true, hidden: Bool = false) -> MirrorCursorState {
        MirrorCursorState(x: x, y: y, shapeID: 7, displayID: 1, isOnMirroredDisplay: onDisplay, isHidden: hidden)
    }

    @Test("The hot spot lands on the pointer's position in frame pixels")
    func hotSpot() throws {
        // 1512 pt display, 1440 px frame, 360 pt PiP window: on screen the
        // arrow is at the 0.75 floor (360 / 1512 = 0.24), and 4 px per point.
        let rect = try #require(MirrorPiPFrameMath.cursorRect(
            state: state(x: 0.5, y: 0.5), shape: Self.arrow,
            displayPointWidth: 1_512, frameWidth: 1_440, frameHeight: 900, windowPointWidth: 360
        ))
        let scale = 0.75 * 4
        #expect(abs(rect.x - (720 - 4 * scale)) < 1e-9)
        #expect(abs(rect.y - (450 - 2 * scale)) < 1e-9)
        #expect(abs(rect.width - 20 * scale) < 1e-9)
        #expect(abs(rect.height - 30 * scale) < 1e-9)
    }

    @Test("A large PiP window uses the mirror's own scale, capped")
    func largeWindow() throws {
        // A 1200 pt window of a 1000 pt display: 1.2× on screen.
        let rect = try #require(MirrorPiPFrameMath.cursorRect(
            state: state(x: 0, y: 0), shape: Self.arrow,
            displayPointWidth: 1_000, frameWidth: 1_200, frameHeight: 750, windowPointWidth: 1_200
        ))
        #expect(abs(rect.width - 20 * 1.2) < 1e-9)
    }

    @Test("Hidden, off-display or off-frame pointers aren't drawn")
    func notDrawn() {
        let args = (shape: Self.arrow, display: 1_440.0, w: 1_440, h: 900, window: 320.0)
        #expect(MirrorPiPFrameMath.cursorRect(state: state(x: 0.5, y: 0.5, hidden: true), shape: args.shape, displayPointWidth: args.display, frameWidth: args.w, frameHeight: args.h, windowPointWidth: args.window) == nil)
        #expect(MirrorPiPFrameMath.cursorRect(state: state(x: 0.5, y: 0.5, onDisplay: false), shape: args.shape, displayPointWidth: args.display, frameWidth: args.w, frameHeight: args.h, windowPointWidth: args.window) == nil)
        #expect(MirrorPiPFrameMath.cursorRect(state: state(x: 1.5, y: 0.5), shape: args.shape, displayPointWidth: args.display, frameWidth: args.w, frameHeight: args.h, windowPointWidth: args.window) == nil)
        #expect(MirrorPiPFrameMath.cursorRect(state: state(x: 0.5, y: 0.5), shape: args.shape, displayPointWidth: args.display, frameWidth: 0, frameHeight: args.h, windowPointWidth: args.window) == nil)
        // At the very edge the sprite still shows partly.
        #expect(MirrorPiPFrameMath.cursorRect(state: state(x: 0.999, y: 0.999), shape: args.shape, displayPointWidth: args.display, frameWidth: args.w, frameHeight: args.h, windowPointWidth: args.window) != nil)
    }

    @Test("An unknown window width falls back to the default")
    func defaultWindow() {
        let a = MirrorPiPFrameMath.cursorRect(state: state(x: 0.5, y: 0.5), shape: Self.arrow, displayPointWidth: 1_440, frameWidth: 1_440, frameHeight: 900, windowPointWidth: 0)
        let b = MirrorPiPFrameMath.cursorRect(state: state(x: 0.5, y: 0.5), shape: Self.arrow, displayPointWidth: 1_440, frameWidth: 1_440, frameHeight: 900, windowPointWidth: MirrorPiPFrameMath.defaultWindowPointWidth)
        #expect(a == b)
    }

    @Test("Flipping for Core Graphics keeps size and mirrors the vertical position")
    func flip() {
        let rect = MirrorRect(x: 10, y: 20, width: 30, height: 40)
        #expect(MirrorPiPFrameMath.flipped(rect, frameHeight: 100) == MirrorRect(x: 10, y: 40, width: 30, height: 40))
    }

    @Test("JPEG frames are redrawn at even sizes, no wider than the cap")
    func jpegSize() {
        #expect(MirrorPiPFrameMath.jpegBufferSize(width: 1_280, height: 801)! == (1_280, 802))
        let big = MirrorPiPFrameMath.jpegBufferSize(width: 3_840, height: 2_400)!
        #expect(big.width == 1_920 && big.height == 1_200)
        #expect(MirrorPiPFrameMath.jpegBufferSize(width: 1, height: 1)! == (2, 2))
        #expect(MirrorPiPFrameMath.jpegBufferSize(width: 0, height: 10) == nil)
        #expect(MirrorPiPFrameMath.jpegBufferSize(width: .nan, height: 10) == nil)
    }

    @Test("Cursor stamps ignore sub-pixel moves")
    func stamps() {
        let a = MirrorPiPFrameMath.CursorStamp(shapeID: 1, rect: MirrorRect(x: 10.2, y: 5, width: 20, height: 30))
        let b = MirrorPiPFrameMath.CursorStamp(shapeID: 1, rect: MirrorRect(x: 10.4, y: 5.1, width: 20, height: 30))
        let c = MirrorPiPFrameMath.CursorStamp(shapeID: 1, rect: MirrorRect(x: 11, y: 5, width: 20, height: 30))
        let d = MirrorPiPFrameMath.CursorStamp(shapeID: 2, rect: MirrorRect(x: 10.2, y: 5, width: 20, height: 30))
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }
}

@Suite struct MirrorPiPPacerTests {
    @Test("Mode follows the PiP state")
    func modes() {
        var state = MirrorPiPState()
        #expect(MirrorPiPPacer.mode(for: state, streamFPS: 30) == .off)
        _ = state.setEntitled(true)
        _ = state.setMirrorActive(true)
        #expect(MirrorPiPPacer.mode(for: state, streamFPS: 30) == .warm)
        _ = state.didStart()
        #expect(MirrorPiPPacer.mode(for: state, streamFPS: 20) == .live(fps: 20))
        _ = state.setPaused(true, now: 0)
        #expect(MirrorPiPPacer.mode(for: state, streamFPS: 20) == .frozen)
    }

    @Test("Live frames are paced at the stream rate, with one trailing frame")
    func live() {
        var pacer = MirrorPiPPacer()
        do { let r = pacer.setMode(.live(fps: 20)); #expect(r == .now) }
        pacer.frameMade(now: 0)
        do { let r = pacer.somethingChanged(now: 0.02); #expect(r == .after(0.05 - 0.02)) }
        do { let r = pacer.somethingChanged(now: 0.03); #expect(r == .none) } // rides along
        do { let r = pacer.deferredFire(now: 0.05); #expect(r) }
        pacer.frameMade(now: 0.05)
        do { let r = pacer.somethingChanged(now: 0.2); #expect(r == .now) }
    }

    @Test("Live is capped at 30 a second; warm is two a second")
    func intervals() {
        var pacer = MirrorPiPPacer()
        _ = pacer.setMode(.live(fps: 60))
        #expect(pacer.interval == 1.0 / 30)
        _ = pacer.setMode(.warm)
        #expect(pacer.interval == MirrorPiPPacer.warmInterval)
    }

    @Test("Frozen and off make nothing and cancel a pending frame")
    func frozen() {
        var pacer = MirrorPiPPacer()
        _ = pacer.setMode(.warm)
        pacer.frameMade(now: 0)
        do { let r = pacer.somethingChanged(now: 0.1); #expect(r != .none) }
        do { let r = pacer.setMode(.frozen); #expect(r == .none) }
        do { let r = pacer.deferredFire(now: 0.5); #expect(!r) }
        do { let r = pacer.somethingChanged(now: 10); #expect(r == .none) }
        _ = pacer.setMode(.off)
        do { let r = pacer.somethingChanged(now: 20); #expect(r == .none) }
    }
}

@Suite struct MirrorPiPDecodeHealthTests {
    @Test("Deltas wait for the first key frame")
    func firstKeyFrame() {
        var health = MirrorPiPDecodeHealth()
        #expect(health.verdict(isKeyFrame: false) == .skip)
        #expect(health.verdict(isKeyFrame: true) == .decode)
        health.decoded(isKeyFrame: true)
        #expect(health.verdict(isKeyFrame: false) == .decode)
    }

    @Test("A failure waits for a key frame; three in a row switch to passthrough")
    func failures() {
        var health = MirrorPiPDecodeHealth()
        health.decoded(isKeyFrame: true)
        do { let r = health.failed(); #expect(r) }
        #expect(health.verdict(isKeyFrame: false) == .skip)
        health.decoded(isKeyFrame: true) // recovered: the count resets
        do { let r = health.failed(); #expect(r) }
        do { let r = health.failed(); #expect(r) }
        #expect(!health.isPassthrough)
        do { let r = health.failed(); #expect(r) }
        #expect(health.isPassthrough)
        #expect(health.verdict(isKeyFrame: false) == .passthrough)
        do { let r = health.failed(); #expect(!r) }
        health.reset()
        #expect(!health.isPassthrough)
        #expect(health.verdict(isKeyFrame: false) == .skip)
    }
}
