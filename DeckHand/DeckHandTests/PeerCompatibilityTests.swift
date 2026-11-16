//
//  PeerCompatibilityTests.swift
//  DeckHandTests
//
//  The "Please update" check that runs before connecting. Loom refuses a
//  session between different protocol versions, so the picker and the menu
//  bar must name the side that's behind.
//

import Loom
import XCTest

final class PeerCompatibilityTests: XCTestCase {
    func testSameVersionIsCompatible() {
        let compatibility = PeerCompatibility(peerProtocolVersion: 3, localProtocolVersion: 3)
        XCTAssertEqual(compatibility, .compatible)
        XCTAssertNil(compatibility.updateMessage(thisDevice: "iPad", peer: "Mac"))
    }

    func testOlderPeerNeedsTheUpdate() {
        let compatibility = PeerCompatibility(peerProtocolVersion: 2, localProtocolVersion: 3)
        XCTAssertEqual(compatibility, .updatePeer)
        XCTAssertEqual(
            compatibility.updateMessage(thisDevice: "iPad", peer: "Mac"),
            "Please update Pixel Hand on your Mac"
        )
    }

    func testNewerPeerMeansThisDeviceNeedsTheUpdate() {
        let compatibility = PeerCompatibility(peerProtocolVersion: 4, localProtocolVersion: 3)
        XCTAssertEqual(compatibility, .updateThisDevice)
        XCTAssertEqual(
            compatibility.updateMessage(thisDevice: "iPad", peer: "Mac"),
            "Please update Pixel Hand on your iPad"
        )
    }

    func testAdvertisementFromThisBuildIsCompatible() {
        // LoomPeerAdvertisement defaults to this build's Loom.protocolVersion.
        let advertisement = LoomPeerAdvertisement()
        XCTAssertEqual(PeerCompatibility(advertisement: advertisement), .compatible)
        XCTAssertEqual(PeerCompatibility.localProtocolVersion, Int(Loom.protocolVersion))
    }
}
