//
//  RemoteHostBook.swift
//  PixelHandCore
//
//  S15: the remote's saved addresses for each paired Mac, used to reach it
//  over a VPN when Bonjour can't see it. Two sources per Mac:
//
//  - `.user`: typed in Settings › Remote Access. Kept until removed.
//  - `.mac`: the Mac's own tunnel addresses (`session.remoteHosts`), sent
//    while the two are connected. Each report replaces the previous one.
//
//  Hosts are only ever kept for Macs on the remote's pairing list, and
//  `seeds(pairedMacs:)` only hands out hosts of Macs still on it: a Mac
//  that was forgotten (or never paired) can't be dialled over a VPN.
//

import Foundation

public struct SavedRemoteHost: Codable, Hashable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case user
        case mac
    }

    public let host: RemoteHost
    public let source: Source
    public let addedAt: Date

    public var id: String { host.value }

    public init(host: RemoteHost, source: Source, addedAt: Date) {
        self.host = host
        self.source = source
        self.addedAt = addedAt
    }
}

public struct RemoteHostBook: Equatable, Sendable {
    public static let storageVersion = 1
    /// Hosts the user can save for one Mac.
    public static let maxUserHostsPerMac = 6
    /// Addresses kept from one Mac report.
    public static let maxReportedHostsPerMac = 4
    /// Macs with saved hosts.
    public static let maxMacs = 16

    public enum AddError: Error, Equatable, Sendable {
        case notPaired
        case invalid(RemoteHost.Rejection)
        case duplicate
        case full
    }

    /// Hosts per Mac, keyed on the Mac's verified identity.
    public private(set) var entries: [PairedDeviceRef: [SavedRemoteHost]]

    public init(entries: [PairedDeviceRef: [SavedRemoteHost]] = [:]) {
        self.entries = entries
    }

    public func hosts(for mac: PairedDeviceRef) -> [SavedRemoteHost] {
        entries[mac] ?? []
    }

    /// Saves a host the user typed for a paired Mac.
    @discardableResult
    public mutating func add(
        _ input: String,
        for mac: PairedDeviceRef,
        pairedMacs: TrustList,
        at now: Date
    ) -> Result<RemoteHost, AddError> {
        guard pairedMacs.device(mac) != nil else { return .failure(.notPaired) }
        let host: RemoteHost
        switch RemoteHost.parse(input) {
        case let .success(parsed): host = parsed
        case let .failure(rejection): return .failure(.invalid(rejection))
        }
        var list = entries[mac] ?? []
        if let existing = list.firstIndex(where: { $0.host == host }) {
            guard list[existing].source == .mac else { return .failure(.duplicate) }
            // The user now owns an address the Mac reported: keep it even
            // if the Mac stops reporting it.
            list.remove(at: existing)
        }
        guard list.filter({ $0.source == .user }).count < Self.maxUserHostsPerMac else {
            return .failure(.full)
        }
        guard entries[mac] != nil || entries.count < Self.maxMacs else { return .failure(.full) }
        list.append(SavedRemoteHost(host: host, source: .user, addedAt: now))
        entries[mac] = list
        return .success(host)
    }

    /// Replaces what a paired Mac reported about its own tunnel addresses.
    /// Invalid entries are skipped; hosts the user saved are kept.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func macReported(
        _ hosts: [String],
        mac: PairedDeviceRef,
        pairedMacs: TrustList,
        at now: Date
    ) -> Bool {
        guard pairedMacs.device(mac) != nil else { return false }
        let existing = entries[mac] ?? []
        let userHosts = existing.filter { $0.source == .user }
        let userValues = Set(userHosts.map(\.host))
        let previous = Dictionary(existing.filter { $0.source == .mac }.map { ($0.host, $0) }, uniquingKeysWith: { a, _ in a })

        var seen = Set<RemoteHost>()
        var reported: [SavedRemoteHost] = []
        for raw in hosts.prefix(Self.maxReportedHostsPerMac * 4) {
            guard let host = RemoteHost(raw), !userValues.contains(host), seen.insert(host).inserted else { continue }
            reported.append(previous[host] ?? SavedRemoteHost(host: host, source: .mac, addedAt: now))
            if reported.count == Self.maxReportedHostsPerMac { break }
        }
        let updated = userHosts + reported
        guard updated != existing else { return false }
        if updated.isEmpty {
            entries.removeValue(forKey: mac)
        } else {
            guard entries[mac] != nil || entries.count < Self.maxMacs else { return false }
            entries[mac] = updated
        }
        return true
    }

    @discardableResult
    public mutating func remove(_ host: RemoteHost, for mac: PairedDeviceRef) -> Bool {
        guard var list = entries[mac], let index = list.firstIndex(where: { $0.host == host }) else { return false }
        list.remove(at: index)
        entries[mac] = list.isEmpty ? nil : list
        return true
    }

    /// Drops the hosts of every Mac that is no longer paired.
    @discardableResult
    public mutating func prune(pairedMacs: TrustList) -> Bool {
        let before = entries.count
        entries = entries.filter { pairedMacs.device($0.key) != nil }
        return entries.count != before
    }

    /// The hosts to probe: those of Macs still on the pairing list, user
    /// hosts first, each host once.
    public func seeds(pairedMacs: TrustList) -> [RemoteHost] {
        var seen = Set<RemoteHost>()
        var result: [RemoteHost] = []
        let macs = entries.keys
            .filter { pairedMacs.device($0) != nil }
            .sorted { ($0.identityKeyID, $0.deviceID.uuidString) < ($1.identityKeyID, $1.deviceID.uuidString) }
        for mac in macs {
            let list = entries[mac] ?? []
            for saved in list.filter({ $0.source == .user }) + list.filter({ $0.source == .mac })
            where seen.insert(saved.host).inserted {
                result.append(saved.host)
            }
        }
        return result
    }

    // MARK: - Storage

    private struct Stored: Codable {
        var version: Int
        var macs: [StoredMac]
    }

    private struct StoredMac: Codable {
        var mac: PairedDeviceRef
        var hosts: [SavedRemoteHost]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let macs = entries
            .map { StoredMac(mac: $0.key, hosts: $0.value) }
            .sorted { ($0.mac.identityKeyID, $0.mac.deviceID.uuidString) < ($1.mac.identityKeyID, $1.mac.deviceID.uuidString) }
        return try encoder.encode(Stored(version: Self.storageVersion, macs: macs))
    }

    /// Decodes a stored book. Entries with invalid hosts fail the whole
    /// decode (`RemoteHost` re-validates), so the caller starts empty.
    public init(storage data: Data) throws {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.version == Self.storageVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported remote host book version \(stored.version)"))
        }
        var entries: [PairedDeviceRef: [SavedRemoteHost]] = [:]
        for mac in stored.macs.prefix(Self.maxMacs) where TrustList.isValidIdentityKeyID(mac.mac.identityKeyID) {
            var seen = Set<RemoteHost>()
            let user = mac.hosts.filter { $0.source == .user && seen.insert($0.host).inserted }.prefix(Self.maxUserHostsPerMac)
            let reported = mac.hosts.filter { $0.source == .mac && seen.insert($0.host).inserted }.prefix(Self.maxReportedHostsPerMac)
            let hosts = Array(user) + Array(reported)
            if !hosts.isEmpty { entries[mac.mac] = hosts }
        }
        self.init(entries: entries)
    }
}
