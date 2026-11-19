//
//  MirrorVideoTests.swift
//  PixelHandCoreTests
//
//  The HEVC mirror's rules (S5): payloads, the Mac's key-frame policy and
//  per-remote backpressure, the remote's watchdog, codec choice, bitrate.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorHEVCPayloadTests {
    static let sets = MirrorHEVCParameterSets(
        nalUnitHeaderLength: 4,
        sets: [Data([0x40, 0x01, 0x0C]), Data([0x42, 0x01, 0x01, 0x01]), Data([0x44, 0x01])]
    )

    @Test("Parameter sets survive encoding")
    func roundTrip() throws {
        let data = Self.sets.encoded()
        #expect(data.count == 2 + (2 + 3) + (2 + 4) + (2 + 2))
        #expect(try MirrorHEVCParameterSets.decode(data) == Self.sets)
    }

    @Test("Damaged parameter sets are refused, never trapped on")
    func damaged() {
        let good = Self.sets.encoded()
        #expect(throws: MirrorHEVCParameterSets.DecodeError.truncated) { try MirrorHEVCParameterSets.decode(Data([4])) }
        #expect(throws: MirrorHEVCParameterSets.DecodeError.truncated) { try MirrorHEVCParameterSets.decode(good.dropLast()) }
        var badLength = good
        badLength[0] = 3
        #expect(throws: MirrorHEVCParameterSets.DecodeError.badHeaderLength(3)) { try MirrorHEVCParameterSets.decode(badLength) }
        var tooFew = good
        tooFew[1] = 2
        #expect(throws: MirrorHEVCParameterSets.DecodeError.badCount(2)) { try MirrorHEVCParameterSets.decode(tooFew) }
        #expect(throws: MirrorHEVCParameterSets.DecodeError.emptySet) {
            try MirrorHEVCParameterSets.decode(Data([4, 3, 0, 0, 0, 1, 1, 0, 1, 1]))
        }
        // Random bytes never crash.
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let bytes = (0..<Int.random(in: 0..<40, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator) }
            _ = try? MirrorHEVCParameterSets.decode(Data(bytes))
            _ = MirrorHEVCNALUnits.isWellFormed(Data(bytes), headerLength: 4)
        }
    }

    @Test("Frame payloads: whole length-prefixed NAL units only")
    func nalUnits() {
        let units = [Data([0x26, 0x01, 0xAF]), Data(repeating: 7, count: 300)]
        for length in [2, 4] {
            let payload = MirrorHEVCNALUnits.join(units, headerLength: length)
            #expect(MirrorHEVCNALUnits.isWellFormed(payload, headerLength: length))
        }
        let payload = MirrorHEVCNALUnits.join(units, headerLength: 4)
        #expect(payload.count == 4 + 3 + 4 + 300)
        #expect(!MirrorHEVCNALUnits.isWellFormed(payload.dropLast(), headerLength: 4))
        #expect(!MirrorHEVCNALUnits.isWellFormed(Data(), headerLength: 4))
        #expect(!MirrorHEVCNALUnits.isWellFormed(Data([0, 0, 0, 0]), headerLength: 4)) // zero-length unit
        #expect(!MirrorHEVCNALUnits.isWellFormed(payload, headerLength: 3))
    }
}

