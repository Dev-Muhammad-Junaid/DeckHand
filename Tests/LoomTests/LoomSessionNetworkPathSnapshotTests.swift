//
//  LoomSessionNetworkPathSnapshotTests.swift
//  LoomTests
//

@testable import Loom
import Testing

@Suite("Session Network Path Snapshot")
struct LoomSessionNetworkPathSnapshotTests {
    private func backendPath(interfaces: [LoomNetworkInterface]) -> LoomNetworkPath {
        LoomNetworkPath(
            status: .satisfied,
            interfaces: interfaces,
            isExpensive: false,
            isConstrained: false,
            supportsIPv4: true,
            supportsIPv6: true,
            usesWiFi: true,
            usesWiredEthernet: true,
            usesCellular: false,
            usesLoopback: false,
            usesOther: false,
            localEndpoint: .hostPort(host: "fe80::1%en7", port: 50_000),
            remoteEndpoint: .hostPort(host: "fe80::2%en7", port: 38_447)
        )
    }

    @Test("Backend paths keep interface order and categories")
    func backendPathKeepsInterfaceOrderAndCategories() {
        let interfaces = [
            LoomNetworkInterface(name: "en7", index: 21, type: .wiredEthernet),
            LoomNetworkInterface(name: "en0", index: 14, type: .wifi),
        ]
        let snapshot = LoomSessionNetworkPathSnapshot(backendPath: backendPath(interfaces: interfaces))

        #expect(snapshot.interfaces == interfaces)
        #expect(snapshot.primaryInterface == interfaces[0])
        #expect(snapshot.interfaceNames == ["en0", "en7"])
        #expect(snapshot.backendPath.interfaces == interfaces)
    }

    @Test("Name-only snapshots list interfaces in the given order")
    func nameOnlySnapshotsKeepGivenOrder() {
        let snapshot = LoomSessionNetworkPathSnapshot(
            status: .satisfied,
            interfaceNames: ["en5", "en0"],
            isExpensive: false,
            isConstrained: false,
            supportsIPv4: true,
            supportsIPv6: false,
            usesWiFi: false,
            usesWiredEthernet: true,
            usesCellular: false,
            usesLoopback: false,
            usesOther: false,
            backendLocalEndpoint: nil,
            backendRemoteEndpoint: nil
        )

        #expect(snapshot.interfaces.map(\.name) == ["en5", "en0"])
        #expect(snapshot.interfaces.allSatisfy { $0.type == .other && $0.index == nil })
        #expect(snapshot.primaryInterface?.name == "en5")
    }

    @Test("Explicit interfaces round-trip through the backend path")
    func explicitInterfacesRoundTrip() {
        let interfaces = [LoomNetworkInterface(name: "utun3", index: 30, type: .other)]
        let snapshot = LoomSessionNetworkPathSnapshot(
            status: .satisfied,
            interfaceNames: ["utun3"],
            isExpensive: false,
            isConstrained: false,
            supportsIPv4: true,
            supportsIPv6: false,
            usesWiFi: false,
            usesWiredEthernet: false,
            usesCellular: false,
            usesLoopback: false,
            usesOther: true,
            backendLocalEndpoint: nil,
            backendRemoteEndpoint: nil,
            interfaces: interfaces
        )

        #expect(LoomSessionNetworkPathSnapshot(backendPath: snapshot.backendPath) == snapshot)
    }

    @Test("A path with no interfaces has no primary interface")
    func emptyPathHasNoPrimaryInterface() {
        let snapshot = LoomSessionNetworkPathSnapshot(backendPath: backendPath(interfaces: []))
        #expect(snapshot.primaryInterface == nil)
        #expect(snapshot.interfaces.isEmpty)
    }
}
