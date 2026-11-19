//
//  LoomOverlayDirectoryConfiguration.swift
//  Loom
//
//  Created by Ethan Lipnik on 3/11/26.
//

import Foundation

/// Configuration for the seed-driven off-LAN Loom peer directory.
public struct LoomOverlayDirectoryConfiguration: Sendable {
    /// Async seed provider used to resolve overlay host names or IP addresses.
    public typealias SeedProvider = @Sendable () async throws -> [LoomOverlaySeed]

    /// Provider used to fetch current overlay seeds.
    public let seedProvider: SeedProvider
    /// Default TCP probe port used when a seed does not override it.
    public let probePort: UInt16
    /// Refresh interval for reloading and re-probing seeds.
    public let refreshInterval: Duration
    /// Per-seed timeout applied to the TCP probe.
    public let probeTimeout: Duration
    /// Number of probe attempts made for each seed during one refresh.
    public let probeAttempts: Int
    /// Delay between retry attempts for a seed that did not respond.
    public let probeRetryDelay: Duration
    /// Duration that the directory keeps the last resolved peers after transient probe failures.
    public let retainedPeerExpiration: Duration
    /// Policy used to rank direct transports when several seeds describe the same peer.
    public let directConnectionPolicy: LoomDirectConnectionPolicy
    /// Whether a node that uses this directory also opens its own overlay probe listener.
    ///
    /// The default is `true`: the local node listens on ``probePort`` so other overlay
    /// directories can discover it. Set it to `false` (or use ``dialOnly()``) for a node
    /// that only resolves and dials overlay peers and never needs to be discovered
    /// through an overlay probe. The directory still probes remote seeds on ``probePort``.
    public var listensForProbes: Bool = true
    package let usesDefaultProbePort: Bool

    public init(
        probePort: UInt16? = nil,
        refreshInterval: Duration = .seconds(30),
        probeTimeout: Duration = .seconds(2),
        directConnectionPolicy: LoomDirectConnectionPolicy = .default,
        seedProvider: @escaping SeedProvider
    ) {
        self.init(
            probePort: probePort,
            refreshInterval: refreshInterval,
            probeTimeout: probeTimeout,
            retainedPeerExpiration: .seconds(120),
            directConnectionPolicy: directConnectionPolicy,
            seedProvider: seedProvider
        )
    }

    public init(
        probePort: UInt16? = nil,
        refreshInterval: Duration = .seconds(30),
        probeTimeout: Duration = .seconds(2),
        retainedPeerExpiration: Duration = .seconds(120),
        directConnectionPolicy: LoomDirectConnectionPolicy = .default,
        seedProvider: @escaping SeedProvider
    ) {
        self.init(
            probePort: probePort,
            refreshInterval: refreshInterval,
            probeTimeout: probeTimeout,
            probeAttempts: 1,
            probeRetryDelay: .zero,
            retainedPeerExpiration: retainedPeerExpiration,
            directConnectionPolicy: directConnectionPolicy,
            seedProvider: seedProvider
        )
    }

    public init(
        probePort: UInt16? = nil,
        refreshInterval: Duration = .seconds(30),
        probeTimeout: Duration = .seconds(2),
        probeAttempts: Int,
        probeRetryDelay: Duration = .zero,
        directConnectionPolicy: LoomDirectConnectionPolicy = .default,
        seedProvider: @escaping SeedProvider
    ) {
        self.init(
            probePort: probePort,
            refreshInterval: refreshInterval,
            probeTimeout: probeTimeout,
            probeAttempts: probeAttempts,
            probeRetryDelay: probeRetryDelay,
            retainedPeerExpiration: .seconds(120),
            directConnectionPolicy: directConnectionPolicy,
            seedProvider: seedProvider
        )
    }

    public init(
        probePort: UInt16? = nil,
        refreshInterval: Duration = .seconds(30),
        probeTimeout: Duration = .seconds(2),
        probeAttempts: Int,
        probeRetryDelay: Duration = .zero,
        retainedPeerExpiration: Duration = .seconds(120),
        directConnectionPolicy: LoomDirectConnectionPolicy = .default,
        seedProvider: @escaping SeedProvider
    ) {
        let usesDefaultProbePort = probePort == nil
        self.seedProvider = seedProvider
        self.probePort = probePort ?? Loom.defaultOverlayProbePort
        self.refreshInterval = refreshInterval
        self.probeTimeout = probeTimeout
        self.probeAttempts = max(1, probeAttempts)
        self.probeRetryDelay = probeRetryDelay
        self.retainedPeerExpiration = retainedPeerExpiration
        self.directConnectionPolicy = directConnectionPolicy
        self.usesDefaultProbePort = usesDefaultProbePort
    }

    /// Returns a copy that resolves and dials overlay peers without opening a local probe listener.
    ///
    /// Use this on nodes that only connect outward, so they never bind ``probePort``
    /// locally. Probes of remote seeds are unchanged.
    public func dialOnly() -> LoomOverlayDirectoryConfiguration {
        var configuration = self
        configuration.listensForProbes = false
        return configuration
    }
}
