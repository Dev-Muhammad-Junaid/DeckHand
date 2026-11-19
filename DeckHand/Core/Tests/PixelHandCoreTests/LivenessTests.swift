//
//  LivenessTests.swift
//  PixelHandCoreTests
//
//  Build 1 dropped the iPad after a couple of minutes: the iPad only
//  counted pongs, the Mac answered pings from its busy main actor, and a
//  short stall on either side read as a dead peer.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct LivenessMonitorTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func remote() -> LivenessMonitor {
        LivenessPolicy.remoteMonitor(now: t0)
    }

    @Test func timeoutIsNotEnforcedBeforeTheFirstHeartbeat() {
        var monitor = remote()
        // Checks every 2 s for a minute with no traffic at all.
        for i in 1...30 {
            #expect(monitor.check(at: t0 + Double(i) * 2) == .notEstablished)
        }
    }

    @Test func anyTrafficKeepsThePeerAlive() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        // No pong for 30 s, but mirror frames and app updates keep coming.
        for i in 1...15 {
            let now = t0 + Double(i) * 2
            monitor.noteInbound(at: now - 0.5)
            #expect(monitor.check(at: now) == .alive, "at \(i * 2) s")
        }
    }

    @Test func oldSixSecondPongGapNoLongerKills() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        // Pongs delayed by up to 8 s behind a stalled main actor.
        #expect(monitor.check(at: t0 + 2) == .alive)
        #expect(monitor.check(at: t0 + 4) == .alive)
        #expect(monitor.check(at: t0 + 6) == .alive)
        #expect(monitor.check(at: t0 + 8) == .alive)
        monitor.noteHeartbeat(at: t0 + 8.5)
        #expect(monitor.check(at: t0 + 10) == .alive)
    }

    @Test func totalSilencePastTheTimeoutIsDead() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        var verdict = LivenessMonitor.Verdict.alive
        var now = t0
        while case .alive = verdict {
            now += 2
            verdict = monitor.check(at: now)
            #expect(now.timeIntervalSince(t0) <= 12)
        }
        #expect(verdict == .dead(silence: 12, sinceHeartbeat: 12))
    }

    @Test func localStallRestartsTheClockInsteadOfKilling() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        #expect(monitor.check(at: t0 + 2) == .alive)
        // The iPad was suspended for 20 s; its next check is very late.
        #expect(monitor.check(at: t0 + 22) == .localStall(gap: 20))
        // The peer gets a full timeout from the end of the stall.
        for seconds in stride(from: 24.0, through: 32.0, by: 2) {
            #expect(monitor.check(at: t0 + seconds) == .alive, "at \(seconds) s")
        }
        #expect(monitor.check(at: t0 + 34) == .dead(silence: 12, sinceHeartbeat: 34))
    }

    @Test func outOfOrderStampsNeverMoveTheClockBack() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0 + 5)
        monitor.noteInbound(at: t0 + 1)
        #expect(monitor.lastInboundAt == t0 + 5)
        #expect(monitor.inboundCount == 2)
    }

    @Test func theMacOutlastsTheIPad() {
        #expect(LivenessPolicy.hostTimeout > LivenessPolicy.remoteTimeout)
        #expect(LivenessPolicy.remoteTimeout >= 4 * LivenessPolicy.pingInterval)
        #expect(LivenessPolicy.remoteStallThreshold > LivenessPolicy.pingInterval)
        #expect(LivenessPolicy.hostStallThreshold > LivenessPolicy.hostSweepInterval)
        #expect(LivenessPolicy.remoteStallThreshold < LivenessPolicy.remoteTimeout)
        #expect(LivenessPolicy.hostStallThreshold < LivenessPolicy.hostTimeout)
    }

    @Test func restartForgivesTimeSpentInTheBackground() {
        var monitor = remote()
        monitor.noteHeartbeat(at: t0)
        #expect(monitor.check(at: t0 + 2) == .alive)
        // Suspended for five minutes, then back in front.
        let back = t0 + 300
        monitor.restart(at: back)
        // The first check after a restart is not a stall and not dead.
        #expect(monitor.check(at: back + 2) == .alive)
        #expect(monitor.isEstablished)
        // But real silence after coming back still counts.
        var now = back + 2
        var verdict = LivenessMonitor.Verdict.alive
        while case .alive = verdict {
            now += 2
            verdict = monitor.check(at: now)
        }
        guard case let .dead(silence, _) = verdict else {
            Issue.record("expected dead, got \(verdict)")
            return
        }
        #expect(silence > LivenessPolicy.remoteTimeout)
        #expect(now.timeIntervalSince(back) <= LivenessPolicy.remoteTimeout + 2)
    }

    @Test func clockRestartIsVisibleInTheSnapshot() {
        let clock = LivenessClock(remote())
        clock.noteHeartbeat(at: t0)
        _ = clock.check(at: t0 + 1)
        clock.restart(at: t0 + 100)
        #expect(clock.snapshot.lastInboundAt == t0 + 100)
        #expect(clock.snapshot.lastCheckAt == nil)
    }

    @Test func clockMarksWhoGaveUp() {
        let clock = LivenessClock(remote())
        #expect(!clock.gaveUp)
        clock.markGaveUp()
        #expect(clock.gaveUp)
    }
}

