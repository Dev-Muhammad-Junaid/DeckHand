//
//  TrustList.swift
//  PixelHandCore
//
//  Paired devices, keyed on the Loom identity key each one proved in the
//  session handshake (`LoomPeerIdentity.identityKeyID`, a SHA-256 of the
//  device's P-256 public key). The Mac keeps one for its remotes, and each
//  remote keeps one for its Macs.
//
//  Rules:
//
//  - Only the identity key decides. A device ID, a name or anything a peer
//    advertises is display data; a record never matches on them. A device
//    that presents a known device ID with a different key is a stranger.
//  - One record per key, and one key per device ID: pairing a device again
//    with a new key (reinstall, new keychain) replaces its old record, so
//    the old key stops being trusted.
//  - Forgetting removes the record. Nothing is kept for a forgotten key.
//  - At most `capacity` records; pairing one more drops the device seen
//    least recently.
//  - Names are cleaned (no control characters, at most
//    `maxNameLength`) because they come from the peer.
//
//  This is the trust store the Mac's `DeckHandHandshakeTrustProvider` and
//  `DeviceAuthorizationManager` read, and what remote access (S15) builds
//  on: a remote reaching the Mac from outside the local network must be on
//  this list. See `PairingAdmission` for the per-connection decision.
//

import Foundation

/// What kind of device a record is, for the icon next to its name.
public enum PairedDeviceKind: String, Codable, Sendable, CaseIterable {
    case mac
    case iPad
    case iPhone
    case vision
    case other

    /// Unknown raw values decode as `.other`, so a newer build's kind never
    /// makes the whole list unreadable.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PairedDeviceKind(rawValue: raw) ?? .other
    }
}

/// How a device came to be paired.
public enum PairingMethod: String, Codable, Sendable {
    /// The remote entered or scanned the Mac's code.
    case code
    /// The Mac's user allowed it and chose to remember it.
    case approval
    /// A remote's own record of a Mac it paired with.
    case remoteRecord

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PairingMethod(rawValue: raw) ?? .approval
    }
}

/// One paired device.
public struct PairedDevice: Codable, Equatable, Sendable, Identifiable {
    /// The Loom identity key ID. The only field trust is decided on.
    public let identityKeyID: String
    /// The Loom device ID last seen with this key. Display and bookkeeping
    /// only (Loom's `revokeTrust(for:)` is keyed on it).
    public var deviceID: UUID
    public var name: String
    public var kind: PairedDeviceKind
    public let method: PairingMethod
    public let pairedAt: Date
    public var lastSeenAt: Date

    public var id: String { identityKeyID }

    public init(
        identityKeyID: String,
        deviceID: UUID,
        name: String,
        kind: PairedDeviceKind,
        method: PairingMethod,
        pairedAt: Date,
        lastSeenAt: Date
    ) {
        self.identityKeyID = identityKeyID
        self.deviceID = deviceID
        self.name = TrustList.cleanName(name)
        self.kind = kind
        self.method = method
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }
}

/// A device asking to be trusted, as the handshake proved it.
public struct TrustCandidate: Equatable, Sendable {
    public let identityKeyID: String
    public let deviceID: UUID
    public let name: String
    public let kind: PairedDeviceKind

    public init(identityKeyID: String, deviceID: UUID, name: String, kind: PairedDeviceKind) {
        self.identityKeyID = identityKeyID
        self.deviceID = deviceID
        self.name = name
        self.kind = kind
    }
}

public struct TrustList: Equatable, Sendable {
    /// Most records kept.
    public static let capacity = 64
    /// Longest stored name, in characters.
    public static let maxNameLength = 64
    /// Shortest and longest identity key ID accepted. Loom's are 64 hex
    /// characters; the range leaves room without accepting junk.
    public static let identityKeyIDLength: ClosedRange<Int> = 16...128

    public enum TrustError: Error, Equatable, Sendable {
        case invalidIdentityKeyID
    }

    /// Records, oldest pairing first.
    public private(set) var devices: [PairedDevice]

    public init(devices: [PairedDevice] = []) {
        self.devices = []
        for device in devices.sorted(by: { $0.pairedAt < $1.pairedAt }) {
            guard Self.isValidIdentityKeyID(device.identityKeyID) else { continue }
            var cleaned = device
            cleaned.name = Self.cleanName(device.name)
            insert(cleaned)
        }
    }

    // MARK: - Reading

    public var isEmpty: Bool { devices.isEmpty }

    /// The record for `identityKeyID`, if that key is trusted.
    public func device(identityKeyID: String?) -> PairedDevice? {
        guard let identityKeyID, !identityKeyID.isEmpty else { return nil }
        return devices.first { $0.identityKeyID == identityKeyID }
    }

    /// Whether a device that proved `identityKeyID` is paired.
    public func isTrusted(identityKeyID: String?) -> Bool {
        device(identityKeyID: identityKeyID) != nil
    }

    // MARK: - Changing

