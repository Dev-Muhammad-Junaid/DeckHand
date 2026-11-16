//
//  PeerCompatibility.swift
//  Pixel Hand – Shared
//
//  Whether a discovered device can connect to this one, decided before
//  dialling. Loom's session hello requires both ends to run the same
//  `Loom.protocolVersion`, and a mismatch fails the handshake with a generic
//  error. Every Loom device already announces its version in its Bonjour TXT
//  record (`proto`), surfaced as `LoomPeerAdvertisement.protocolVersion`, so
//  the app can compare first and tell the user which side to update.
//

import Loom

enum PeerCompatibility: Equatable, Sendable {
    /// Same Loom protocol on both ends.
    case compatible
    /// The other device runs a newer protocol: this device needs the update.
    case updateThisDevice
    /// The other device runs an older protocol: it needs the update.
    case updatePeer

    /// This build's Loom protocol version.
    static let localProtocolVersion = Int(Loom.protocolVersion)

    init(peerProtocolVersion: Int, localProtocolVersion: Int = PeerCompatibility.localProtocolVersion) {
        if peerProtocolVersion == localProtocolVersion {
            self = .compatible
        } else if peerProtocolVersion > localProtocolVersion {
            self = .updateThisDevice
        } else {
            self = .updatePeer
        }
    }

    init(advertisement: LoomPeerAdvertisement) {
        self.init(peerProtocolVersion: advertisement.protocolVersion)
    }

    var isCompatible: Bool { self == .compatible }

    /// The line to show, from the point of view of `thisDevice`, about a
    /// `peer`. For example, on an iPad looking at an older Mac:
    /// "Please update Pixel Hand on your Mac".
    func updateMessage(thisDevice: String, peer: String) -> String? {
        switch self {
        case .compatible: nil
        case .updateThisDevice: "Please update Pixel Hand on your \(thisDevice)"
        case .updatePeer: "Please update Pixel Hand on your \(peer)"
        }
    }
}
