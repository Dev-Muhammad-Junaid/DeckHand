//
//  LoomOverlayDirectoryConfigurationTests.swift
//  Loom
//

@testable import Loom
import Foundation
import Testing

@Suite("Loom Overlay Directory Configuration")
struct LoomOverlayDirectoryConfigurationTests {
    @Test("An overlay directory listens for probes by default")
    func listensForProbesByDefault() {
        let configuration = LoomOverlayDirectoryConfiguration(seedProvider: { [] })
        #expect(configuration.listensForProbes)
    }

    @Test("A dial-only copy stops listening for probes and keeps every probing setting")
    func dialOnlyKeepsProbingSettings() {
        let configuration = LoomOverlayDirectoryConfiguration(
            probePort: 41_010,
            refreshInterval: .seconds(12),
            probeTimeout: .seconds(3),
            probeAttempts: 4,
            probeRetryDelay: .milliseconds(250),
            retainedPeerExpiration: .seconds(90),
            seedProvider: { [] }
        )

        let dialOnly = configuration.dialOnly()

        #expect(!dialOnly.listensForProbes)
        #expect(configuration.listensForProbes)
        #expect(dialOnly.probePort == 41_010)
        #expect(dialOnly.refreshInterval == .seconds(12))
        #expect(dialOnly.probeTimeout == .seconds(3))
        #expect(dialOnly.probeAttempts == 4)
        #expect(dialOnly.probeRetryDelay == .milliseconds(250))
        #expect(dialOnly.retainedPeerExpiration == .seconds(90))
        #expect(dialOnly.usesDefaultProbePort == configuration.usesDefaultProbePort)
    }
}
