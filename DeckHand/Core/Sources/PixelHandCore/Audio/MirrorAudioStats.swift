//
//  MirrorAudioStats.swift
//  PixelHandCore
//
//  S17's half of the stream stats (S6). While audio plays, the Mac's
//  `diagnostics.mirrorStats` carries `MirrorHostStats.audio` and the
//  remote's `diagnostics.mirrorClientStats` carries
//  `MirrorClientStats.audio`; both are absent while audio is off.
//

import Foundation

/// The Mac's audio to one remote over the last report window.
public struct MirrorAudioHostStats: Codable, Sendable, Equatable {
    public var codec: MirrorAudioCodec
    /// Packets sent to this remote.
    public var packetsSent: Int
    /// Packets dropped because this remote's link fell behind.
    public var packetsDropped: Int
    /// Audio payload sent to this remote.
    public var kilobitsPerSecond: Double

    public init(codec: MirrorAudioCodec, packetsSent: Int, packetsDropped: Int, kilobitsPerSecond: Double) {
        self.codec = codec
        self.packetsSent = packetsSent
        self.packetsDropped = packetsDropped
        self.kilobitsPerSecond = kilobitsPerSecond
    }
}

/// The remote's audio over the last report window.
public struct MirrorAudioClientStats: Codable, Sendable, Equatable {
    /// Packets that arrived in order.
    public var packetsReceived: Int
    /// Gaps in the sequence: packets the Mac dropped.
    public var packetsLost: Int
    /// Packets thrown away for arriving too late: out of order, or cut
    /// from a burst to keep the delay down (counted in packets' worth).
    public var packetsLate: Int
    /// Times playback ran dry.
    public var underruns: Int
    /// Audio waiting to be played at the end of the window.
    public var bufferMilliseconds: Double
    /// The delay the buffer aims for.
    public var targetMilliseconds: Double
    /// Measured interarrival jitter.
    public var jitterMilliseconds: Double

    public init(packetsReceived: Int, packetsLost: Int, packetsLate: Int, underruns: Int, bufferMilliseconds: Double, targetMilliseconds: Double, jitterMilliseconds: Double) {
        self.packetsReceived = packetsReceived
        self.packetsLost = packetsLost
        self.packetsLate = packetsLate
        self.underruns = underruns
        self.bufferMilliseconds = bufferMilliseconds
        self.targetMilliseconds = targetMilliseconds
        self.jitterMilliseconds = jitterMilliseconds
    }

    /// The Mac's check for numbers a remote sent.
    public func sanitized() -> MirrorAudioClientStats {
        func count(_ value: Int) -> Int { min(max(value, 0), 1_000_000) }
        func millis(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(max(value, 0), 60_000)
        }
        return MirrorAudioClientStats(
            packetsReceived: count(packetsReceived),
            packetsLost: count(packetsLost),
            packetsLate: count(packetsLate),
            underruns: count(underruns),
            bufferMilliseconds: millis(bufferMilliseconds),
            targetMilliseconds: millis(targetMilliseconds),
            jitterMilliseconds: millis(jitterMilliseconds)
        )
    }
}

/// Counts the Mac's audio to one remote between reports.
public struct MirrorAudioHostCounter: Sendable, Equatable {
    public private(set) var packetsSent = 0
    public private(set) var packetsDropped = 0
    public private(set) var bytes = 0

    public init() {}

    public mutating func noteSent(packets: Int, bytes: Int) {
        packetsSent += max(0, packets)
        self.bytes += max(0, bytes)
    }

    public mutating func noteDropped(_ count: Int) {
        packetsDropped += max(0, count)
    }

    /// The window's stats, starting a new window.
    public mutating func take(codec: MirrorAudioCodec, elapsed: Double) -> MirrorAudioHostStats {
        let seconds = max(elapsed.isFinite ? elapsed : 0, 0.001)
        defer { self = MirrorAudioHostCounter() }
        return MirrorAudioHostStats(
            codec: codec,
            packetsSent: packetsSent,
            packetsDropped: packetsDropped,
            kilobitsPerSecond: MirrorStatsCounter.round1(Double(bytes) * 8 / 1_000 / seconds)
        )
    }
}

extension MirrorAudioClientStats {
    /// The remote's window from its sequence tracker and buffer counts.
    public static func make(
        counts: (received: Int, lost: Int, late: Int),
        underruns: Int,
        trimmedFrames: Int,
        framesPerPacket: Int,
        bufferedSeconds: Double,
        targetSeconds: Double,
        jitterSeconds: Double
    ) -> MirrorAudioClientStats {
        let trimmedPackets = framesPerPacket > 0
            ? (trimmedFrames + framesPerPacket - 1) / framesPerPacket
            : 0
        return MirrorAudioClientStats(
            packetsReceived: counts.received,
            packetsLost: counts.lost,
            packetsLate: counts.late + trimmedPackets,
            underruns: underruns,
            bufferMilliseconds: MirrorStatsCounter.round1(bufferedSeconds * 1_000),
            targetMilliseconds: MirrorStatsCounter.round1(targetSeconds * 1_000),
            jitterMilliseconds: MirrorStatsCounter.round1(jitterSeconds * 1_000)
        )
    }
}
