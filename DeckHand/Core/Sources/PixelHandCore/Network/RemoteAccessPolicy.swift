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
//  (a tunnel interface, an overlay address, or cellular) is admitted only
//  if it is already paired. No Allow prompt and no pairing code from
//  outside the local network. Loopback, and a peer at one of the Mac's
//  own addresses, is this same machine (a simulator, VQ-001) and counts
//  as local: the prompt and the code still need a
//  person at the Mac.
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

    // MARK: - Remote: testing a saved host

    /// What a probe of one saved host found (Settings › Remote Access ›
    /// Test). The probe answer is an advertisement, not proof: a match only
    /// says the right Mac answers there; the pinned handshake proves it.
    public enum ProbeVerdict: Equatable, Sendable {
        /// The paired Mac answered, advertising its stored key.
        case reachable
        /// A Pixel Hand Mac answered, but not this paired Mac (or with
        /// another key).
        case differentMac
        /// Nothing answered.
        case noAnswer

        public var message: String {
            switch self {
            case .reachable: "Reachable. Connect from the device list."
            case .differentMac: "Another Mac answered at this address."
            case .noAnswer: "No answer. Check that the VPN is on for both devices and Pixel Hand is open on the Mac."
            }
        }
    }

    public static func probeVerdict(
        answers: [(deviceID: UUID?, identityKeyID: String?)],
        mac: PairedDeviceRef
    ) -> ProbeVerdict {
        if answers.isEmpty { return .noAnswer }
        let match = answers.contains { $0.deviceID == mac.deviceID && $0.identityKeyID == mac.identityKeyID }
        return match ? .reachable : .differentMac
    }

    // MARK: - Mac: admission

    /// Where a connection came from, as far as admission cares.
    public enum PathClass: Equatable, Sendable {
        /// The same machine: a loopback address (`127.0.0.0/8`, `::1`, or
        /// an IPv4-mapped loopback), one of this Mac's own interface
        /// addresses, or anything carried over the loopback interface. A
        /// simulator on this Mac, or a process running here. Treated like
        /// the local network: the Allow prompt and the pairing code still
        /// need a person at the Mac.
        case sameMachine
        /// The local network (Wi-Fi, Ethernet, the USB cable, AWDL), link-
        /// local addresses included.
        case localNetwork
        /// Anything else: a tunnel interface, an overlay (Tailscale)
        /// address, or cellular. Only a paired device is admitted, pinned.
        case remote
    }

    /// Classifies a connection's path.
    ///
    /// 1. A loopback address, or one of this Mac's own addresses, is the
    ///    same machine whatever the link says. A peer elsewhere can't hold
    ///    the Mac's own address: replies to it never leave the Mac, so a
    ///    handshake from it can't complete. (VQ-001: a simulator dials the
    ///    Mac's Bonjour-resolved Wi-Fi address; the kernel carries it over
    ///    `lo0`, from that same address.)
    /// 2. Any other overlay (Tailscale) address is remote, whatever the
    ///    interface says.
    /// 3. The loopback interface is the same machine: only this Mac can
    ///    put a packet on `lo0`.
    /// 4. Tunnels and cellular are remote; everything else is the local
    ///    network.
    ///
    /// - Parameter ownAddresses: this Mac's interface addresses (the keys
    ///   of `InterfaceAddressTable.current()`). Link-local entries are
    ///   ignored: those are unique only per link, so another device can
    ///   hold the same one.
    public static func pathClass(link: LinkKind, remoteHost: String?, ownAddresses: Set<String> = []) -> PathClass {
        if LinkJudge.isLoopback(remoteHost) { return .sameMachine }
        if isOwnAddress(remoteHost, ownAddresses: ownAddresses) { return .sameMachine }
        if RemoteHost.isOverlayAddress(remoteHost) { return .remote }
        switch link {
        case .loopback:
            return .sameMachine
        case .tunnel, .cellular:
            return .remote
        case .wired, .ethernet, .wifi, .peerToPeer, .other, .unknown:
            return .localNetwork
        }
    }

    /// Whether `host` is one of `ownAddresses` (this Mac's interface
    /// addresses): compared without zone, brackets, case or an IPv4-mapped
    /// prefix. Link-local addresses never match.
    public static func isOwnAddress(_ host: String?, ownAddresses: Set<String>) -> Bool {
        guard let host, !host.isEmpty, !ownAddresses.isEmpty,
              !LinkJudge.isLinkLocal(host) else { return false }
        let normalized = normalizedAddress(host)
        return ownAddresses.contains { own in
            !LinkJudge.isLinkLocal(own) && normalizedAddress(own) == normalized
        }
    }

    private static func normalizedAddress(_ host: String) -> String {
        let h = LinkJudge.unscoped(host)
        if h.hasPrefix("::ffff:"), h.dropFirst(7).contains(".") { return String(h.dropFirst(7)) }
        return h
    }

    /// Whether a connection's path is a remote one: anything that isn't the
    /// local network or this same machine (VQ-001: a simulator on the Mac
    /// reaches it over loopback and must be able to pair).
    public static func isRemotePath(link: LinkKind, remoteHost: String?, ownAddresses: Set<String> = []) -> Bool {
        pathClass(link: link, remoteHost: remoteHost, ownAddresses: ownAddresses) == .remote
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
