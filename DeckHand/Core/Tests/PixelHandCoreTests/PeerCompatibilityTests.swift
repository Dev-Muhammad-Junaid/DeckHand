//
//  PeerCompatibilityTests.swift
//  PixelHandCoreTests
//
//  The "Please update" check that runs before connecting: Loom refuses a
//  session between different Loom protocols, and different Pixel Hand
//  protocols can't decode each other's messages, so the picker and the menu
//  bar must name the side that's behind.
//

import PixelHandCore
import Testing

@Suite struct PeerCompatibilityTests {

    @Test("Same versions are compatible")
    func sameVersionIsCompatible() {
        let compatibility = PeerCompatibility(peerLoomVersion: 3, peerAppVersion: 2, localLoomVersion: 3, localAppVersion: 2)
        #expect(compatibility == .compatible)
        #expect(compatibility.updateMessage(thisDevice: "iPad", peer: "Mac") == nil)
    }

    @Test("An older Loom protocol on the peer: the peer needs the update")
    func olderLoomPeer() {
        let compatibility = PeerCompatibility(peerLoomVersion: 2, peerAppVersion: 2, localLoomVersion: 3, localAppVersion: 2)
        #expect(compatibility == .updatePeer)
        #expect(compatibility.updateMessage(thisDevice: "iPad", peer: "Mac") == "Please update Pixel Hand on your Mac")
    }

    @Test("A newer Loom protocol on the peer: this device needs the update")
    func newerLoomPeer() {
        let compatibility = PeerCompatibility(peerLoomVersion: 4, peerAppVersion: 2, localLoomVersion: 3, localAppVersion: 2)
        #expect(compatibility == .updateThisDevice)
        #expect(compatibility.updateMessage(thisDevice: "iPad", peer: "Mac") == "Please update Pixel Hand on your iPad")
    }

    @Test("Same Loom, different app protocol")
    func appProtocolMismatch() {
        #expect(PeerCompatibility(peerLoomVersion: 3, peerAppVersion: 1, localLoomVersion: 3, localAppVersion: 2) == .updatePeer)
        #expect(PeerCompatibility(peerLoomVersion: 3, peerAppVersion: 3, localLoomVersion: 3, localAppVersion: 2) == .updateThisDevice)
    }

    @Test("The Loom protocol decides first, whatever the app protocol says")
    func loomDecidesFirst() {
        #expect(PeerCompatibility(peerLoomVersion: 2, peerAppVersion: 9, localLoomVersion: 3, localAppVersion: 2) == .updatePeer)
        #expect(PeerCompatibility(peerLoomVersion: 4, peerAppVersion: 1, localLoomVersion: 3, localAppVersion: 2) == .updateThisDevice)
    }

    @Test("A peer that didn't advertise ph-proto isn't blocked")
    func missingAppVersionIsCompatible() {
        #expect(PeerCompatibility(peerLoomVersion: 3, peerAppVersion: nil, localLoomVersion: 3) == .compatible)
    }

    @Test("The default local app version is this build's")
    func defaultLocalVersion() {
        #expect(PeerCompatibility(peerLoomVersion: 1, peerAppVersion: PixelHandProtocol.version, localLoomVersion: 1) == .compatible)
        #expect(PeerCompatibility(peerLoomVersion: 1, peerAppVersion: PixelHandProtocol.version + 1, localLoomVersion: 1) == .updateThisDevice)
    }
}
