//
//  NetworkLinkTests.swift
//  PixelHandCoreTests
//
//  S1 (keep-alive tick) and S13 (link judge, USB "Wired" detection).
//

import Foundation
import PixelHandCore
import Testing

@Suite struct LinkJudgeTests {

    @Test func usbTetherConfirmedByIOKitIsWired() {
        let o = LinkObservation(interfaceName: "en7", usesWiredEthernet: true, remoteHost: "169.254.10.2", isUSBTether: true)
        #expect(LinkJudge.judge(o) == .wired)
    }

    @Test func wiredLANWhenIOKitSaysNotATether() {
        // The Mac checked: a link-local peer on a real Ethernet port is a LAN.
        let o = LinkObservation(interfaceName: "en0", usesWiredEthernet: true, remoteHost: "169.254.10.2", isUSBTether: false)
        #expect(LinkJudge.judge(o) == .ethernet)
    }

    @Test func remoteInfersTheCableFromALinkLocalWiredPeer() {
        // The iPad has no IOKit: wired + link-local peer means the cable.
        let v4 = LinkObservation(interfaceName: "en2", usesWiredEthernet: true, remoteHost: "169.254.1.1")
        let v6 = LinkObservation(interfaceName: "en2", usesWiredEthernet: true, remoteHost: "fe80::1c2b:3aff:fe11:2233%en2")
        let other = LinkObservation(interfaceName: "anpi0", usesOther: true, remoteHost: "fe80::1%anpi0")
        #expect(LinkJudge.judge(v4) == .wired)
        #expect(LinkJudge.judge(v6) == .wired)
        #expect(LinkJudge.judge(other) == .wired)
    }

    @Test func routableWiredPeerIsEthernet() {
        let o = LinkObservation(interfaceName: "en2", usesWiredEthernet: true, remoteHost: "192.168.1.20")
        #expect(LinkJudge.judge(o) == .ethernet)
    }

    @Test func wifiEvenToALinkLocalPeer() {
        let o = LinkObservation(interfaceName: "en0", usesWiFi: true, remoteHost: "fe80::1%en0")
        #expect(LinkJudge.judge(o) == .wifi)
    }

    @Test func awdlIsPeerToPeerWhateverItsType() {
        #expect(LinkJudge.judge(LinkObservation(interfaceName: "awdl0", usesWiFi: true)) == .peerToPeer)
        #expect(LinkJudge.judge(LinkObservation(interfaceName: "llw0", usesOther: true, remoteHost: "fe80::1%llw0")) == .peerToPeer)
    }

    @Test func tunnelsAndLoopback() {
        #expect(LinkJudge.judge(LinkObservation(interfaceName: "utun4", usesOther: true, remoteHost: "100.64.0.7")) == .tunnel)
        #expect(LinkJudge.judge(LinkObservation(interfaceName: "lo0", usesLoopback: true)) == .loopback)
        #expect(LinkJudge.judge(LinkObservation(remoteHost: "::1")) == .loopback)
    }

    @Test func nothingKnownIsUnknown() {
        #expect(LinkJudge.judge(LinkObservation()) == .unknown)
        #expect(LinkJudge.judge(LinkObservation(usesCellular: true)) == .cellular)
    }

    @Test func eitherSidesCableWins() {
        #expect(LinkJudge.merged(local: .wifi, peer: .wired) == .wired)
        #expect(LinkJudge.merged(local: .wired, peer: .ethernet) == .wired)
        #expect(LinkJudge.merged(local: .unknown, peer: .ethernet) == .ethernet)
        #expect(LinkJudge.merged(local: .wifi, peer: .ethernet) == .wifi)
        #expect(LinkJudge.merged(local: .unknown, peer: nil) == .unknown)
    }

    @Test func carryingInterfacePrefersTheAddressScope() {
        #expect(LinkJudge.carryingInterface(localHost: "fe80::1%en7", addressOwners: ["fe80::1": "en0"], pathInterfaces: ["en0"]) == "en7")
        #expect(LinkJudge.carryingInterface(localHost: "169.254.3.4", addressOwners: ["169.254.3.4": "en9"], pathInterfaces: ["en0", "en9"]) == "en9")
        #expect(LinkJudge.carryingInterface(localHost: "[FE80::AB]", addressOwners: ["fe80::ab": "en5"], pathInterfaces: []) == "en5")
        #expect(LinkJudge.carryingInterface(localHost: "10.0.0.2", addressOwners: [:], pathInterfaces: ["en1", "en0"]) == "en1")
        #expect(LinkJudge.carryingInterface(localHost: nil, addressOwners: [:], pathInterfaces: []) == nil)
    }

    @Test func addressHelpers() {
        #expect(LinkJudge.scope(of: "fe80::1%en7") == "en7")
        #expect(LinkJudge.scope(of: "fe80::1%") == nil)
        #expect(LinkJudge.scope(of: "10.0.0.1") == nil)
        #expect(LinkJudge.isLinkLocal("febf::1"))
        #expect(!LinkJudge.isLinkLocal("fec0::1"))
        #expect(!LinkJudge.isLinkLocal("169.25.0.1"))
        #expect(!LinkJudge.isLinkLocal(nil))
        // An IPv4 address that happens to start with "fe8" can't exist, and
        // a host name isn't an address.
        #expect(!LinkJudge.isLinkLocal("fe80-host.local"))
    }

    @Test func unknownKindsDecodeAsOther() throws {
        let decoded = try JSONDecoder().decode([LinkKind].self, from: Data(#"["wired","satellite"]"#.utf8))
        #expect(decoded == [.wired, .other])
    }

    @Test func everyKindHasCopyAndASymbol() {
        for kind in LinkKind.allCases {
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.systemImage.isEmpty)
        }
        #expect(LinkKind.wired.displayName == "Wired")
    }
}

@Suite struct WiredLinkPolicyTests {

