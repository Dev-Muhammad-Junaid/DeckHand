//
//  PairingAdmission.swift
//  PixelHandCore
//
//  What the Mac does with a new connection, from the identity the Loom
//  handshake proved and the Mac's `TrustList` (S4):
//
//  - A paired key connects without the Allow prompt.
//  - A proven but unknown key gets the Allow / Deny prompt, and may pair
//    with the Mac's code while it waits.
//  - A connection without a proven key is refused. Loom's handshake (through
//    `DeckHandHandshakeTrustProvider`) already refuses these; this is the
//    second lock on the same door.
//

import Foundation

public enum PairingAdmission: Equatable, Sendable {
    /// Paired: grant at once, no prompt.
    case autoGrant(PairedDevice)
    /// Unknown but proven: ask the user (or take a pairing code).
    case askUser(PairedDeviceRef)
    /// No proven identity key: disconnect.
    case refuse

    /// - Parameters:
    ///   - identityKeyID: `LoomPeerIdentity.identityKeyID` from the session
    ///     context, or `nil` when the context is missing.
    ///   - deviceID: `LoomPeerIdentity.deviceID` (signed by that key).
    ///   - isIdentityAuthenticated: `LoomPeerIdentity.isIdentityAuthenticated`.
    ///   - trustList: The Mac's paired devices.
    public static func decide(
        identityKeyID: String?,
        deviceID: UUID?,
        isIdentityAuthenticated: Bool,
        trustList: TrustList
    ) -> PairingAdmission {
        guard isIdentityAuthenticated,
              let identityKeyID,
              let deviceID,
              TrustList.isValidIdentityKeyID(identityKeyID) else {
            return .refuse
        }
        if let device = trustList.device(identityKeyID: identityKeyID, deviceID: deviceID) {
            return .autoGrant(device)
        }
        return .askUser(PairedDeviceRef(identityKeyID: identityKeyID, deviceID: deviceID))
    }
}

/// A remote's record of the Macs it is paired with, plus the Macs it was
/// told to forget while they were out of reach (S4).
///
/// The Mac's `pairing.pairedStatus` is the source of truth: the remote
/// records a Mac when the Mac says it is paired, and drops it when the Mac
/// says it isn't. "Forget" on the remote removes the record at once; if
/// that Mac isn't connected, the remote remembers to send `pairing.forget`
/// the next time the Mac reports it as paired.
public struct RemotePairingBook: Equatable, Sendable {
    /// Most forgets held for Macs that are out of reach.
    public static let maxPendingForgets = 32

    public private(set) var macs: TrustList
    /// Macs to send `pairing.forget` to on next contact.
    public private(set) var pendingForgets: [PairedDeviceRef]

    public init(macs: TrustList = TrustList(), pendingForgets: [PairedDeviceRef] = []) {
        self.macs = macs
        self.pendingForgets = Array(
            pendingForgets.filter { TrustList.isValidIdentityKeyID($0.identityKeyID) }.suffix(Self.maxPendingForgets)
        )
    }

    /// What the remote should do after the Mac reported its pairing.
    public enum Action: Equatable, Sendable {
        case none
        /// The Mac is now on this remote's list (or its record refreshed).
        case recorded
        /// The Mac was on the list and no longer is.
        case removed
        /// The user forgot this Mac while it was away: send `pairing.forget`.
        case sendForget
    }

    /// Applies the Mac's `pairedStatus(paired:)`.
    ///
    /// - Parameter mac: The Mac as the handshake proved it on this remote.
    public mutating func macReported(paired: Bool, mac: TrustCandidate, at now: Date) -> Action {
        if pendingForgets.contains(mac.ref) {
            pendingForgets.removeAll { $0 == mac.ref }
            macs.revoke(mac.ref)
            return paired ? .sendForget : .none
        }
        if paired {
            return (try? macs.trust(mac, method: .remoteRecord, at: now)) == nil ? .none : .recorded
        }
        return macs.revoke(mac.ref) == nil ? .none : .removed
    }

    /// The user chose "Forget" for a Mac.
    ///
    /// - Parameters:
    ///   - isConnected: Whether a session with that Mac is live. If it is,
    ///     the caller sends `pairing.forget` now; if not, the forget is
    ///     held for the next contact.
    /// - Returns: The removed record, if there was one.
    @discardableResult
    public mutating func forget(_ mac: PairedDeviceRef, isConnected: Bool) -> PairedDevice? {
        let removed = macs.revoke(mac)
        if !isConnected, TrustList.isValidIdentityKeyID(mac.identityKeyID), !pendingForgets.contains(mac) {
            pendingForgets.append(mac)
            if pendingForgets.count > Self.maxPendingForgets {
                pendingForgets.removeFirst(pendingForgets.count - Self.maxPendingForgets)
            }
        }
        return removed
    }

    // MARK: - Storage

    private struct Stored: Codable {
        var version: Int
        var macs: Data
        var pendingForgets: [PairedDeviceRef]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Stored(version: TrustList.storageVersion, macs: macs.encoded(), pendingForgets: pendingForgets))
    }

    public init(storage data: Data) throws {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.version == TrustList.storageVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported pairing book version \(stored.version)"))
        }
        self.init(macs: try TrustList(storage: stored.macs), pendingForgets: stored.pendingForgets)
    }
}
