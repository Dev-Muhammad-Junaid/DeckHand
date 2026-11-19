//
//  MirrorAudioTests.swift
//  PixelHandCoreTests
//
//  S17: the audio payloads, sequence tracking, the jitter buffer and its
//  drop policy, the Mac's packet cutting and send queue, the stats and the
//  lock gate.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorAudioFramingTests {
    @Test("A format round-trips, cookie included")
    func formatRoundTrip() throws {
        let format = MirrorAudioFormat(codec: .aacLC, channels: 2, sampleRate: 48_000, magicCookie: Data([0x11, 0x90]))
        #expect(format.framesPerPacket == 1024)
        let bytes = format.encoded()
        #expect(bytes.count == MirrorAudioFormat.headerByteCount + 2)
        #expect(Array(bytes.prefix(4)) == [1, 2, 0x04, 0x00])
        #expect(try MirrorAudioFormat.decode(bytes) == format)
        #expect(abs(format.packetDuration - 1024.0 / 48_000) < 1e-9)
    }

    @Test("A format the remote can't play is refused")
    func formatRefused() {
        var bad = [UInt8](MirrorAudioFormat(codec: .pcm16, channels: 2, sampleRate: 48_000).encoded())
        bad[0] = 9
        #expect(throws: MirrorAudioFormat.DecodeError.unknownCodec(9)) { try MirrorAudioFormat.decode(Data(bad)) }
        bad[0] = 2
        bad[1] = 6
        #expect(throws: MirrorAudioFormat.DecodeError.badChannels(6)) { try MirrorAudioFormat.decode(Data(bad)) }
        #expect(throws: MirrorAudioFormat.DecodeError.truncated) { try MirrorAudioFormat.decode(Data([1, 2, 3])) }
        let tooFast = MirrorAudioFormat(codec: .pcm16, channels: 1, sampleRate: 400_000).encoded()
        #expect(throws: MirrorAudioFormat.DecodeError.badSampleRate(400_000)) { try MirrorAudioFormat.decode(tooFast) }
        // Cookie length says more than is there.
        var short = [UInt8](MirrorAudioFormat(codec: .aacLC, channels: 2, sampleRate: 48_000, magicCookie: Data([1, 2, 3])).encoded())
        short.removeLast()
        #expect(throws: MirrorAudioFormat.DecodeError.truncated) { try MirrorAudioFormat.decode(Data(short)) }
    }

    @Test("A packet round-trips through a binary frame")
    func packetRoundTrip() throws {
        let packet = MirrorAudioPacket(sequence: 0xFFFF_FFFE, sampleTime: 1_234_567_890_123, frameCount: 1024, data: Data([9, 8, 7]))
        let frame = BinaryFrameHeader.frame(kind: .audioPacket, seq: 3, presentationTimeMicros: 99, payload: packet.encoded())
        let (header, payload) = try BinaryFrameHeader.decodeFrame(frame)
        #expect(header.kind == .audioPacket)
        #expect(BinaryFrameHeader.Kind.audioFormat.rawValue == 7)
        #expect(BinaryFrameHeader.Kind.audioPacket.rawValue == 8)
        #expect(try MirrorAudioPacket.decode(payload) == packet)
        #expect(PixelHandStream.audio != PixelHandStream.mirror)
    }

    @Test("Empty, short and oversized packets are refused")
    func packetRefused() {
        let empty = MirrorAudioPacket(sequence: 1, sampleTime: 0, frameCount: 0, data: Data()).encoded()
        #expect(throws: MirrorAudioPacket.DecodeError.empty) { try MirrorAudioPacket.decode(empty) }
        #expect(throws: MirrorAudioPacket.DecodeError.truncated) { try MirrorAudioPacket.decode(Data([0, 1])) }
        let huge = MirrorAudioPacket(sequence: 1, sampleTime: 0, frameCount: 1, data: Data(count: MirrorAudioPacket.maxDataLength + 1)).encoded()
        #expect(throws: MirrorAudioPacket.DecodeError.tooLarge(MirrorAudioPacket.maxDataLength + 1)) { try MirrorAudioPacket.decode(huge) }
    }

    @Test("PCM16 round-trips within one step and clips")
    func pcm16() {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 2, -3, .nan]
        let data = MirrorAudioPCM16.encode(samples)
        #expect(data.count == samples.count * 2)
        let back = MirrorAudioPCM16.decode(data)
        let expected: [Float] = [0, 0.5, -0.5, 1, -1, 1, -1, 0]
        for (a, b) in zip(back, expected) {
            #expect(abs(a - b) < 1.0 / 32_000)
        }
        #expect(MirrorAudioPCM16.decode(Data([0x7F])).isEmpty)
    }
}

