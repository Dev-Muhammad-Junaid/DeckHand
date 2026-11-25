//
//  LastLANBook.swift
//  PixelHandCore – Network
//
//  VQ-069: when Bonjour is quiet (it sometimes takes 45 s or more after a
//  launch to see the Mac), the picker also tries the paired Mac's last LAN
//  address. This book keeps one address per paired Mac: the private address
//  the session last ran over on Wi-Fi or Ethernet. The remote's overlay
//  directory probes it next to the saved VPN hosts (`RemoteHostBook`), and
//  a Mac that answers is dialled the remote way: paired only, pinned to the
//  key stored when it paired (`RemoteAccessPolicy`). Forgetting a Mac drops
//  its address at once.
//
//  `LANFallbackPlan` says when the picker asks Loom to probe again while no
//  Mac is listed.
//

import Foundation

/// The last LAN address a paired Mac was reached at.
public struct LastLANAddress: Codable, Hashable, Sendable {
    public let host: RemoteHost
    public let seenAt: Date

    public init(host: RemoteHost, seenAt: Date) {
        self.host = host
        self.seenAt = seenAt
    }
}

public struct LastLANBook: Equatable, Sendable {
    public static let storageVersion = 1
    /// Same cap as the VPN host book.
    public static let maxMacs = 16
    /// An address older than this is no longer probed: DHCP leases move on.
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    public private(set) var entries: [PairedDeviceRef: LastLANAddress]

    public init(entries: [PairedDeviceRef: LastLANAddress] = [:]) {
        self.entries = entries
    }

    public func address(for mac: PairedDeviceRef) -> LastLANAddress? {
        entries[mac]
    }

    /// Whether `link` is a LAN the address is worth keeping for. A USB
    /// cable (link-local), a VPN, cellular, loopback (the Simulator) and
    /// unknown links are not.
    public static func isLAN(_ link: LinkKind) -> Bool {
        switch link {
        case .wifi, .ethernet: true
        case .wired, .peerToPeer, .tunnel, .cellular, .loopback, .other, .unknown: false
        }
    }

    /// Whether `host` may be kept: a private IPv4 or a unique-local IPv6
    /// address. Public addresses, names and Tailscale ranges are not LAN
    /// addresses (VPN hosts live in `RemoteHostBook`).
    public static func lanHost(_ raw: String?) -> RemoteHost? {
        guard let raw else { return nil }
        guard let host = RemoteHost(LinkJudge.unscoped(raw)) else { return nil }
        switch host.kind {
        case .privateIPv4, .uniqueLocalIPv6: return host
        default: return nil
        }
    }

    /// Records the address a session to `mac` runs over. Ignored unless the
    /// Mac is paired, the link is a LAN and the address is private.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func sessionRan(
        overHost raw: String?,
        link: LinkKind,
        mac: PairedDeviceRef,
        pairedMacs: TrustList,
        at now: Date
    ) -> Bool {
        guard Self.isLAN(link),
              pairedMacs.device(mac) != nil,
              let host = Self.lanHost(raw) else { return false }
        if let existing = entries[mac], existing.host == host,
           now.timeIntervalSince(existing.seenAt) < 24 * 60 * 60 {
            // Same address, seen within a day: don't rewrite the file.
            return false
        }
        guard entries[mac] != nil || entries.count < Self.maxMacs else { return false }
        entries[mac] = LastLANAddress(host: host, seenAt: now)
        return true
    }

    /// Drops the address of every Mac that is no longer paired.
    @discardableResult
    public mutating func prune(pairedMacs: TrustList) -> Bool {
        let before = entries.count
        entries = entries.filter { pairedMacs.device($0.key) != nil }
        return entries.count != before
    }

    /// The addresses to probe: paired Macs only, newest first, none older
    /// than `maxAge`, each host once.
    public func seeds(pairedMacs: TrustList, now: Date) -> [RemoteHost] {
        var seen = Set<RemoteHost>()
        return entries
            .filter { pairedMacs.device($0.key) != nil && now.timeIntervalSince($0.value.seenAt) <= Self.maxAge }
            .map(\.value)
            .sorted { ($0.seenAt, $0.host.value) > ($1.seenAt, $1.host.value) }
            .compactMap { seen.insert($0.host).inserted ? $0.host : nil }
    }

    // MARK: - Storage

    private struct Stored: Codable {
        var version: Int
        var macs: [StoredMac]
    }

    private struct StoredMac: Codable {
        var mac: PairedDeviceRef
        var address: LastLANAddress
    }

    public enum StorageError: Error, Equatable {
        case unsupportedVersion(Int)
        case invalidHost
    }

    public func encoded() throws -> Data {
        let macs = entries
            .sorted { ($0.key.identityKeyID, $0.key.deviceID.uuidString) < ($1.key.identityKeyID, $1.key.deviceID.uuidString) }
            .map { StoredMac(mac: $0.key, address: $0.value) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(Stored(version: Self.storageVersion, macs: macs))
    }

    /// Reads a stored book. Fails closed: a wrong version or an address
    /// that no longer passes `lanHost` throws, and the caller starts empty.
    public init(storage data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let stored = try decoder.decode(Stored.self, from: data)
        guard stored.version == Self.storageVersion else { throw StorageError.unsupportedVersion(stored.version) }
        var entries: [PairedDeviceRef: LastLANAddress] = [:]
        for item in stored.macs.prefix(Self.maxMacs) {
            guard Self.lanHost(item.address.host.value) == item.address.host else { throw StorageError.invalidHost }
            entries[item.mac] = item.address
        }
        self.entries = entries
    }
}

/// When the picker asks Loom to look again while no Mac is listed.
public enum LANFallbackPlan {
    /// Seconds after the picker went quiet at which it refreshes discovery
    /// (Bonjour and the overlay probe of saved and last-LAN addresses).
    /// The three checks still show at 10 s (`checksDelay`).
    public static let refreshTimes: [Double] = [2, 5, 9, 15, 25, 40]
    /// No Mac after this long: show the three checks with Try again.
    public static let checksDelay: Double = 10

    /// The refresh times, as gaps from the previous one.
    public static var refreshGaps: [Double] {
        zip(refreshTimes, [0] + refreshTimes).map { $0 - $1 }
    }

    /// Whether the picker should refresh: only while no Mac is listed and
    /// discovery is running. A refresh restarts the Bonjour browse too, so
    /// it's worth doing even with no saved address.
    public static func shouldRefresh(peersListed: Bool, discoveryRunning: Bool) -> Bool {
        !peersListed && discoveryRunning
    }
}