@Suite struct MirrorKeyFramePolicyTests {
    @Test("The first frame is a key frame")
    func firstFrame() {
        var policy = MirrorKeyFramePolicy()
        do { let r = policy.shouldForceKeyFrame(now: 10); #expect(r) }
        policy.noteKeyFrame(at: 10)
        do { let r = policy.shouldForceKeyFrame(now: 10.1); #expect(!r) }
        policy.reset()
        do { let r = policy.shouldForceKeyFrame(now: 11); #expect(r) }
    }

    @Test("Requests are served, but forced key frames stay spaced out")
    func spacing() {
        var policy = MirrorKeyFramePolicy()
        policy.noteKeyFrame(at: 0)
        policy.request()
        do { let r = policy.shouldForceKeyFrame(now: 0.2); #expect(!r) } // too soon, kept
        #expect(policy.pending)
        do { let r = policy.shouldForceKeyFrame(now: 0.5); #expect(r) }
        policy.noteKeyFrame(at: 0.5)
        do { let r = policy.shouldForceKeyFrame(now: 0.6); #expect(!r) } // nothing pending
        // A request loop gives at most one forced key frame per spacing.
        var forced = 0
        var t = 0.5
        while t < 3.5 {
            policy.request()
            if policy.shouldForceKeyFrame(now: t) {
                forced += 1
                policy.noteKeyFrame(at: t)
            }
            t += 0.05
        }
        #expect(forced <= Int(3 / MirrorKeyFramePolicy.minForcedSpacing) + 1)
    }

    @Test("The encoder's own key frame serves a waiting request")
    func naturalKeyFrame() {
        var policy = MirrorKeyFramePolicy()
        policy.noteKeyFrame(at: 0)
        policy.request()
        policy.noteKeyFrame(at: 0.3)
        #expect(!policy.pending)
        do { let r = policy.shouldForceKeyFrame(now: 1); #expect(!r) }
    }
}

@Suite struct MirrorVideoBackpressureTests {
    @Test("A remote starts at a key frame; deltas before it are dropped")
    func startsAtKeyFrame() {
        var bp = MirrorVideoBackpressure()
        do { let r = bp.decide(isKeyFrame: false); #expect(r == .drop(requestKeyFrame: true)) }
        do { let r = bp.decide(isKeyFrame: true); #expect(r == .send) }
        do { let r = bp.decide(isKeyFrame: false); #expect(r == .send) }
    }

    @Test("Deltas drop while more than two sends are un-acked, then a key frame is asked for when the link drains")
    func dropsThenRecovers() {
        var bp = MirrorVideoBackpressure()
        do { let r = bp.decide(isKeyFrame: true); #expect(r == .send) } // 1 in flight
        do { let r = bp.decide(isKeyFrame: false); #expect(r == .send) } // 2
        do { let r = bp.decide(isKeyFrame: false); #expect(r == .send) } // 3: allowed, 2 were un-acked
        #expect(bp.unacked == 3)
        do { let r = bp.decide(isKeyFrame: false); #expect(r == .drop(requestKeyFrame: false)) }
        #expect(bp.needsKeyFrame)
        // The chain is broken: no delta goes until a key frame.
        do { let r = bp.noteAcked(); #expect(r) }                         // 3 → 2: ask now
        do { let r = bp.decide(isKeyFrame: false); #expect(r == .drop(requestKeyFrame: true)) }
        do { let r = bp.noteAcked(); #expect(!r) }
        do { let r = bp.decide(isKeyFrame: true); #expect(r == .send) }
        #expect(!bp.needsKeyFrame)
        do { let r = bp.decide(isKeyFrame: false); #expect(r == .send) }
    }

    @Test("Key frames are dropped too when the link is far behind")
    func keyFrameCap() {
        var bp = MirrorVideoBackpressure()
        for _ in 0..<MirrorVideoBackpressure.maxUnackedForKeyFrame {
            do { let r = bp.decide(isKeyFrame: true); #expect(r == .send) }
        }
        do { let r = bp.decide(isKeyFrame: true); #expect(r == .drop(requestKeyFrame: false)) }
        #expect(bp.needsKeyFrame)
        bp.reset()
        #expect(bp.unacked == 0)
        #expect(bp.needsKeyFrame)
    }

    @Test("Acks never go below zero")
    func acks() {
        var bp = MirrorVideoBackpressure()
        do { let r = bp.noteAcked(); #expect(!r) }
        #expect(bp.unacked == 0)
    }
}

@Suite struct MirrorVideoWatchdogTests {
    @Test("Deltas before the first key frame are dropped and a key frame asked for")
    func waitsForKeyFrame() {
        var dog = MirrorVideoWatchdog(now: 0)
        let first = dog.frameArrived(.deltaFrame, now: 0.1)
        #expect(!first.decode)
        #expect(first.action == .requestKeyFrame)
        do { let r = dog.frameArrived(.deltaFrame, now: 0.2); #expect(r == (false, .none)) } // spaced
        do { let r = dog.frameArrived(.parameterSets, now: 0.3); #expect(r.decode) }
        do { let r = dog.frameArrived(.keyFrame, now: 0.3); #expect(r == (true, .none)) }
        #expect(dog.phase == .playing)
        dog.frameDisplayed(now: 0.35)
        #expect(dog.keyFrameRequests == 0)
        do { let r = dog.frameArrived(.deltaFrame, now: 0.4); #expect(r == (true, .none)) }
    }

    @Test("A decode error drops deltas until the next key frame")
    func decodeError() {
        var dog = MirrorVideoWatchdog(now: 0)
        _ = dog.frameArrived(.keyFrame, now: 0)
        dog.frameDisplayed(now: 0)
        do { let r = dog.decodeFailed(now: 1); #expect(r == .requestKeyFrame) }
        #expect(dog.phase == .recovering)
        do { let r = dog.frameArrived(.deltaFrame, now: 1.1); #expect(!r.decode) }
        do { let r = dog.frameArrived(.keyFrame, now: 1.2); #expect(r.decode) }
        #expect(dog.phase == .playing)
    }

    @Test("A delta sent after a drop on the Mac starts recovery")
    func afterDrop() {
        var dog = MirrorVideoWatchdog(now: 0)
        _ = dog.frameArrived(.keyFrame, now: 0)
        let r = dog.frameArrived(.deltaFrame, afterDrop: true, now: 0.5)
        #expect(!r.decode)
        #expect(r.action == .requestKeyFrame)
    }

    @Test("Frames arriving with no picture: ask for a key frame, then fall back to JPEG")
    func stallFallsBack() {
        var dog = MirrorVideoWatchdog(now: 0)
        _ = dog.frameArrived(.keyFrame, now: 0)
        // Frames keep arriving; nothing is ever displayed. Two requests
        // (the stall, then the deltas it can't use), then JPEG.
        var actions: [MirrorVideoWatchdog.Action] = []
        var t = 0.0
        while t < 10 {
            let arrival = dog.frameArrived(.deltaFrame, now: t)
            if arrival.action != .none { actions.append(arrival.action) }
            let a = dog.tick(now: t)
            if a != .none { actions.append(a) }
            t += 0.25
        }
        #expect(actions == [.requestKeyFrame, .requestKeyFrame, .fallBackToJPEG])
        #expect(dog.phase == .fellBack)
        do { let r = dog.frameArrived(.keyFrame, now: 11); #expect(r == (false, .none)) }
        dog.reset(now: 12)
        #expect(dog.phase == .fellBack) // lasts for the session
    }

    @Test("An idle screen sends nothing, which is not a stall")
    func idleIsFine() {
        var dog = MirrorVideoWatchdog(now: 0)
        _ = dog.frameArrived(.keyFrame, now: 0)
        dog.frameDisplayed(now: 0.05)
        do { let r = dog.tick(now: 30); #expect(r == .none) }
        #expect(dog.phase == .playing)
    }

    @Test("A picture after a request clears the count")
    func recovers() {
        var dog = MirrorVideoWatchdog(now: 0)
        _ = dog.frameArrived(.keyFrame, now: 0)
        dog.frameDisplayed(now: 0)
        _ = dog.frameArrived(.deltaFrame, now: 2.5)
        do { let r = dog.tick(now: 2.5); #expect(r == .requestKeyFrame) }
        _ = dog.frameArrived(.keyFrame, now: 2.8)
        dog.frameDisplayed(now: 2.8)
        #expect(dog.keyFrameRequests == 0)
        _ = dog.frameArrived(.deltaFrame, now: 3)
        do { let r = dog.tick(now: 3); #expect(r == .none) }
    }

    @Test("No decoder: straight to JPEG")
    func noDecoder() {
        var dog = MirrorVideoWatchdog(now: 0)
        do { let r = dog.fallBack(); #expect(r == .fallBackToJPEG) }
        do { let r = dog.fallBack(); #expect(r == .none) }
        do { let r = dog.decodeFailed(now: 1); #expect(r == .none) }
    }
}

@Suite struct MirrorCodecChoiceTests {
    @Test("HEVC only when preferred, decodable and not given up on")
    func choice() {
        #expect(MirrorCodecChoice.requested(prefersHEVC: true, hevcDecodeAvailable: true, fellBack: false) == .hevc)
        #expect(MirrorCodecChoice.requested(prefersHEVC: false, hevcDecodeAvailable: true, fellBack: false) == .jpeg)
        #expect(MirrorCodecChoice.requested(prefersHEVC: true, hevcDecodeAvailable: false, fellBack: false) == .jpeg)
        #expect(MirrorCodecChoice.requested(prefersHEVC: true, hevcDecodeAvailable: true, fellBack: true) == .jpeg)
    }

    @Test("Bitrate scales with size and rate, within limits; dimensions are even")
    func bitrate() {
        let small = MirrorVideoBitrate.averageBitsPerSecond(width: 320, height: 200, fps: 10)
        let mid = MirrorVideoBitrate.averageBitsPerSecond(width: 1440, height: 900, fps: 20)
        let huge = MirrorVideoBitrate.averageBitsPerSecond(width: 1920, height: 1200, fps: 30)
        #expect(small == 1_000_000)
        #expect(mid == 3_110_400)
        #expect(huge <= 12_000_000)
        #expect(MirrorVideoBitrate.averageBitsPerSecond(width: -5, height: 0, fps: 0) == 1_000_000)
        #expect(MirrorVideoBitrate.evenDimension(901) == 900)
        #expect(MirrorVideoBitrate.evenDimension(900) == 900)
        #expect(MirrorVideoBitrate.evenDimension(1) == 2)
    }
}