@Suite struct MirrorAudioSequenceTests {
    @Test("In order, gaps and late packets")
    func verdicts() {
        var tracker = MirrorAudioSequenceTracker()
        #expect(tracker.note(10) == .inOrder)
        #expect(tracker.note(11) == .inOrder)
        #expect(tracker.note(14) == .afterGap(lost: 2))
        #expect(tracker.note(13) == .late)
        #expect(tracker.note(14) == .late)
        #expect(tracker.note(15) == .inOrder)
        let counts = tracker.takeCounts()
        #expect(counts.received == 4)
        #expect(counts.lost == 2)
        #expect(counts.late == 2)
        #expect(tracker.takeCounts().received == 0)
    }

    @Test("Sequence numbers wrap around")
    func wraps() {
        var tracker = MirrorAudioSequenceTracker()
        _ = tracker.note(UInt32.max - 1)
        #expect(tracker.note(UInt32.max) == .inOrder)
        #expect(tracker.note(0) == .inOrder)
        #expect(tracker.note(2) == .afterGap(lost: 1))
        #expect(tracker.note(UInt32.max) == .late)
    }

    @Test("A new format starts a new run")
    func restart() {
        var tracker = MirrorAudioSequenceTracker()
        _ = tracker.note(500)
        tracker.restart()
        #expect(tracker.note(0) == .inOrder)
    }
}

@Suite struct MirrorAudioJitterTests {
    private let rate = 48_000
    private let packet = 1024

    @Test("Steady arrivals measure no jitter; uneven ones do")
    func estimator() {
        var steady = MirrorAudioJitterEstimator(sampleRate: rate)
        for index in 0..<50 {
            let sampleTime = UInt64(index * packet)
            steady.note(sampleTime: sampleTime, arrival: 5 + Double(sampleTime) / Double(rate))
        }
        #expect(steady.jitter < 1e-9)

        var uneven = MirrorAudioJitterEstimator(sampleRate: rate)
        for index in 0..<200 {
            let sampleTime = UInt64(index * packet)
            let wobble = index.isMultiple(of: 2) ? 0.0 : 0.02
            uneven.note(sampleTime: sampleTime, arrival: Double(sampleTime) / Double(rate) + wobble)
        }
        // Every difference is 20 ms; the estimate converges on it.
        #expect(abs(uneven.jitter - 0.02) < 0.001)
    }

    @Test("A long pause counts as at most a second of jitter")
    func pauseCapped() {
        var estimator = MirrorAudioJitterEstimator(sampleRate: rate)
        estimator.note(sampleTime: 0, arrival: 0)
        estimator.note(sampleTime: 1024, arrival: 60)
        #expect(estimator.jitter <= 1.0 / 16 + 1e-9)
    }

    @Test("The target is one packet plus three jitters, between 60 and 150 ms")
    func desiredTarget() {
        let policy = MirrorAudioJitterPolicy.standard
        let duration = Double(packet) / Double(rate)
        #expect(policy.desiredTarget(jitter: 0, packetDuration: duration) == 0.06)
        #expect(abs(policy.desiredTarget(jitter: 0.015, packetDuration: duration) - (duration + 0.045)) < 1e-9)
        #expect(policy.desiredTarget(jitter: 1, packetDuration: duration) == 0.15)
        #expect(policy.desiredTarget(jitter: .nan, packetDuration: duration) == 0.06)
    }
}

@Suite struct MirrorAudioJitterBufferTests {
    private func samples(frames: Int, channels: Int = 2, value: Float = 0.5) -> [Float] {
        [Float](repeating: value, count: frames * channels)
    }

