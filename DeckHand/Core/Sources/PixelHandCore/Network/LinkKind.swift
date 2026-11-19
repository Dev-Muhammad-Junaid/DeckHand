//
//  LinkKind.swift
//  PixelHandCore
//
//  What kind of link a session runs over, as judged by `LinkJudge`. Travels
//  Mac → remote in `session.link(kind:)`, so the remote can show "Wired"
//  when the Mac has confirmed the USB cable (S13).
//

import Foundation

public enum LinkKind: String, Codable, Sendable, CaseIterable {
    /// A USB cable between the Mac and the device (CDC-NCM networking).
    case wired
    /// Wired Ethernet that isn't a USB cable to the device: a LAN.
    case ethernet
    /// Wi-Fi through an access point.
    case wifi
    /// Peer-to-peer Wi-Fi (AWDL). Off by default since S1.
    case peerToPeer
    /// A VPN or tunnel interface (`utun`, `ipsec`, `ppp`). S15 builds on it.
    case tunnel
    case cellular
    /// Both ends on this machine.
    case loopback
    /// A link that is up but fits none of the above.
    case other
    /// Not judged yet.
    case unknown

    /// The radio on this link can doze between packets, so a quiet session
    /// sees latency spikes unless something keeps it awake (the keep-alive
    /// tick). Unknown links are treated as dozing: a few bytes a second is
    /// cheaper than a 300 ms stall.
    public var dozes: Bool {
        switch self {
        case .wired, .ethernet, .loopback: false
        case .wifi, .peerToPeer, .tunnel, .cellular, .other, .unknown: true
        }
    }

    /// Short label for status rows and badges.
    public var displayName: String {
        switch self {
        case .wired: "Wired"
        case .ethernet: "Ethernet"
        case .wifi: "Wi-Fi"
        case .peerToPeer: "Direct"
        case .tunnel: "VPN"
        case .cellular: "Cellular"
        case .loopback: "This device"
        case .other: "Network"
        case .unknown: "Checking…"
        }
    }

    /// SF Symbol for the link.
    public var systemImage: String {
        switch self {
        case .wired: "cable.connector"
        case .ethernet: "network"
        case .wifi: "wifi"
        case .peerToPeer: "antenna.radiowaves.left.and.right"
        case .tunnel: "lock.shield"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .loopback: "laptopcomputer"
        case .other: "network"
        case .unknown: "questionmark.circle"
        }
    }

    /// A kind added by a newer peer decodes as `.other` instead of failing
    /// the whole message.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LinkKind(rawValue: raw) ?? .other
    }
}
