//
//  LoomSessionNetworkPathSnapshot.swift
//  Loom
//
//  Created by Ethan Lipnik on 3/13/26.
//

import Foundation
#if canImport(Network)
import Network
#endif

/// High-level reachability status for an authenticated Loom session transport path.
public enum LoomSessionNetworkPathStatus: String, Sendable, Codable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

/// Snapshot of the transport path currently used by an authenticated Loom session.
public struct LoomSessionNetworkPathSnapshot: Sendable, Equatable {
    public let status: LoomSessionNetworkPathStatus
    /// Names of the path's interfaces, sorted alphabetically.
    public let interfaceNames: [String]
    /// The path's interfaces in the transport's order of preference, with
    /// their category and index when the backend reports them.
    ///
    /// For an established connection the first entry is the interface
    /// carrying it; see ``primaryInterface``. Snapshots created from names
    /// only list each interface with the ``LoomNetworkInterfaceType/other``
    /// category, in the order given.
    public let interfaces: [LoomNetworkInterface]
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let supportsIPv4: Bool
    public let supportsIPv6: Bool
    public let usesWiFi: Bool
    public let usesWiredEthernet: Bool
    public let usesCellular: Bool
    public let usesLoopback: Bool
    public let usesOther: Bool
    public let backendLocalEndpoint: LoomNetworkEndpoint?
    public let backendRemoteEndpoint: LoomNetworkEndpoint?

#if canImport(Network)
    /// Network.framework compatibility projection of the local endpoint.
    public var localEndpoint: NWEndpoint? {
        backendLocalEndpoint?.nwEndpoint
    }

    /// Network.framework compatibility projection of the remote endpoint.
    public var remoteEndpoint: NWEndpoint? {
        backendRemoteEndpoint?.nwEndpoint
    }
#endif

    /// The interface the transport prefers on this path: for an established
    /// connection, the one carrying it. `nil` when no interface is reported.
    public var primaryInterface: LoomNetworkInterface? {
        interfaces.first
    }

    /// Backend-independent representation of this path snapshot.
    public var backendPath: LoomNetworkPath {
        let backendStatus: LoomNetworkPathStatus = switch status {
        case .satisfied:
            .satisfied
        case .unsatisfied:
            .unsatisfied
        case .requiresConnection:
            .requiresConnection
        }
        return LoomNetworkPath(
            status: backendStatus,
            interfaces: interfaces,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            supportsIPv4: supportsIPv4,
            supportsIPv6: supportsIPv6,
            usesWiFi: usesWiFi,
            usesWiredEthernet: usesWiredEthernet,
            usesCellular: usesCellular,
            usesLoopback: usesLoopback,
            usesOther: usesOther,
            localEndpoint: backendLocalEndpoint,
            remoteEndpoint: backendRemoteEndpoint
        )
    }