    private func pull(_ buffer: inout MirrorAudioJitterBuffer, frames: Int) -> (played: Int, output: [Float]) {
        var output = [Float](repeating: -9, count: frames * buffer.channels)
        let played = output.withUnsafeMutableBufferPointer { buffer.pull(frameCount: frames, into: $0) }
        return (played, output)
    }

    @Test("Silence until the target is buffered, then audio with a fade-in")
    func prebuffers() {
        var buffer = MirrorAudioJitterBuffer(channels: 2, sampleRate: 48_000)
        buffer.push(samples(frames: 1024))         // 21 ms < 60 ms
        let early = pull(&buffer, frames: 256)
        #expect(early.played == 0)
        #expect(early.output.allSatisfy { $0 == 0 })
        #expect(buffer.isPrebuffering)

        buffer.push(samples(frames: 2048))         // 64 ms ≥ 60 ms
        let first = pull(&buffer, frames: 256)
        #expect(first.played == 256)
        #expect(!buffer.isPrebuffering)
        #expect(first.output[0] < 0.5 * 0.05)      // fading in
        #expect(first.output[0] > 0)
        #expect(first.output[2 * 200] == 0.5)      // faded in after 96 frames
        #expect(buffer.bufferedFrames == 3072 - 256)
    }

    @Test("Running dry fades out, plays silence and prebuffers again")
    func underrun() {
        var buffer = MirrorAudioJitterBuffer(channels: 1, sampleRate: 48_000)
        buffer.push(samples(frames: 3000, channels: 1))
        _ = pull(&buffer, frames: 2900)
        let dry = pull(&buffer, frames: 256)
        #expect(dry.played == 100)
        #expect(dry.output[99] < 0.5 * 0.1)        // faded out
        #expect(dry.output[100...].allSatisfy { $0 == 0 })
        #expect(buffer.isPrebuffering)
        #expect(buffer.takeCounts().underruns == 1)
        // Nothing plays until 60 ms is back.
        buffer.push(samples(frames: 1000, channels: 1))
        #expect(pull(&buffer, frames: 128).played == 0)
    }

    @Test("A burst above target + headroom is cut back to the target")
    func trimsBursts() {
        var buffer = MirrorAudioJitterBuffer(channels: 2, sampleRate: 48_000)
        // Target 60 ms (2880 frames), headroom 60 ms: cut above 5760.
        buffer.push(samples(frames: 5760))
        #expect(buffer.bufferedFrames == 5760)
        buffer.push(samples(frames: 1024))
        #expect(buffer.bufferedFrames == 2880)
        #expect(buffer.takeCounts().trimmedFrames == 5760 + 1024 - 2880)
        #expect(abs(buffer.bufferedSeconds - 0.06) < 1e-9)
    }

    @Test("The buffer never grows, whatever is pushed")
    func bounded() {
        var buffer = MirrorAudioJitterBuffer(channels: 2, sampleRate: 48_000)
        for _ in 0..<500 { buffer.push(samples(frames: 1024)) }
        #expect(buffer.bufferedSeconds <= buffer.policy.maximumTarget + buffer.policy.headroom + 1e-9)
        buffer.push(samples(frames: 200_000))
        #expect(buffer.bufferedSeconds <= buffer.capacitySeconds)
        #expect(buffer.bufferedFrames <= Int((buffer.target + buffer.policy.headroom) * 48_000) + 1)
    }

    @Test("Audio comes out in order across the ring's wrap")
    func orderAcrossWrap() {
        var buffer = MirrorAudioJitterBuffer(channels: 1, sampleRate: 1_000, policy: MirrorAudioJitterPolicy(minimumTarget: 0.01, maximumTarget: 0.02, headroom: 0.1, fadeFrames: 0))
        var next: Float = 0
        var expected: Float = 0
        for _ in 0..<40 {
            let chunk = (0..<30).map { index in next + Float(index) }
            next += 30
            buffer.push(chunk)
            let out = pull(&buffer, frames: 30)
            for value in out.output.prefix(out.played) {
                #expect(value == expected)
                expected += 1
            }
        }
        #expect(expected > 1_000)
    }

