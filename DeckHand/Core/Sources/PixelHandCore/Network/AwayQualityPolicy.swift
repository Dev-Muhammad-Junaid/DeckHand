//
//  AwayQualityPolicy.swift
//  PixelHandCore
//
//  S15 "away" quality: over a VPN, or any link with a long round trip, the
//  mirror asks for less (fewer frames, a narrower picture, HEVC when the
//  device can decode it), so a tunnel's narrower pipe and longer queue
//  don't turn into seconds of lag.
//
//  This only suggests: the Mirror code passes the request it would send
//  through `adjust(_:)` and sends what comes back. Settings lower than the
//  away caps are never raised.
//

import Foundation

/// The parts of `mirror.start` the network can have an opinion on.
public struct MirrorRequestShape: Equatable, Sendable {
    public var fps: Int
    public var maxWidth: Int
    public var codec: MirrorCodec

    public init(fps: Int, maxWidth: Int, codec: MirrorCodec) {
        self.fps = fps
        self.maxWidth = maxWidth
        self.codec = codec
    }
}

public struct AwayQualityPolicy: Equatable, Sendable {
    /// A smoothed round trip at or above this is "away" even on Wi-Fi.
    public static let enterRoundTrip: TimeInterval = 0.120
    /// …and drops back to "home" only below this (hysteresis).
    public static let leaveRoundTrip: TimeInterval = 0.070

    /// Caps while away.
    public static let awayFPS = 15
    public static let awayMaxWidthHEVC = 1_280
    public static let awayMaxWidthJPEG = 960

    /// The link this session runs over (`KeepAliveGate.displayedLink`).
    public private(set) var link: LinkKind = .unknown
    /// Latched by the round trip, with hysteresis.
    public private(set) var slowRoundTrip = false

    public init() {}

    public var isAway: Bool {
        link == .tunnel || link == .cellular || slowRoundTrip
    }

    /// Returns whether `isAway` changed.
    @discardableResult
    public mutating func setLink(_ kind: LinkKind) -> Bool {
        let before = isAway
        link = kind
        return before != isAway
    }

    /// Feeds the latest smoothed round trip. Returns whether `isAway` changed.
    @discardableResult
    public mutating func noteRoundTrip(_ smoothed: TimeInterval?) -> Bool {
        guard let smoothed else { return false }
        let before = isAway
        if slowRoundTrip {
            if smoothed < Self.leaveRoundTrip { slowRoundTrip = false }
        } else if smoothed >= Self.enterRoundTrip {
            slowRoundTrip = true
        }
        return before != isAway
    }

    /// The request to send. At home it is `request` unchanged. Away: at most
    /// `awayFPS` frames, a width capped for the codec, and HEVC instead of
    /// JPEG when `hevcAvailable` (the device decodes it and the session
    /// hasn't fallen back).
    public func adjust(_ request: MirrorRequestShape, hevcAvailable: Bool) -> MirrorRequestShape {
        guard isAway else { return request }
        let codec: MirrorCodec = hevcAvailable ? .hevc : request.codec
        let widthCap = codec == .hevc ? Self.awayMaxWidthHEVC : Self.awayMaxWidthJPEG
        return MirrorRequestShape(
            fps: min(request.fps, Self.awayFPS),
            maxWidth: min(request.maxWidth, widthCap),
            codec: codec
        )
    }
}

/// Round trips from the heartbeat's ping / pong pairs, smoothed like TCP's
/// SRTT (α = 1/8). A pong for a ping it didn't see, or one older than the
/// last 16 pings, is ignored.
public struct RoundTripEstimator: Equatable, Sendable {
    public static let maxOutstanding = 16
    public static let gain = 0.125

    private var sent: [UInt64: TimeInterval] = [:]
    public private(set) var smoothed: TimeInterval?
    public private(set) var latest: TimeInterval?

    public init() {}

    public mutating func pingSent(seq: UInt64, at now: TimeInterval) {
        sent[seq] = now
        if sent.count > Self.maxOutstanding, let oldest = sent.min(by: { $0.value < $1.value })?.key {
            sent.removeValue(forKey: oldest)
        }
    }

    /// Returns the new smoothed round trip, or `nil` for an unknown pong.
    @discardableResult
    public mutating func pongReceived(seq: UInt64, at now: TimeInterval) -> TimeInterval? {
        guard let start = sent.removeValue(forKey: seq) else { return nil }
        // Pings sent before this one and still unanswered won't be: the
        // Mac answers in order.
        sent = sent.filter { $0.value > start }
        let sample = max(0, now - start)
        latest = sample
        if let s = smoothed {
            smoothed = s + Self.gain * (sample - s)
        } else {
            smoothed = sample
        }
        return smoothed
    }

    /// Forget everything (resume from background, new session).
    public mutating func reset() {
        sent = [:]
        smoothed = nil
        latest = nil
    }
}