    /// Pairs `candidate`, or refreshes its record if its key is already
    /// paired (keeping the original pairing date and method). Any other
    /// record for the same device ID is dropped: the device has a new key.
    ///
    /// - Returns: The stored record.
    @discardableResult
    public mutating func trust(_ candidate: TrustCandidate, method: PairingMethod, at now: Date) throws -> PairedDevice {
        guard Self.isValidIdentityKeyID(candidate.identityKeyID) else {
            throw TrustError.invalidIdentityKeyID
        }
        if let index = devices.firstIndex(where: { $0.identityKeyID == candidate.identityKeyID }) {
            devices[index].deviceID = candidate.deviceID
            devices[index].name = Self.cleanName(candidate.name)
            devices[index].kind = candidate.kind
            devices[index].lastSeenAt = now
            devices.removeAll { $0.deviceID == candidate.deviceID && $0.identityKeyID != candidate.identityKeyID }
            return devices.first { $0.identityKeyID == candidate.identityKeyID }!
        }
        devices.removeAll { $0.deviceID == candidate.deviceID }
        let record = PairedDevice(
            identityKeyID: candidate.identityKeyID,
            deviceID: candidate.deviceID,
            name: candidate.name,
            kind: candidate.kind,
            method: method,
            pairedAt: now,
            lastSeenAt: now
        )
        insert(record)
        return record
    }

    /// Stamps a paired device as seen and takes its current name. Does
    /// nothing for a key that isn't paired.
    ///
    /// - Returns: Whether a record changed.
    @discardableResult
    public mutating func noteSeen(identityKeyID: String, name: String?, at now: Date) -> Bool {
        guard let index = devices.firstIndex(where: { $0.identityKeyID == identityKeyID }) else { return false }
        devices[index].lastSeenAt = now
        if let name {
            devices[index].name = Self.cleanName(name)
        }
        return true
    }

    /// Forgets the device with `identityKeyID`.
    ///
    /// - Returns: The removed record, or `nil` if it wasn't paired.
    @discardableResult
    public mutating func revoke(identityKeyID: String) -> PairedDevice? {
        guard let index = devices.firstIndex(where: { $0.identityKeyID == identityKeyID }) else { return nil }
        return devices.remove(at: index)
    }

    /// Forgets every record last seen with `deviceID` (Loom's
    /// `revokeTrust(for:)` hook is keyed on the device ID).
    ///
    /// - Returns: The removed records.
    @discardableResult
    public mutating func revokeAll(deviceID: UUID) -> [PairedDevice] {
        let removed = devices.filter { $0.deviceID == deviceID }
        devices.removeAll { $0.deviceID == deviceID }
        return removed
    }

    public mutating func removeAll() {
        devices.removeAll()
    }

    // MARK: - Rules

    /// Loom key IDs are hex; this accepts ASCII letters, digits, `-`, `_`,
    /// `.` and `:` within `identityKeyIDLength`.
    public static func isValidIdentityKeyID(_ keyID: String) -> Bool {
        guard identityKeyIDLength.contains(keyID.utf8.count) else { return false }
        return keyID.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".", ":": true
            default: false
            }
        }
    }

    /// A peer-supplied name made safe to show: control and format
    /// characters dropped, whitespace trimmed, at most `maxNameLength`
    /// characters, "Unnamed device" when nothing is left.
    public static func cleanName(_ name: String) -> String {
        let kept = name.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned, .privateUse:
                false
            default:
                true
            }
        }
        var cleaned = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > maxNameLength {
            cleaned = String(cleaned.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        }
        return cleaned.isEmpty ? "Unnamed device" : cleaned
    }

    private mutating func insert(_ record: PairedDevice) {
        devices.removeAll { $0.identityKeyID == record.identityKeyID }
        devices.append(record)
        while devices.count > Self.capacity {
            // Drop the device seen least recently (ties: paired earliest).
            guard let stalest = devices.indices.min(by: {
                (devices[$0].lastSeenAt, devices[$0].pairedAt) < (devices[$1].lastSeenAt, devices[$1].pairedAt)
            }) else { break }
            devices.remove(at: stalest)
        }
    }
}

// MARK: - Storage

extension TrustList {
    /// The on-disk format's version.
    public static let storageVersion = 1

    private struct Stored: Codable {
        var version: Int
        var devices: [StoredDevice]
    }

    /// A record as stored, decoded leniently: one bad record is skipped,
    /// not the whole list.
    private struct StoredDevice: Codable {
        var device: PairedDevice?

        init(_ device: PairedDevice) { self.device = device }

        init(from decoder: Decoder) throws {
            device = try? PairedDevice(from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            try device?.encode(to: encoder)
        }
    }

    /// Encodes the list for storage.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(Stored(version: Self.storageVersion, devices: devices.map(StoredDevice.init)))
    }

    /// Reads a stored list. A newer storage version, or data that isn't a
    /// list at all, throws; the caller decides whether to start empty.
    /// Records with an invalid key are dropped.
    public init(storage data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let stored = try decoder.decode(Stored.self, from: data)
        guard stored.version == Self.storageVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported trust list version \(stored.version)"))
        }
        self.init(devices: stored.devices.compactMap(\.device))
    }
}
