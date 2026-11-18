//
//  Liveness.swift
//  PixelHandCore
//
//  How each side decides the other is gone.
//
//  Build 1 dropped the iPad after a couple of minutes. Both sides measured
//  liveness from work done on the main actor: the iPad only counted pongs,
//  which it handled in its main-actor message loop, and the Mac answered
//  pings and stamped activity from its main-actor message loop, behind AX
//  tree walks (40–50 ms) and cursor injection. A few seconds of main-actor
//  contention on either side, or a pong queued behind mirror frames, read
//  as a dead peer.
//
//  Now:
//  - any message from the peer counts as a sign of life, not only pongs or
//    pings;
//  - the Mac answers pings as they arrive, off the main actor
//    (`HeartbeatResponder`);
//  - if the side doing the checking was itself stalled (suspended, asleep,
//    main thread blocked), the silence clock restarts instead of blaming
//    the peer;
//  - whichever side gives up logs why, with the numbers.
//
//  On the wire: `session.ping(seq)` and `session.pong(seq)`.
//

import Foundation

/// Pure liveness bookkeeping for one connection. Value type, so it is
/// tested without clocks or tasks.
public struct LivenessMonitor: Sendable, Equatable {
    public enum Verdict: Equatable, Sendable {
        /// The peer has never sent a heartbeat message, so it may be a build
        /// that doesn't speak ping; the timeout isn't enforced.
        case notEstablished
        case alive
        /// The checker itself woke up `gap` seconds after its last check, so
        /// the silence clock was restarted.
        case localStall(gap: TimeInterval)
        /// Nothing at all from the peer for `silence` seconds.
        case dead(silence: TimeInterval, sinceHeartbeat: TimeInterval)
    }

    /// Silence after which the peer counts as gone.
    public let timeout: TimeInterval
    /// A gap between two checks longer than this means the checker stalled.
    public let stallThreshold: TimeInterval

    public private(set) var lastInboundAt: Date
    public private(set) var lastHeartbeatAt: Date?
    public private(set) var lastCheckAt: Date?
    public private(set) var inboundCount: UInt64 = 0

    public var isEstablished: Bool { lastHeartbeatAt != nil }

    public init(timeout: TimeInterval, stallThreshold: TimeInterval, now: Date = Date()) {
        self.timeout = timeout
        self.stallThreshold = stallThreshold
        self.lastInboundAt = now
    }

    /// Any message from the peer.
    public mutating func noteInbound(at now: Date = Date()) {
        if now > lastInboundAt { lastInboundAt = now }
        inboundCount &+= 1
    }

    /// A ping (on the Mac) or a pong (on the iPad). Also counts as inbound.
    public mutating func noteHeartbeat(at now: Date = Date()) {
        noteInbound(at: now)
        lastHeartbeatAt = now
    }

    /// Run periodically by the side doing the checking.
    public mutating func check(at now: Date = Date()) -> Verdict {
        defer { lastCheckAt = now }
        if let lastCheckAt {
            let gap = now.timeIntervalSince(lastCheckAt)
            if gap > stallThreshold {
                // Our own side wasn't running. Whatever the peer sent in the
                // meantime may still be queued unread, so start counting
                // again from now.
                if now > lastInboundAt { lastInboundAt = now }
                return .localStall(gap: gap)
            }
        }
        guard let lastHeartbeatAt else { return .notEstablished }
        let silence = now.timeIntervalSince(lastInboundAt)
        guard silence > timeout else { return .alive }
        return .dead(silence: silence, sinceHeartbeat: now.timeIntervalSince(lastHeartbeatAt))
    }
}

/// Timings for both sides. The Mac waits longer than the iPad, so in a
/// symmetric failure the iPad, which has the UI to explain it, gives up
/// first.
public enum LivenessPolicy {
    /// The iPad pings this often.
    public static let pingInterval: TimeInterval = 2
    /// iPad: no traffic from the Mac for this long means it's gone. Was 6 s
    /// of pong silence.
    public static let remoteTimeout: TimeInterval = 10
    /// iPad: a check this late means the iPad itself stalled.
    public static let remoteStallThreshold: TimeInterval = 5
    /// Mac: no traffic from the iPad for this long means it's gone. Was 8 s.
    public static let hostTimeout: TimeInterval = 15
    /// Mac: how often the sweep runs.
    public static let hostSweepInterval: TimeInterval = 3
    /// Mac: a sweep this late means the Mac itself stalled (or slept).
    public static let hostStallThreshold: TimeInterval = 8

    public static func remoteMonitor(now: Date = Date()) -> LivenessMonitor {
        LivenessMonitor(timeout: remoteTimeout, stallThreshold: remoteStallThreshold, now: now)
    }

    public static func hostMonitor(now: Date = Date()) -> LivenessMonitor {
        LivenessMonitor(timeout: hostTimeout, stallThreshold: hostStallThreshold, now: now)
    }
}

/// A `LivenessMonitor` that any thread or actor can update. Inbound traffic
/// is stamped from wherever it is read, without hopping to the main actor.
public final class LivenessClock: @unchecked Sendable {
    private let lock = NSLock()
    private var monitor: LivenessMonitor
    private var didGiveUp = false

    /// Set by the side that declared the peer dead, so the end-of-stream
    /// log can tell "we gave up" from "the peer closed it".
    public var gaveUp: Bool {
        lock.lock(); defer { lock.unlock() }
        return didGiveUp
    }

    public func markGaveUp() {
        lock.lock(); defer { lock.unlock() }
        didGiveUp = true
    }

    public init(_ monitor: LivenessMonitor) {
        self.monitor = monitor
    }

    public func noteInbound(at now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        monitor.noteInbound(at: now)
    }

    public func noteHeartbeat(at now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        monitor.noteHeartbeat(at: now)
    }

    public func check(at now: Date = Date()) -> LivenessMonitor.Verdict {
        lock.lock(); defer { lock.unlock() }
        return monitor.check(at: now)
    }

    public var snapshot: LivenessMonitor {
        lock.lock(); defer { lock.unlock() }
        return monitor
    }
}

/// Answers pings as they arrive, before the main-actor message loop sees
/// them, and stamps every message on a `LivenessClock`.
public enum HeartbeatResponder {
    /// An encoded ping is under 60 bytes. Larger messages are never decoded
    /// here, so input and other traffic pass through untouched.
    public static let maxPingBytes = 96

    /// The ping's sequence number, if `data` is a ping.
    public static func pingSequence(in data: Data) -> UInt64? {
        guard data.count <= maxPingBytes,
              let message = try? ControlMessageCoding.decode(data),
              case let .session(.ping(seq)) = message
        else { return nil }
        return seq
    }

    /// Reads `source` off the main actor and republishes it, in order, as
    /// the returned stream. Every message is stamped on `clock`; pings are
    /// also answered at once through `reply` and still passed on, so the
    /// loop can do its periodic work on them.
    public static func relay(
        _ source: AsyncStream<Data>,
        clock: LivenessClock,
        reply: @escaping @Sendable (UInt64) async -> Void
    ) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        let pump = Task.detached(priority: .userInitiated) {
            for await data in source {
                if let seq = pingSequence(in: data) {
                    clock.noteHeartbeat()
                    // Its own task: a slow send must not hold up input.
                    Task.detached(priority: .userInitiated) { await reply(seq) }
                } else {
                    clock.noteInbound()
                }
                continuation.yield(data)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in pump.cancel() }
        return stream
    }
}
