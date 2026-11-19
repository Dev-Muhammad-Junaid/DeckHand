//
//  LinkJudge.swift
//  PixelHandCore
//
//  Decides what a session's link is from what each side can see: the
//  interface carrying the connection, the path's interface types, the
//  addresses, and (on the Mac only) whether IOKit says that interface is a
//  USB CDC-NCM link to an Apple device (`WiredLinkPolicy`).
//
//  Pure, so it is tested here. The Mac (`HostLinkMonitor`) and the remote
//  (`RemoteLinkMonitor`) fill a `LinkObservation` from Loom's path
//  snapshots and ask `judge(_:)`.
//

import Foundation

/// What one side knows about the link carrying a session.
public struct LinkObservation: Sendable, Equatable {
    /// The interface carrying the connection (`en7`, `awdl0`, `utun3`), if known.
    public var interfaceName: String?
    public var usesWiFi: Bool
    public var usesWiredEthernet: Bool
    public var usesCellular: Bool
    public var usesLoopback: Bool
    public var usesOther: Bool
    /// The peer's address, verbatim (a scoped IPv6 address keeps `%en7`).
    public var remoteHost: String?
    /// IOKit's answer for `interfaceName` (Mac only): `true` for a USB
    /// CDC-NCM link to an Apple device. `nil` when it wasn't checked.
    public var isUSBTether: Bool?

    public init(
        interfaceName: String? = nil,
        usesWiFi: Bool = false,
        usesWiredEthernet: Bool = false,
        usesCellular: Bool = false,
        usesLoopback: Bool = false,
        usesOther: Bool = false,
        remoteHost: String? = nil,
        isUSBTether: Bool? = nil
    ) {
        self.interfaceName = interfaceName
        self.usesWiFi = usesWiFi
        self.usesWiredEthernet = usesWiredEthernet
        self.usesCellular = usesCellular
        self.usesLoopback = usesLoopback
        self.usesOther = usesOther
        self.remoteHost = remoteHost
        self.isUSBTether = isUSBTether
    }
}

public enum LinkJudge {
    /// Interface name prefixes that identify a link regardless of its type.
    static let peerToPeerPrefixes = ["awdl", "llw"]
    static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]

    public static func judge(_ o: LinkObservation) -> LinkKind {
        let name = o.interfaceName?.lowercased()
        if o.usesLoopback || name == "lo0" || name == "lo" || isLoopback(o.remoteHost) {
            return .loopback
        }
        if let name, peerToPeerPrefixes.contains(where: name.hasPrefix) {
            return .peerToPeer
        }
        if o.isUSBTether == true {
            return .wired
        }
        if let name, tunnelPrefixes.contains(where: name.hasPrefix) {
            return .tunnel
        }
        if o.usesWiredEthernet || (o.usesOther && !o.usesWiFi && !o.usesCellular) {
            // Without IOKit (the remote, public API only): a wired interface
            // to a link-local peer is the USB cable to the Mac. A LAN peer
            // found over Bonjour normally has a routable address too.
            if o.isUSBTether == nil, isLinkLocal(o.remoteHost) {
                return .wired
            }
            if o.usesWiredEthernet { return .ethernet }
        }
        if o.usesWiFi { return .wifi }
        if o.usesCellular { return .cellular }
        if o.usesOther || name != nil { return .other }
        return .unknown
    }

    /// What to show for a session given this side's own judgement and the
    /// peer's report. A cable is a cable at both ends, so either side's
    /// `.wired` wins; otherwise the local judgement stands, falling back to
    /// the peer's while the local one is still unknown.
    public static func merged(local: LinkKind, peer: LinkKind?) -> LinkKind {
        if local == .wired || peer == .wired { return .wired }
        if local == .unknown, let peer { return peer }
        return local
    }

    /// The interface carrying a connection: the zone of a scoped local
    /// address first (`fe80::1%en7`), then the owner of the local address
    /// (`addressOwners`, from `getifaddrs`), then the path's preferred
    /// interface.
    public static func carryingInterface(
        localHost: String?,
        addressOwners: [String: String],
        pathInterfaces: [String]
    ) -> String? {
        if let localHost {
            if let zone = scope(of: localHost) { return zone }
            if let owner = addressOwners[unscoped(localHost)] { return owner }
        }
        return pathInterfaces.first
    }

    // MARK: - Address helpers

    /// The zone of a scoped IPv6 address (`en7` in `fe80::1%en7`).
    public static func scope(of host: String) -> String? {
        guard let percent = host.firstIndex(of: "%") else { return nil }
        let zone = host[host.index(after: percent)...]
        return zone.isEmpty ? nil : String(zone)
    }

    /// The address without its zone or IPv6 brackets.
    public static func unscoped(_ host: String) -> String {
        var h = host
        if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        if let percent = h.firstIndex(of: "%") { h = String(h[..<percent]) }
        return h.lowercased()
    }

    /// 169.254.0.0/16 or fe80::/10.
    public static func isLinkLocal(_ host: String?) -> Bool {
        guard let host else { return false }
        let h = unscoped(host)
        if h.hasPrefix("169.254.") { return true }
        // fe80::/10 covers fe80 … febf.
        let ipv6Prefixes = ["fe8", "fe9", "fea", "feb"]
        return h.contains(":") && ipv6Prefixes.contains(where: h.hasPrefix)
    }

    public static func isLoopback(_ host: String?) -> Bool {
        guard let host else { return false }
        let h = unscoped(host)
        return h == "::1" || h.hasPrefix("127.") || h == "localhost"
    }
}
