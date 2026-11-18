//
//  MirrorStats.swift
//  PixelHandCore
//
//  S6, the stream stats. Both ends count what their half of the mirror
//  does over a short window; the Mac sends its numbers to the remote
//  (`diagnostics.mirrorStats`) and the remote sends its own back
//  (`diagnostics.mirrorClientStats`). The remote's HUD and the Mac's log
//  print the same one-line summary (`MirrorStatsLine`).
//

import Foundation

/// How mirror frames are encoded.
public enum MirrorCodec: String, Codable, Sendable, CaseIterable {
    case jpeg
    /// S5.
    case hevc
}

/// The Mac's half of the mirror over the last report window.
public struct MirrorHostStats: Codable, Sendable, Equatable {
    public var codec: MirrorCodec
    /// Size of the frames being sent, in pixels.
    public var width: Int
    public var height: Int
    /// Frames ScreenCaptureKit delivered, per second.
    public var capturedFPS: Double
    /// Frames sent to this remote, per second.
    public var sentFPS: Double
    /// Frames dropped in the window: the encoder was busy, or this remote's
    /// previous frame was still on the wire.
    public var droppedFrames: Int
    /// Average time to encode one frame.
    public var encodeMilliseconds: Double
    /// Payload sent to this remote.
    public var kilobitsPerSecond: Double

    public init(codec: MirrorCodec, width: Int, height: Int, capturedFPS: Double, sentFPS: Double, droppedFrames: Int, encodeMilliseconds: Double, kilobitsPerSecond: Double) {
        self.codec = codec
        self.width = width
        self.height = height
        self.capturedFPS = capturedFPS
        self.sentFPS = sentFPS
        self.droppedFrames = droppedFrames
        self.encodeMilliseconds = encodeMilliseconds
        self.kilobitsPerSecond = kilobitsPerSecond
    }
}

/// The remote's half of the mirror over the last report window.
public struct MirrorClientStats: Codable, Sendable, Equatable {
    /// Frames that arrived, per second.
    public var receivedFPS: Double
    /// Frames that reached the screen, per second.
    public var displayedFPS: Double
    /// Frames that arrived but were replaced by a newer one before they
    /// could be decoded (newest-frame-wins).
    public var droppedFrames: Int
    /// Average time to decode one frame.
    public var decodeMilliseconds: Double
    /// Payload received.
    public var kilobitsPerSecond: Double

    public init(receivedFPS: Double, displayedFPS: Double, droppedFrames: Int, decodeMilliseconds: Double, kilobitsPerSecond: Double) {
        self.receivedFPS = receivedFPS
        self.displayedFPS = displayedFPS
        self.droppedFrames = droppedFrames
        self.decodeMilliseconds = decodeMilliseconds
        self.kilobitsPerSecond = kilobitsPerSecond
    }

    /// The Mac's check for numbers a remote sent: non-finite becomes 0,
    /// everything is clamped to a range no real stream reaches.
    public func sanitized() -> MirrorClientStats {
        func safe(_ value: Double, limit: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(max(value, 0), limit)
        }
        return MirrorClientStats(
            receivedFPS: safe(receivedFPS, limit: 1_000),
            displayedFPS: safe(displayedFPS, limit: 1_000),
            droppedFrames: min(max(droppedFrames, 0), 1_000_000),
            decodeMilliseconds: safe(decodeMilliseconds, limit: 60_000),
            kilobitsPerSecond: safe(kilobitsPerSecond, limit: 10_000_000)
        )
    }
}

/// Counts one end's mirror events between reports. Not thread-safe: keep it
/// on one actor or queue.
///
/// "In" is what arrives at this end's stage (captured on the Mac, received
/// on the remote), "out" is what leaves it (sent, displayed).
public struct MirrorStatsCounter: Sendable, Equatable {
    public private(set) var framesIn = 0
    public private(set) var framesOut = 0
    public private(set) var dropped = 0
    public private(set) var bytes = 0
    private var workSeconds = 0.0
    private var workCount = 0

