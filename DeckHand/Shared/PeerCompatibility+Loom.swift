//
//  PeerCompatibility+Loom.swift
//  Pixel Hand – Shared
//
//  Feeds a discovered device's Bonjour advertisement into PixelHandCore's
//  `PeerCompatibility`. Both the Loom protocol (`proto`) and the Pixel Hand
//  protocol (`ph-proto`) are compared before dialling; see
//  `PixelHandProtocol` for why there are two.
//

import Loom

extension PeerCompatibility {
    /// This build's Loom protocol version.
    static let localProtocolVersion = Int(Loom.protocolVersion)

    init(advertisement: LoomPeerAdvertisement) {
        self.init(
            peerLoomVersion: advertisement.protocolVersion,
            peerAppVersion: PixelHandProtocol.advertisedVersion(in: advertisement.metadata),
            localLoomVersion: Self.localProtocolVersion
        )
    }
}
