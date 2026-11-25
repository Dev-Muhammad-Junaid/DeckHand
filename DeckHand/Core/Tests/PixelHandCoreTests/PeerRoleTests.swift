//
//  PeerRoleTests.swift
//  PixelHandCoreTests
//

import Testing
@testable import PixelHandCore

@Suite("PeerRole: only Macs are listed as Macs")
struct PeerRoleTests {

    @Test("Each app advertises its role next to the protocol version")
    func advertisement() {
        let mac = PixelHandProtocol.advertisementMetadata(role: .mac)
        let remote = PixelHandProtocol.advertisementMetadata(role: .remote)
        #expect(mac == ["ph-proto": String(PixelHandProtocol.version), "ph-role": "mac"])
        #expect(remote["ph-role"] == "remote")
        #expect(PeerRole.advertised(in: mac) == .mac)
        #expect(PeerRole.advertised(in: remote) == .remote)
        #expect(PeerRole.advertised(in: ["ph-role": " MAC "]) == .mac)
        #expect(PeerRole.advertised(in: ["ph-role": "toaster"]) == nil)
        #expect(PeerRole.advertised(in: [:]) == nil)
        #expect(PeerRole.advertisementKey.utf8.count <= 9)
    }

    @Test("Another iPad or iPhone is never listed as a Mac (build 19)")
    func iOSDevicesAreNotMacs() {
        // A build 18 iPad: no role key, Loom says iPad (the iPad Pro in the
        // iPad mini's picker).
        let build18 = PixelHandProtocol.advertisementMetadata
        for type in ["iPad", "iPhone", "vision", "ipad"] {
            #expect(!PeerRole.isListedAsMac(metadata: build18, deviceType: type), "\(type)")
            #expect(!PeerRole.isListedAsMac(metadata: [:], deviceType: type), "\(type)")
        }
        // A remote with the role key says so, whatever the device type.
        let remote = PixelHandProtocol.advertisementMetadata(role: .remote)
        for type in ["iPad", "iPhone", "mac", "unknown", nil] as [String?] {
            #expect(!PeerRole.isListedAsMac(metadata: remote, deviceType: type))
        }
    }

    @Test("Macs are listed, with or without the role key")
    func macsAreListed() {
        let mac = PixelHandProtocol.advertisementMetadata(role: .mac)
        #expect(PeerRole.isListedAsMac(metadata: mac, deviceType: "mac"))
        #expect(PeerRole.isListedAsMac(metadata: mac, deviceType: "unknown"))
        #expect(PeerRole.isListedAsMac(metadata: mac, deviceType: nil))
        // A build 18 Mac (no role key) and a Mac seen with no type.
        #expect(PeerRole.isListedAsMac(metadata: PixelHandProtocol.advertisementMetadata, deviceType: "mac"))
        #expect(PeerRole.isListedAsMac(metadata: [:], deviceType: "unknown"))
        #expect(PeerRole.isListedAsMac(metadata: [:], deviceType: nil))
    }

    @Test("A role claiming mac never lists an iOS device; an unknown role is not listed")
    func eitherSignalRulesOut() {
        #expect(!PeerRole.isListedAsMac(metadata: ["ph-role": "mac"], deviceType: "iPad"))
        #expect(!PeerRole.isListedAsMac(metadata: ["ph-role": "mac"], deviceType: "iPhone"))
        #expect(!PeerRole.isListedAsMac(metadata: ["ph-role": "something-new"], deviceType: "mac"))
    }
}