    @Test("The target rises at once and falls slowly")
    func adaptiveTarget() {
        var buffer = MirrorAudioJitterBuffer(channels: 2, sampleRate: 48_000)
        #expect(buffer.target == 0.06)
        buffer.updateTarget(desired: 0.12, elapsed: 0.02)
        #expect(buffer.target == 0.12)
        buffer.updateTarget(desired: 0.06, elapsed: 1)
        #expect(abs(buffer.target - 0.10) < 1e-9)
        buffer.updateTarget(desired: 0.5, elapsed: 0)
        #expect(buffer.target == 0.15)
        for _ in 0..<10 { buffer.updateTarget(desired: 0, elapsed: 1) }
        #expect(buffer.target == 0.06)
    }

    @Test("Reset empties and prebuffers")
    func reset() {
        var buffer = MirrorAudioJitterBuffer(channels: 2, sampleRate: 48_000)
        buffer.push(samples(frames: 4000))
        _ = pull(&buffer, frames: 10)
        buffer.reset()
        #expect(buffer.bufferedFrames == 0)
        #expect(buffer.isPrebuffering)
    }
}

@Suite struct MirrorAudioSendingTests {
    @Test("Captured audio is cut into whole packets with sample times")
    func chunker() {
        var chunker = MirrorAudioChunker(channels: 2, framesPerPacket: 4)
        #expect(chunker.append([1, 1, 2, 2, 3, 3]).isEmpty)
        let chunks = chunker.append([4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9])  // odd sample ignored
        #expect(chunks.count == 2)
        #expect(chunks[0].samples == [1, 1, 2, 2, 3, 3, 4, 4])
        #expect(chunks[0].sampleTime == 0)
        #expect(chunks[1].samples == [5, 5, 6, 6, 7, 7, 8, 8])
        #expect(chunks[1].sampleTime == 4)
        #expect(chunker.pendingFrames == 0)
        #expect(chunker.nextSampleTime == 8)
    }

    @Test("A backlog the encoder can't clear is dropped from the oldest end")
    func chunkerBacklog() {
        var chunker = MirrorAudioChunker(channels: 1, framesPerPacket: 100, maxPendingFrames: 150)
        // 90 frames wait, then 90 more: 180 > 150, so 30 old frames go.
        _ = chunker.append([Float](repeating: 0, count: 90))
        let chunks = chunker.append([Float](repeating: 1, count: 90))
        #expect(chunks.count == 1)
        #expect(chunks[0].sampleTime == 30)
        #expect(chunker.pendingFrames == 50)
    }

    @Test("One send at a time; waiting packets go together")
    func sendQueueBatches() {
        var queue = MirrorAudioSendQueue<Int>(maxQueued: 4)
        queue.enqueue(1)
        #expect(queue.takeBatch() == [1])
        #expect(queue.isSending)
        queue.enqueue(2)
        queue.enqueue(3)
        #expect(queue.takeBatch() == nil)
        queue.sendFinished()
        #expect(queue.takeBatch() == [2, 3])
        queue.sendFinished()
        #expect(queue.takeBatch() == nil)
        #expect(queue.takeDropped() == 0)
    }

    @Test("A stalled link drops the oldest packets, never queues more")
    func sendQueueDrops() {
        var queue = MirrorAudioSendQueue<Int>(maxQueued: 4)
        queue.enqueue(0)
        _ = queue.takeBatch()
        for packet in 1...10 { queue.enqueue(packet) }
        #expect(queue.queued == [7, 8, 9, 10])
        #expect(queue.dropped == 6)
        queue.sendFinished()
        #expect(queue.takeBatch() == [7, 8, 9, 10])
        #expect(queue.takeDropped() == 6)
        #expect(queue.takeDropped() == 0)
    }
}

@Suite struct MirrorAudioStatsTests {
    @Test("The host counter reports and starts a new window")
    func hostCounter() {
        var counter = MirrorAudioHostCounter()
        counter.noteSent(packets: 47, bytes: 16_000)
        counter.noteDropped(2)
        let stats = counter.take(codec: .aacLC, elapsed: 1)
        #expect(stats == MirrorAudioHostStats(codec: .aacLC, packetsSent: 47, packetsDropped: 2, kilobitsPerSecond: 128))
        #expect(counter == MirrorAudioHostCounter())
    }

