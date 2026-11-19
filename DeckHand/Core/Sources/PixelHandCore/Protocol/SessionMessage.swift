//
//  SessionMessage.swift
//  PixelHandCore
//
//  Domain: session and liveness. Heartbeats, the Wi-Fi keep-alive tick, the
//  link the session runs over, the Mac's VPN addresses, and what the host
//  can do right now. Both
//  ways. Owned by the network lane together with `SessionHandler`.
//

import Foundation

public enum SessionMessage: Codable, Sendable, Equatable {
    /// Remote → Mac, every `LivenessPolicy.pingInterval` while a session is
    /// up. The Mac answers off its main actor (`HeartbeatResponder`).
    case ping(seq: UInt64)
    /// Mac → remote: the answer to `ping`.
    case pong(seq: UInt64)
    /// Mac → remote: what the host can execute right now and which optional
    /// features it speaks. Sent at session start and with every 5th ping,
    /// so a permission granted mid-session reaches the remote's banner.
    /// Replaces version 1's `hostCapabilities` and `hostFeatures`.
    case hostStatus(status: HostStatus)
    /// Remote → Mac, every `KeepAlivePolicy.tickInterval` while a session is
    /// in front on a link that dozes (Wi-Fi). Carries nothing and needs no
    /// answer: its only job is to keep the remote's radio out of power save,
    /// which otherwise turns a 5 ms round trip into a 5–300 ms sawtooth.
    /// The Mac stamps it as a sign of life off its main actor and drops it
    /// there (`HeartbeatResponder`); handlers never see it.
    case tick
    /// Mac → remote: how the Mac judges the link carrying this session
    /// (`LinkJudge`), for example `.wired` over a USB cable. Sent once the
    /// path is known and again whenever the judgement changes.
    case link(kind: LinkKind)
    /// Mac → remote, to a paired remote only: the Mac's own addresses on a
    /// VPN or overlay network (Tailscale and other tunnel interfaces), at
    /// most `RemoteAccessPolicy.maxReportedHosts`, so the remote can reach
    /// it later when Bonjour can't see it (S15). Sent once per session and
    /// again when they change; an empty list clears what the remote saved
    /// from earlier reports. The remote re-validates every entry
    /// (`RemoteHost.parse`) and keeps them only for a paired Mac.
    case remoteHosts(hosts: [String])
}

/// The Mac's permissions and optional protocol features.
public struct HostStatus: Codable, Sendable, Equatable {
    /// Accessibility is granted: input, shortcuts, dialog and menu reading work.
    public var accessibility: Bool
    /// Screen Recording is granted: captures and the mirror work.
    public var screenRecording: Bool
    /// Optional features this host build supports, sorted.
    public var features: [ProtocolFeature]

    public init(accessibility: Bool, screenRecording: Bool, features: [ProtocolFeature]) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.features = features.sorted { $0.rawValue < $1.rawValue }
    }

    public func supports(_ feature: ProtocolFeature) -> Bool {
        features.contains(feature)
    }

    private enum CodingKeys: String, CodingKey {
        case accessibility, screenRecording, features
    }

    /// Unknown feature names are skipped rather than failing the message,
    /// so a host can announce a feature before every remote knows it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let names = try c.decode([String].self, forKey: .features)
        self.init(
            accessibility: try c.decode(Bool.self, forKey: .accessibility),
            screenRecording: try c.decode(Bool.self, forKey: .screenRecording),
            features: names.compactMap(ProtocolFeature.init(rawValue:))
        )
    }
}

/// Optional capabilities a host announces in `HostStatus`.
public enum ProtocolFeature: String, Codable, Sendable, CaseIterable {
    /// The host answers `deck.run` with `deck.receipt`.
    case commandReceipts
    /// The host sends mirror frames and the cursor on their own binary Loom
    /// stream (`PixelHandStream.mirror`, `BinaryFrameHeader`), not on the
    /// control stream, and draws no cursor into the video (S3).
    case binaryMirrorStream
}
