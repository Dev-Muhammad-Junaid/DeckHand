//
//  LoomKitPortConfigurationTests.swift
//  LoomKit
//
//  Created by Codex on 5/5/26.
//

@testable import Loom
@testable import LoomKit
import Testing

@Suite("LoomKit Port Configuration")
struct LoomKitPortConfigurationTests {
    @Test("Default LoomKit overlay probe port follows Loom's default")
    func defaultOverlayProbePortFollowsLoomDefault() {
        #expect(LoomKitPortConfiguration.default.overlayProbePort == Loom.defaultOverlayProbePort)
    }

    @MainActor
    @Test("Container applies LoomKit overlay probe default when overlay configuration omits the port")
    func containerAppliesLoomKitOverlayProbeDefault() throws {
        let container = try LoomContainer(
            for: LoomContainerConfiguration(
                serviceName: "Overlay Host",
                overlayDirectory: LoomOverlayDirectoryConfiguration(
                    seedProvider: { [] }
                )
            )
        )

        #expect(container.configuration.overlayDirectory?.probePort == Loom.defaultOverlayProbePort)
    }

    @MainActor
    @Test("Container preserves explicit LoomKit port overrides")
    func containerPreservesExplicitPortOverrides() throws {
        let ports = LoomKitPortConfiguration(
            tcpPort: 41_001,
            udpPort: 41_002,
            overlayProbePort: 41_004
        )
        let container = try LoomContainer(
            for: LoomContainerConfiguration(
                serviceName: "Custom Port Host",
                overlayDirectory: LoomOverlayDirectoryConfiguration(
                    seedProvider: { [] }
                ),
                ports: ports
            )
        )

        #expect(container.configuration.ports == ports)
        #expect(container.configuration.overlayDirectory?.probePort == ports.overlayProbePort)
    }

    @MainActor
    @Test("Container preserves an explicit overlay directory probe port")
    func containerPreservesExplicitOverlayDirectoryProbePort() throws {
        let container = try LoomContainer(
            for: LoomContainerConfiguration(
                serviceName: "Explicit Overlay Host",
                overlayDirectory: LoomOverlayDirectoryConfiguration(
                    probePort: 41_005,
                    seedProvider: { [] }
                )
            )
        )

        #expect(container.configuration.overlayDirectory?.probePort == 41_005)
    }

    @MainActor
    @Test("Container keeps the overlay probe listener by default")
    func containerKeepsProbeListenerByDefault() throws {
        let container = try LoomContainer(
            for: LoomContainerConfiguration(
                serviceName: "Listening Overlay Host",
                overlayDirectory: LoomOverlayDirectoryConfiguration(
                    seedProvider: { [] }
                )
            )
        )

        let overlayDirectory = try #require(container.configuration.overlayDirectory)
        #expect(overlayDirectory.listensForProbes)
        #expect(LoomContainer.localOverlayProbePort(for: overlayDirectory) == Loom.defaultOverlayProbePort)
    }

    @MainActor
    @Test("A dial-only overlay directory opens no local probe listener but keeps probing remote seeds")
    func dialOnlyOverlayDirectoryOpensNoProbeListener() throws {
        let ports = LoomKitPortConfiguration(overlayProbePort: 41_006)
        let container = try LoomContainer(
            for: LoomContainerConfiguration(
                serviceName: "Dial-only Overlay Client",
                overlayDirectory: LoomOverlayDirectoryConfiguration(
                    probeAttempts: 2,
                    probeRetryDelay: .milliseconds(400),
                    retainedPeerExpiration: .seconds(45),
                    seedProvider: { [] }
                ).dialOnly(),
                ports: ports
            )
        )

        let overlayDirectory = try #require(container.configuration.overlayDirectory)
        #expect(!overlayDirectory.listensForProbes)
        #expect(overlayDirectory.probePort == 41_006)
        #expect(overlayDirectory.probeAttempts == 2)
        #expect(overlayDirectory.retainedPeerExpiration == .seconds(45))
        #expect(LoomContainer.localOverlayProbePort(for: overlayDirectory) == nil)
        #expect(LoomContainer.localOverlayProbePort(for: nil) == nil)
    }
}
