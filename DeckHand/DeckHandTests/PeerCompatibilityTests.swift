//
//  PeerCompatibilityTests.swift
//  DeckHandTests
//
//  The Loom side of the "Please update" check: reading both versions out of
//  a real `LoomPeerAdvertisement`. The decision itself is tested in
//  PixelHandCore (`PeerCompatibilityTests`).
//

import Foundation
import Loom
import Testing

@Suite struct PeerCompatibilityAdvertisementTests {

    @Test("An advertisement from this build is compatible")
    func thisBuildIsCompatible() {
        let advertisement = LoomPeerAdvertisement(metadata: PixelHandProtocol.advertisementMetadata)
        #expect(PeerCompatibility(advertisement: advertisement) == .compatible)
        #expect(PeerCompatibility.localProtocolVersion == Int(Loom.protocolVersion))
    }

    @Test("ph-proto survives the Bonjour TXT record")
    func appVersionSurvivesTXT() {
        let advertisement = LoomPeerAdvertisement(metadata: PixelHandProtocol.advertisementMetadata)
        let received = LoomPeerAdvertisement.from(txtRecord: advertisement.toTXTRecord())
        #expect(PixelHandProtocol.advertisedVersion(in: received.metadata) == PixelHandProtocol.version)
    }

    @Test("An older or newer app protocol names the side to update")
    func appVersionMismatch() {
        let older = LoomPeerAdvertisement(metadata: [PixelHandProtocol.advertisementKey: String(PixelHandProtocol.version - 1)])
        #expect(PeerCompatibility(advertisement: older) == .updatePeer)
        let newer = LoomPeerAdvertisement(metadata: [PixelHandProtocol.advertisementKey: String(PixelHandProtocol.version + 1)])
        #expect(PeerCompatibility(advertisement: newer) == .updateThisDevice)
    }

    @Test("A different Loom protocol still wins over the app protocol")
    func loomVersionMismatch() {
        let advertisement = LoomPeerAdvertisement(
            protocolVersion: Int(Loom.protocolVersion) + 1,
            metadata: PixelHandProtocol.advertisementMetadata
        )
        #expect(PeerCompatibility(advertisement: advertisement) == .updateThisDevice)
    }
}
