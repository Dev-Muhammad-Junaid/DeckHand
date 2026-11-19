//
//  RemoteAccessPolicy.swift
//  PixelHandCore
//
//  S15: who may connect over a VPN, and to whom.
//
//  Remote side (`dialPlan`): a Mac Bonjour can see is dialled as before.
//  A Mac reached any other way (Loom's overlay probe of a saved host) is
//  dialled only if it is on this device's pairing list, and the handshake
//  is pinned to the identity key stored when it paired, never the key the
//  probe answer advertised. A Mac that isn't paired is refused before any
//  connection is made. After the handshake, `verify` checks the proven
//  identity against the pin once more (key and Loom device ID).
//
//  Mac side (`admission`): a connection that arrives over a remote path
//  (a tunnel interface, an overlay address, cellular, or loopback from an
//  SSH port forward) is admitted only if it is already paired. No Allow
//  prompt and no pairing code from outside the local network.
//

import Foundation

public enum RemoteAccessPolicy {

    // MARK: - Remote: dialling

    /// How a peer the picker shows was found.
    public struct PeerReach: Equatable, Sendable {
        /// Loom device ID of the peer (signed by its key in the handshake).
        public var deviceID: UUID
        /// Seen by Bonjour on this network.
        public var isNearby: Bool
        /// The identity key the peer advertised, if any. Never trusted for
        /// a remote dial; only compared for a clearer error.
        public var advertisedIdentityKeyID: String?

        public init(deviceID: UUID, isNearby: Bool, advertisedIdentityKeyID: String?) {
            self.deviceID = deviceID
            self.isNearby = isNearby
            self.advertisedIdentityKeyID = advertisedIdentityKeyID
        }
    }

    public enum DialPlan: Equatable, Sendable {
        /// On this network: dial as usual (the Mac's Allow / pairing rules apply).
        case local
        /// Off this network: dial with the handshake pinned to this paired
        /// Mac's stored identity.
        case remote(pinned: PairedDeviceRef)
        case refuse(DialRefusal)
    }

    public enum DialRefusal: Equatable, Sendable {
        /// Not on the pairing list: remote access needs pairing first.
        case notPaired
        /// Paired, but the Mac reached at that address advertises another
        /// identity key (reinstalled, or not the same Mac).
        case keyChanged

        public var message: String {
            switch self {
            case .notPaired:
                "Remote access works only with a paired Mac. Pair on the same Wi-Fi first (Enter Pairing Code), then try again."
            case .keyChanged:
                "That address answered with a different identity than the paired Mac. If you reinstalled Pixel Hand on the Mac, forget it and pair again on the same Wi-Fi."
            }
        }
    }

    public static func dialPlan(for peer: PeerReach, pairedMacs: TrustList) -> DialPlan {
        if peer.isNearby { return .local }
        let candidates = pairedMacs.devices.filter { $0.deviceID == peer.deviceID }
        guard !candidates.isEmpty else { return .refuse(.notPaired) }
        // One owner's Macs can share a key (iCloud Keychain), never a
        // device ID; more than one record per device ID only happens
        // briefly after a re-pair. Prefer the one the advertisement names,
        // then the most recently paired.
        if let advertised = peer.advertisedIdentityKeyID,
           let match = candidates.first(where: { $0.identityKeyID == advertised }) {
            return .remote(pinned: match.ref)
        }
        if peer.advertisedIdentityKeyID != nil {
            return .refuse(.keyChanged)
        }
        let newest = candidates.max { $0.pairedAt < $1.pairedAt }!
        return .remote(pinned: newest.ref)
    }

    /// The identity the handshake proved matches the pin: same key, same
    /// Loom device ID.
    public static func verify(provenIdentityKeyID: String?, provenDeviceID: UUID?, pinned: PairedDeviceRef) -> Bool {
        guard let provenIdentityKeyID, let provenDeviceID else { return false }
        return provenIdentityKeyID == pinned.identityKeyID && provenDeviceID == pinned.deviceID
    }

    // MARK: - Mac: admission

    /// Whether a connection's path is a remote one: anything that isn't a
    /// local network the Allow prompt was designed for.
    public static func isRemotePath(link: LinkKind, remoteHost: String?) -> Bool {
        if RemoteHost.isOverlayAddress(remoteHost) { return true }
        // Loopback on the Mac means an SSH port forward or another relay.
        if LinkJudge.isLoopback(remoteHost) { return true }
        switch link {
        case .tunnel, .cellular:
            return true
        case .loopback:
            // Only an SSH port forward (or another local relay) brings a
            // remote's connection in over loopback.
            return true
        case .wired, .ethernet, .wifi, .peerToPeer, .other, .unknown:
            return false
        }
    }

    /// The Mac's decision for a connection, given the pairing decision and
    /// the path it arrived on. A remote path admits only paired devices.
    public static func admission(_ pairing: PairingAdmission, isRemotePath: Bool) -> PairingAdmission {
        guard isRemotePath else { return pairing }
        switch pairing {
        case .autoGrant: return pairing
        case .askUser, .refuse: return .refuse
        }
    }

    // MARK: - Mac: addresses to report

    /// Most addresses the Mac reports in `session.remoteHosts`.
    public static let maxReportedHosts = 4

    /// The Mac's own addresses a paired remote can save to reach it over a
    /// VPN: addresses on tunnel interfaces (`utun`, `wg`, `ipsec`, …) and
    /// any address in Tailscale's ranges, minus link-local, loopback and
    /// the like. Tailscale first, then other IPv4, then IPv6.
    ///
    /// - Parameter addressOwners: address → interface name, from
    ///   `InterfaceAddressTable.current()`.
    public static func reportableHosts(addressOwners: [String: String]) -> [String] {
        var hosts: [RemoteHost] = []
        for (address, interface) in addressOwners {
            let name = interface.lowercased()
            let onTunnel = LinkJudge.tunnelPrefixes.contains(where: name.hasPrefix)
            guard onTunnel || RemoteHost.isOverlayAddress(address),
                  LinkJudge.scope(of: address) == nil,
                  let host = RemoteHost(address),
                  host.kind != .publicIP || onTunnel,
                  !hosts.contains(host) else { continue }
            hosts.append(host)
        }
        func rank(_ h: RemoteHost) -> Int {
            switch h.kind {
            case .tailscaleIPv4: 0
            case .privateIPv4: 1
            case .tailscaleIPv6: 2
            case .uniqueLocalIPv6: 3
            default: 4
            }
        }
        return hosts
            .sorted { (rank($0), $0.value) < (rank($1), $1.value) }
            .prefix(maxReportedHosts)
            .map(\.value)
    }
}