    public init() {}

    public mutating func noteFrameIn(bytes: Int = 0) {
        framesIn += 1
        self.bytes += max(0, bytes)
    }

    public mutating func noteFrameOut(bytes: Int = 0) {
        framesOut += 1
        self.bytes += max(0, bytes)
    }

    public mutating func noteDropped(_ count: Int = 1) {
        dropped += max(0, count)
    }

    /// Time spent encoding (Mac) or decoding (remote) one frame.
    public mutating func noteWork(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        workSeconds += seconds
        workCount += 1
    }

    public var averageWorkMilliseconds: Double {
        workCount == 0 ? 0 : workSeconds / Double(workCount) * 1_000
    }

    public mutating func reset() {
        self = MirrorStatsCounter()
    }

    /// The Mac's report for a window of `elapsed` seconds.
    public func hostStats(codec: MirrorCodec, width: Int, height: Int, elapsed: Double) -> MirrorHostStats {
        let seconds = max(elapsed, 0.001)
        return MirrorHostStats(
            codec: codec,
            width: width,
            height: height,
            capturedFPS: Self.round1(Double(framesIn) / seconds),
            sentFPS: Self.round1(Double(framesOut) / seconds),
            droppedFrames: dropped,
            encodeMilliseconds: Self.round1(averageWorkMilliseconds),
            kilobitsPerSecond: Self.round1(Double(bytes) * 8 / 1_000 / seconds)
        )
    }

    /// The remote's report for a window of `elapsed` seconds.
    public func clientStats(elapsed: Double) -> MirrorClientStats {
        let seconds = max(elapsed, 0.001)
        return MirrorClientStats(
            receivedFPS: Self.round1(Double(framesIn) / seconds),
            displayedFPS: Self.round1(Double(framesOut) / seconds),
            droppedFrames: dropped,
            decodeMilliseconds: Self.round1(averageWorkMilliseconds),
            kilobitsPerSecond: Self.round1(Double(bytes) * 8 / 1_000 / seconds)
        )
    }

    static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// How often each end reports.
public enum MirrorStatsPolicy {
    /// Seconds between stats reports while a mirror runs.
    public static let reportInterval = 1.0
}

/// The one-line summary on the remote's HUD and in the Mac's log.
///
///     JPEG 1440×900 · Mac 20 fps, 6.1 ms, 1.2 Mb/s, 3 dropped · iPad 19.8 fps, 4.0 ms
public enum MirrorStatsLine {
    public static func text(host: MirrorHostStats?, client: MirrorClientStats?, clientName: String = "iPad") -> String {
        var parts: [String] = []
        if let host {
            parts.append("\(host.codec.rawValue.uppercased()) \(host.width)×\(host.height)")
            var mac = "Mac \(number(host.sentFPS)) fps, \(number(host.encodeMilliseconds)) ms, \(rate(host.kilobitsPerSecond))"
            if host.droppedFrames > 0 { mac += ", \(host.droppedFrames) dropped" }
            parts.append(mac)
        }
        if let client {
            var remote = "\(clientName) \(number(client.displayedFPS)) fps, \(number(client.decodeMilliseconds)) ms"
            if client.droppedFrames > 0 { remote += ", \(client.droppedFrames) skipped" }
            parts.append(remote)
        }
        return parts.isEmpty ? "Waiting for stats…" : parts.joined(separator: " · ")
    }

    /// One decimal below 10, whole numbers above.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        if value < 10 {
            let tenths = Int((value * 10).rounded())
            return "\(tenths / 10).\(tenths % 10)"
        }
        return String(Int(value.rounded()))
    }

    static func rate(_ kilobits: Double) -> String {
        guard kilobits.isFinite else { return "–" }
        if kilobits >= 1_000 { return "\(number(kilobits / 1_000)) Mb/s" }
        return "\(Int(kilobits.rounded())) kb/s"
    }
}