    /// Creates a path snapshot without exposing a platform networking type.
    ///
    /// - Parameter interfaces: The path's interfaces in order of preference.
    ///   When `nil`, ``interfaces`` lists `interfaceNames` in the given order
    ///   with the ``LoomNetworkInterfaceType/other`` category.
    public init(
        status: LoomSessionNetworkPathStatus,
        interfaceNames: [String],
        isExpensive: Bool,
        isConstrained: Bool,
        supportsIPv4: Bool,
        supportsIPv6: Bool,
        usesWiFi: Bool,
        usesWiredEthernet: Bool,
        usesCellular: Bool,
        usesLoopback: Bool,
        usesOther: Bool,
        backendLocalEndpoint: LoomNetworkEndpoint?,
        backendRemoteEndpoint: LoomNetworkEndpoint?,
        interfaces: [LoomNetworkInterface]? = nil
    ) {
        self.status = status
        self.interfaceNames = interfaceNames
        self.interfaces = interfaces ?? interfaceNames.map {
            LoomNetworkInterface(name: $0, type: .other)
        }
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.supportsIPv4 = supportsIPv4
        self.supportsIPv6 = supportsIPv6
        self.usesWiFi = usesWiFi
        self.usesWiredEthernet = usesWiredEthernet
        self.usesCellular = usesCellular
        self.usesLoopback = usesLoopback
        self.usesOther = usesOther
        self.backendLocalEndpoint = backendLocalEndpoint
        self.backendRemoteEndpoint = backendRemoteEndpoint
    }

#if canImport(Network)
    /// Creates a path snapshot using the released Network.framework endpoint API.
    ///
    /// - Parameter interfaces: The path's interfaces in order of preference.
    ///   When `nil`, ``interfaces`` lists `interfaceNames` in the given order
    ///   with the ``LoomNetworkInterfaceType/other`` category.
    public init(
        status: LoomSessionNetworkPathStatus,
        interfaceNames: [String],
        isExpensive: Bool,
        isConstrained: Bool,
        supportsIPv4: Bool,
        supportsIPv6: Bool,
        usesWiFi: Bool,
        usesWiredEthernet: Bool,
        usesCellular: Bool,
        usesLoopback: Bool,
        usesOther: Bool,
        localEndpoint: NWEndpoint?,
        remoteEndpoint: NWEndpoint?,
        interfaces: [LoomNetworkInterface]? = nil
    ) {
        self.init(
            status: status,
            interfaceNames: interfaceNames,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            supportsIPv4: supportsIPv4,
            supportsIPv6: supportsIPv6,
            usesWiFi: usesWiFi,
            usesWiredEthernet: usesWiredEthernet,
            usesCellular: usesCellular,
            usesLoopback: usesLoopback,
            usesOther: usesOther,
            backendLocalEndpoint: localEndpoint.flatMap(LoomNetworkEndpoint.init),
            backendRemoteEndpoint: remoteEndpoint.flatMap(LoomNetworkEndpoint.init),
            interfaces: interfaces
        )
    }
#endif
}

extension LoomSessionNetworkPathSnapshot {
    package init(backendPath: LoomNetworkPath) {
        let status: LoomSessionNetworkPathStatus = switch backendPath.status {
        case .satisfied:
            .satisfied
        case .unsatisfied:
            .unsatisfied
        case .requiresConnection:
            .requiresConnection
        }
        self.init(
            status: status,
            interfaceNames: backendPath.interfaces.map(\.name).sorted(),
            isExpensive: backendPath.isExpensive,
            isConstrained: backendPath.isConstrained,
            supportsIPv4: backendPath.supportsIPv4,
            supportsIPv6: backendPath.supportsIPv6,
            usesWiFi: backendPath.usesWiFi,
            usesWiredEthernet: backendPath.usesWiredEthernet,
            usesCellular: backendPath.usesCellular,
            usesLoopback: backendPath.usesLoopback,
            usesOther: backendPath.usesOther,
            backendLocalEndpoint: backendPath.localEndpoint,
            backendRemoteEndpoint: backendPath.remoteEndpoint,
            interfaces: backendPath.interfaces
        )
    }

#if canImport(Network)
    package init(path: NWPath) {
        let status: LoomSessionNetworkPathStatus = switch path.status {
        case .satisfied:
            .satisfied
        case .unsatisfied:
            .unsatisfied
        case .requiresConnection:
            .requiresConnection
        @unknown default:
            .requiresConnection
        }

        self.init(
            status: status,
            interfaceNames: path.availableInterfaces.map(\.name).sorted(),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            supportsIPv4: path.supportsIPv4,
            supportsIPv6: path.supportsIPv6,
            usesWiFi: path.usesInterfaceType(.wifi),
            usesWiredEthernet: path.usesInterfaceType(.wiredEthernet),
            usesCellular: path.usesInterfaceType(.cellular),
            usesLoopback: path.usesInterfaceType(.loopback),
            usesOther: path.usesInterfaceType(.other),
            localEndpoint: path.localEndpoint,
            remoteEndpoint: path.remoteEndpoint,
            interfaces: path.availableInterfaces.map(LoomNetworkInterface.init)
        )
    }
#endif
}
