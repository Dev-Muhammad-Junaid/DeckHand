//
//  KeepAlivePolicy.swift
//  PixelHandCore
//
//  S1: the remote's Wi-Fi radio dozes between packets. With only a 2 s ping
//  the round trip sawtooths from ~5 ms to ~300 ms as packets wait for the
//  radio's next wake-up. A tiny `session.tick` a few times a second keeps
//  it awake while the session is in front. Nothing is sent in the
//  background, and the liveness clock restarts on the way back, so the time
//  spent suspended doesn't count as the Mac's silence.
//

import Foundation

public enum KeepAlivePolicy {
    /// Ticks while in front, on a link that dozes. Four a second keeps the
    /// radio's power-save timer from expiring between ticks.
    public static let tickInterval: TimeInterval = 0.25

    /// Whether to tick, given this side's link and the peer's report.
    public static func needsTick(local: LinkKind, peer: LinkKind?) -> Bool {
        // Either side seeing the cable means no radio is involved.
        if local == .wired || peer == .wired { return false }
        return local.dozes
    }
}

/// The remote's keep-alive state: in front or not, and the link. Value type,
/// so the transitions are tested here.
public struct KeepAliveGate: Sendable, Equatable {
    public enum Transition: Sendable, Equatable {
        case none
        /// Stop ticking and pinging.
        case paused
        /// Restart the liveness clock, ping at once, resume ticking.
        case resumed
    }

    public private(set) var isForeground: Bool
    public private(set) var localLink: LinkKind
    public private(set) var peerLink: LinkKind?

    public init(isForeground: Bool = true, localLink: LinkKind = .unknown, peerLink: LinkKind? = nil) {
        self.isForeground = isForeground
        self.localLink = localLink
        self.peerLink = peerLink
    }

    /// Ticks go out now.
    public var isTicking: Bool {
        isForeground && KeepAlivePolicy.needsTick(local: localLink, peer: peerLink)
    }

    /// Pings (and the liveness check) run now.
    public var isPinging: Bool { isForeground }

    /// What to show for the session's link.
    public var displayedLink: LinkKind {
        LinkJudge.merged(local: localLink, peer: peerLink)
    }

    public mutating func setForeground(_ foreground: Bool) -> Transition {
        guard foreground != isForeground else { return .none }
        isForeground = foreground
        return foreground ? .resumed : .paused
    }

    public mutating func setLocalLink(_ link: LinkKind) {
        localLink = link
    }

    public mutating func setPeerLink(_ link: LinkKind?) {
        peerLink = link
    }
}
