//
//  SessionMessage.swift
//  PixelHandCore
//
//  Domain: session and liveness. Heartbeats, and what the host can do right
//  now. Both ways. Owned by the network lane (S1's keep-alive tick replaces
//  or joins `ping` here) together with `SessionHandler`.
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
    /// Reserved for S5: the host can stream the mirror on its own binary
    /// Loom stream (`PixelHandStream.mirror`, `BinaryFrameHeader`).
    case binaryMirrorStream
}
