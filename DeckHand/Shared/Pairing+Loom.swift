//
//  Pairing+Loom.swift
//  Pixel Hand – Shared
//
//  Feeds what Loom's handshake proved about a peer into PixelHandCore's
//  pairing types (S4). Trust is anchored on `LoomPeerIdentity.identityKeyID`
//  and matched with the device ID that key signed; nothing a peer merely
//  advertises (Bonjour TXT, names) decides anything.
//

import Foundation
import Loom
import LoomKit

extension PairedDeviceKind {
    init(_ type: DeviceType) {
        switch type {
        case .mac: self = .mac
        case .iPad: self = .iPad
        case .iPhone: self = .iPhone
        case .vision: self = .vision
        case .unknown: self = .other
        }
    }

    /// SF Symbol for lists of paired devices.
    var systemImage: String {
        switch self {
        case .mac: "desktopcomputer"
        case .iPad: "ipad"
        case .iPhone: "iphone"
        case .vision: "visionpro"
        case .other: "questionmark.square.dashed"
        }
    }
}

extension TrustCandidate {
    /// The candidate for a peer whose identity key the handshake verified,
    /// or `nil` when it didn't (no key, or not authenticated).
    init?(identity: LoomPeerIdentity) {
        guard identity.isIdentityAuthenticated,
              let keyID = identity.identityKeyID,
              let publicKey = identity.identityPublicKey,
              LoomIdentityManager.keyID(for: publicKey) == keyID,
              TrustList.isValidIdentityKeyID(keyID) else { return nil }
        self.init(
            identityKeyID: keyID,
            deviceID: identity.deviceID,
            name: identity.name,
            kind: PairedDeviceKind(identity.deviceType)
        )
    }
}

extension LoomConnectionHandle {
    /// The peer's identity as Loom's handshake verified it, or `nil` when
    /// the session has no context (it never finished the handshake).
    func verifiedPeerIdentity() async -> LoomPeerIdentity? {
        await session.context?.peerIdentity
    }

    /// The peer as a pairing candidate: only when its identity key was
    /// verified.
    func pairingCandidate() async -> TrustCandidate? {
        guard let identity = await verifiedPeerIdentity() else { return nil }
        return TrustCandidate(identity: identity)
    }
}
