//
//  LivenessTests.swift
//  DeckHandTests
//
//  Build 1 dropped the iPad after a couple of minutes: the iPad only
//  counted pongs, the Mac answered pings from its busy main actor, and a
//  short stall on either side read as a dead peer.
//

import XCTest

final class LivenessMonitorTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func remote() -> LivenessMonitor {
        LivenessPolicy.remoteMonitor(now: t0)
    }

    func testTimeoutIsNotEnforcedBeforeTheFirstHeartbeat() {
        var monitor = remote()
        // Checks every 2 s for a minute with no traffic at all.
        for i in 1...30 {
            XCTAssertEqual(monitor.check(at: t0 + Double(i) * 2), .notEstablished)
        }
    }

    func testAnyTrafficKeepsThePeerAlive() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        // No pong for 30 s, but mirror frames and app updates keep coming.
        for i in 1...15 {
            let now = t0 + Double(i) * 2
            monitor.noteInbound(at: now - 0.5)
            XCTAssertEqual(monitor.check(at: now), .alive, "at \(i * 2) s")
        }
    }

    func testOldSixSecondPongGapNoLongerKills() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        // Pongs delayed by up to 8 s behind a stalled main actor.
        XCTAssertEqual(monitor.check(at: t0 + 2), .alive)
        XCTAssertEqual(monitor.check(at: t0 + 4), .alive)
        XCTAssertEqual(monitor.check(at: t0 + 6), .alive)
        XCTAssertEqual(monitor.check(at: t0 + 8), .alive)
        monitor.noteHeartbeat(at: t0 + 8.5)
        XCTAssertEqual(monitor.check(at: t0 + 10), .alive)
    }

    func testTotalSilencePastTheTimeoutIsDead() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        var verdict = LivenessMonitor.Verdict.alive
        var now = t0
        while case .alive = verdict {
            now += 2
            verdict = monitor.check(at: now)
            XCTAssertLessThanOrEqual(now.timeIntervalSince(t0), 12)
        }
        XCTAssertEqual(verdict, .dead(silence: 12, sinceHeartbeat: 12))
    }

    func testLocalStallRestartsTheClockInsteadOfKilling() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        XCTAssertEqual(monitor.check(at: t0 + 2), .alive)
        // The iPad was suspended for 20 s; its next check is very late.
        XCTAssertEqual(monitor.check(at: t0 + 22), .localStall(gap: 20))
        // The peer gets a full timeout from the end of the stall.
        for seconds in stride(from: 24.0, through: 32.0, by: 2) {
            XCTAssertEqual(monitor.check(at: t0 + seconds), .alive, "at \(seconds) s")
        }
        XCTAssertEqual(monitor.check(at: t0 + 34), .dead(silence: 12, sinceHeartbeat: 34))
    }

    func testOutOfOrderStampsNeverMoveTheClockBack() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0 + 5)
        monitor.noteInbound(at: t0 + 1)
        XCTAssertEqual(monitor.lastInboundAt, t0 + 5)
        XCTAssertEqual(monitor.inboundCount, 2)
    }

    func testTheMacOutlastsTheIPad() {
        XCTAssertGreaterThan(LivenessPolicy.hostTimeout, LivenessPolicy.remoteTimeout)
        XCTAssertGreaterThanOrEqual(LivenessPolicy.remoteTimeout, 4 * LivenessPolicy.pingInterval)
        XCTAssertGreaterThan(LivenessPolicy.remoteStallThreshold, LivenessPolicy.pingInterval)
        XCTAssertGreaterThan(LivenessPolicy.hostStallThreshold, LivenessPolicy.hostSweepInterval)
        XCTAssertLessThan(LivenessPolicy.remoteStallThreshold, LivenessPolicy.remoteTimeout)
        XCTAssertLessThan(LivenessPolicy.hostStallThreshold, LivenessPolicy.hostTimeout)
    }

    func testClockMarksWhoGaveUp() {
        let clock = LivenessClock(remote())
        XCTAssertFalse(clock.gaveUp)
        clock.markGaveUp()
        XCTAssertTrue(clock.gaveUp)
    }
}

final class HeartbeatResponderTests: XCTestCase {

    private func encode(_ message: ControlMessage) throws -> Data {
        try ControlMessageCoding.encoder.encode(message)
    }

    func testRecognisesPingsOnly() throws {
        XCTAssertEqual(HeartbeatResponder.pingSequence(in: try encode(.ping(seq: 42))), 42)
        XCTAssertEqual(HeartbeatResponder.pingSequence(in: try encode(.ping(seq: .max))), .max)
        XCTAssertNil(HeartbeatResponder.pingSequence(in: try encode(.pong(seq: 42))))
        XCTAssertNil(HeartbeatResponder.pingSequence(in: try encode(.mouseDelta(dx: 1, dy: 2))))
        XCTAssertNil(HeartbeatResponder.pingSequence(in: Data("not json".utf8)))
    }

    func testEncodedPingFitsTheSizeLimit() throws {
        XCTAssertLessThanOrEqual(try encode(.ping(seq: .max)).count, HeartbeatResponder.maxPingBytes)
    }

    func testRelayAnswersPingsAndPassesEverythingOnInOrder() async throws {
        let (source, input) = AsyncStream.makeStream(of: Data.self)
        let clock = LivenessClock(LivenessPolicy.hostMonitor())
        let replies = ReplyRecorder()
        let output = HeartbeatResponder.relay(source, clock: clock) { seq in
            await replies.record(seq)
        }

        let sent: [ControlMessage] = [
            .mouseDelta(dx: 1, dy: 1),
            .ping(seq: 7),
            .mouseClick(button: .left),
            .ping(seq: 8),
        ]
        for message in sent {
            input.yield(try encode(message))
        }
        input.finish()

        var received: [Data] = []
        for await data in output {
            received.append(data)
        }
        XCTAssertEqual(received, try sent.map(encode))

        // Replies run in their own tasks; give them a moment.
        var waits = 0
        while await replies.values.count < 2, waits < 100 {
            try await Task.sleep(for: .milliseconds(10))
            waits += 1
        }
        let answered = await replies.values
        XCTAssertEqual(answered.sorted(), [7, 8])

        let state = clock.snapshot
        XCTAssertTrue(state.isEstablished)
        XCTAssertEqual(state.inboundCount, 4)
    }
}

private actor ReplyRecorder {
    private(set) var values: [UInt64] = []
    func record(_ value: UInt64) { values.append(value) }
}