@Suite struct HeartbeatResponderTests {

    private func encode(_ message: ControlMessage) throws -> Data {
        try ControlMessageCoding.encoder.encode(message)
    }

    @Test func recognisesPingsOnly() throws {
        #expect(HeartbeatResponder.pingSequence(in: try encode(.session(.ping(seq: 42)))) == 42)
        #expect(HeartbeatResponder.pingSequence(in: try encode(.session(.ping(seq: .max)))) == .max)
        #expect(HeartbeatResponder.pingSequence(in: try encode(.session(.pong(seq: 42)))) == nil)
        #expect(HeartbeatResponder.pingSequence(in: try encode(.input(.mouseDelta(dx: 1, dy: 2)))) == nil)
        #expect(HeartbeatResponder.pingSequence(in: Data("not json".utf8)) == nil)
    }

    @Test func recognisesTicks() throws {
        #expect(HeartbeatResponder.heartbeat(in: try encode(.session(.tick))) == .tick)
        #expect(HeartbeatResponder.heartbeat(in: try encode(.session(.ping(seq: 3)))) == .ping(seq: 3))
        #expect(HeartbeatResponder.heartbeat(in: try encode(.session(.link(kind: .wired)))) == nil)
        #expect(HeartbeatResponder.pingSequence(in: try encode(.session(.tick))) == nil)
    }

    @Test func encodedTickIsTiny() throws {
        let tick = try encode(.session(.tick))
        #expect(tick.count <= HeartbeatResponder.maxPingBytes)
        #expect(tick.count < 40, "\(String(decoding: tick, as: UTF8.self))")
    }

    @Test func relayStampsTicksButDoesNotPassThemOn() async throws {
        let (source, input) = AsyncStream.makeStream(of: Data.self)
        let clock = LivenessClock(LivenessPolicy.hostMonitor())
        let output = HeartbeatResponder.relay(source, clock: clock) { _ in }
        let sent: [ControlMessage] = [
            .session(.tick),
            .input(.mouseDelta(dx: 1, dy: 1)),
            .session(.tick),
            .session(.tick),
            .input(.mouseClick(button: .left)),
        ]
        for message in sent { input.yield(try encode(message)) }
        input.finish()
        var received: [Data] = []
        for await data in output { received.append(data) }
        #expect(received == [try encode(sent[1]), try encode(sent[4])])
        #expect(clock.snapshot.inboundCount == 5)
        // Ticks are signs of life, not heartbeats: they don't arm the timeout.
        #expect(!clock.snapshot.isEstablished)
    }

    @Test func encodedPingFitsTheSizeLimit() throws {
        #expect(try encode(.session(.ping(seq: .max))).count <= HeartbeatResponder.maxPingBytes)
    }

    @Test func relayAnswersPingsAndPassesEverythingOnInOrder() async throws {
        let (source, input) = AsyncStream.makeStream(of: Data.self)
        let clock = LivenessClock(LivenessPolicy.hostMonitor())
        let replies = ReplyRecorder()
        let output = HeartbeatResponder.relay(source, clock: clock) { seq in
            await replies.record(seq)
        }

        let sent: [ControlMessage] = [
            .input(.mouseDelta(dx: 1, dy: 1)),
            .session(.ping(seq: 7)),
            .input(.mouseClick(button: .left)),
            .session(.ping(seq: 8)),
        ]
        for message in sent {
            input.yield(try encode(message))
        }
        input.finish()

        var received: [Data] = []
        for await data in output {
            received.append(data)
        }
        let expected = try sent.map(encode)
        #expect(received == expected)

        // Replies run in their own tasks; give them a moment.
        var waits = 0
        while await replies.values.count < 2, waits < 100 {
            try await Task.sleep(for: .milliseconds(10))
            waits += 1
        }
        let answered = await replies.values
        #expect(answered.sorted() == [7, 8])

        let state = clock.snapshot
        #expect(state.isEstablished)
        #expect(state.inboundCount == 4)
    }
}

private actor ReplyRecorder {
    private(set) var values: [UInt64] = []
    func record(_ value: UInt64) { values.append(value) }
}