    @Test("Client stats count trimmed audio as late packets")
    func clientStats() {
        let stats = MirrorAudioClientStats.make(
            counts: (received: 40, lost: 1, late: 1),
            underruns: 2,
            trimmedFrames: 1025,
            framesPerPacket: 1024,
            bufferedSeconds: 0.0645,
            targetSeconds: 0.06,
            jitterSeconds: 0.00433
        )
        #expect(stats.packetsLate == 3)
        #expect(stats.bufferMilliseconds == 64.5)
        #expect(stats.jitterMilliseconds == 4.3)
    }

    @Test("The Mac cleans a remote's audio numbers")
    func sanitized() {
        let wild = MirrorClientStats(
            receivedFPS: 1, displayedFPS: 1, droppedFrames: 0, decodeMilliseconds: 1, kilobitsPerSecond: 1,
            audio: MirrorAudioClientStats(packetsReceived: -4, packetsLost: .max, packetsLate: 0, underruns: 0, bufferMilliseconds: .infinity, targetMilliseconds: -1, jitterMilliseconds: .nan)
        ).sanitized()
        #expect(wild.audio?.packetsReceived == 0)
        #expect(wild.audio?.packetsLost == 1_000_000)
        #expect(wild.audio?.bufferMilliseconds == 0)
        #expect(wild.audio?.targetMilliseconds == 0)
        #expect(wild.audio?.jitterMilliseconds == 0)
    }

    @Test("The stats line adds audio only while it plays")
    func statsLine() {
        let host = MirrorHostStats(codec: .hevc, width: 1440, height: 900, capturedFPS: 30, sentFPS: 30, droppedFrames: 0, encodeMilliseconds: 3, kilobitsPerSecond: 4_000)
        #expect(!MirrorStatsLine.text(host: host, client: nil).contains("Audio"))
        var withAudio = host
        withAudio.audio = MirrorAudioHostStats(codec: .aacLC, packetsSent: 47, packetsDropped: 0, kilobitsPerSecond: 131.5)
        let client = MirrorClientStats(
            receivedFPS: 30, displayedFPS: 30, droppedFrames: 0, decodeMilliseconds: 2, kilobitsPerSecond: 4_000,
            audio: MirrorAudioClientStats(packetsReceived: 47, packetsLost: 2, packetsLate: 1, underruns: 1, bufferMilliseconds: 64.4, targetMilliseconds: 60, jitterMilliseconds: 3)
        )
        let line = MirrorStatsLine.text(host: withAudio, client: client)
        #expect(line.hasSuffix("Audio AAC 132 kb/s, 64/60 ms, 2 lost, 1 late, 1 gap"))
    }
}

@Suite struct MirrorAudioLockTests {
    @Test("Audio follows the mirror's lock rule")
    func lockGate() {
        let on = ControlMessage.mirror(.audio(enabled: true))
        let off = ControlMessage.mirror(.audio(enabled: false))
        #expect(LockPolicy.decide(on, state: .unlocked) == .allow)
        #expect(LockPolicy.decide(on, state: .screenLocked) == .allow)
        #expect(LockPolicy.decide(on, state: .offConsole) == .refuse(reply: .none))
        #expect(LockPolicy.decide(off, state: .offConsole) == .allow)
        #expect(LockPolicy.decide(.mirror(.audioError(message: "x")), state: .offConsole) == .allow)
        // Same as a display mirror's start.
        let start = ControlMessage.mirror(.start(fps: 20, maxWidth: 640, displayID: nil, codec: .jpeg, windowID: nil))
        for state in [MacLockState.unlocked, .screenLocked, .offConsole] {
            #expect(LockPolicy.decide(on, state: state) == LockPolicy.decide(start, state: state))
        }
    }

    @Test("Remote input validation passes audio messages through")
    func validation() {
        let message = ControlMessage.mirror(.audio(enabled: true))
        #expect(RemoteInputValidation.sanitize(message) == message)
    }
}