    /// Roughly what IOKit shows above an "iPad USB" interface.
    private let iPadChain: [RegistryNode] = [
        RegistryNode(className: "IOEthernetInterface"),
        RegistryNode(className: "AppleUSBNCMData", properties: ["bInterfaceClass": 0x0A]),
        RegistryNode(className: "IOUSBHostInterface", properties: ["bInterfaceClass": 0x0A, "idVendor": 0x05AC]),
        RegistryNode(className: "IOUSBHostDevice", properties: ["idVendor": 0x05AC, "bDeviceClass": 0]),
        RegistryNode(className: "AppleUSBXHCIPort"),
    ]

    @Test func appleNCMChainIsATether() {
        #expect(WiredLinkPolicy.isUSBTether(ancestry: iPadChain))
    }

    @Test func ncmByInterfaceClassWithoutANamedDriver() {
        let chain = [
            RegistryNode(className: "IOEthernetInterface"),
            RegistryNode(className: "SomeDriver"),
            RegistryNode(className: "IOUSBHostInterface", properties: ["bInterfaceClass": 2, "bInterfaceSubClass": 0x0D]),
            RegistryNode(className: "IOUSBHostDevice", properties: ["idVendor": 0x05AC]),
        ]
        #expect(WiredLinkPolicy.isUSBTether(ancestry: chain))
    }

    @Test func thirdPartyNCMAdapterIsNotATether() {
        let chain = [
            RegistryNode(className: "IOEthernetInterface"),
            RegistryNode(className: "AppleUSBNCMData"),
            RegistryNode(className: "IOUSBHostDevice", properties: ["idVendor": 0x0BDA]),
        ]
        #expect(!WiredLinkPolicy.isUSBTether(ancestry: chain))
    }

    @Test func builtInEthernetAndWiFiAreNotTethers() {
        let ethernet = [
            RegistryNode(className: "IOEthernetInterface"),
            RegistryNode(className: "AppleBCM5701Ethernet"),
            RegistryNode(className: "IOPCIDevice"),
        ]
        let wifi = [
            RegistryNode(className: "IO80211Interface"),
            RegistryNode(className: "AppleBCMWLANCore"),
        ]
        #expect(!WiredLinkPolicy.isUSBTether(ancestry: ethernet))
        #expect(!WiredLinkPolicy.isUSBTether(ancestry: wifi))
        #expect(!WiredLinkPolicy.isUSBTether(ancestry: []))
    }

    @Test func appleVendorBelowTheNCMFunctionDoesNotCount() {
        // The vendor must be on the NCM function or above it.
        let chain = [
            RegistryNode(className: "IOEthernetInterface", properties: ["idVendor": 0x05AC]),
            RegistryNode(className: "AppleUSBNCMData"),
            RegistryNode(className: "IOUSBHostDevice", properties: ["idVendor": 0x0BDA]),
        ]
        #expect(!WiredLinkPolicy.isUSBTether(ancestry: chain))
    }

    @Test func walkIsBounded() {
        let deep = Array(repeating: RegistryNode(className: "Filler"), count: WiredLinkPolicy.maxDepth) + iPadChain
        #expect(!WiredLinkPolicy.isUSBTether(ancestry: deep))
    }
}

@Suite struct KeepAliveTests {

    @Test func ticksOnlyOnLinksThatDoze() {
        #expect(KeepAlivePolicy.needsTick(local: .wifi, peer: nil))
        #expect(KeepAlivePolicy.needsTick(local: .unknown, peer: nil))
        #expect(KeepAlivePolicy.needsTick(local: .wifi, peer: .ethernet))
        #expect(!KeepAlivePolicy.needsTick(local: .wifi, peer: .wired))
        #expect(!KeepAlivePolicy.needsTick(local: .wired, peer: nil))
        #expect(!KeepAlivePolicy.needsTick(local: .ethernet, peer: nil))
        #expect(!KeepAlivePolicy.needsTick(local: .loopback, peer: nil))
    }

    @Test func tickIsMuchMoreFrequentThanThePing() {
        #expect(KeepAlivePolicy.tickInterval <= 0.25)
        #expect(KeepAlivePolicy.tickInterval * 4 <= LivenessPolicy.pingInterval)
    }

    @Test func backgroundPausesEverythingAndResumeIsReported() {
        var gate = KeepAliveGate(localLink: .wifi)
        #expect(gate.isTicking && gate.isPinging)
        #expect(gate.setForeground(false) == .paused)
        #expect(!gate.isTicking && !gate.isPinging)
        #expect(gate.setForeground(false) == .none)
        #expect(gate.setForeground(true) == .resumed)
        #expect(gate.isTicking && gate.isPinging)
        #expect(gate.setForeground(true) == .none)
    }

    @Test func theCableStopsTicksButNotPings() {
        var gate = KeepAliveGate(localLink: .wifi)
        gate.setPeerLink(.wired)
        #expect(!gate.isTicking)
        #expect(gate.isPinging)
        #expect(gate.displayedLink == .wired)
        gate.setPeerLink(nil)
        gate.setLocalLink(.ethernet)
        #expect(!gate.isTicking)
        #expect(gate.displayedLink == .ethernet)
    }
}

@Suite struct InterfaceAddressTableTests {
    @Test func loopbackAddressIsOwnedByTheLoopbackInterface() {
        let owners = InterfaceAddressTable.current()
        let owner = owners["127.0.0.1"]
        #expect(owner == "lo" || owner == "lo0", "\(owners)")
    }
}
