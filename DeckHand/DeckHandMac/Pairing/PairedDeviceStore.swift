//
//  PairedDeviceStore.swift
//  DeckHandMac
//
//  The Mac's paired remotes (S4): PixelHandCore's `TrustList`, kept in
//  `~/Library/Application Support/Pixel Hand/PairedDevices.json` (owner
//  read/write only) and published for the menu bar.
//
//  Who uses it:
//  - `DeckHandHandshakeTrustProvider` (Loom's trust hooks): `grantTrust`
//    and `revokeTrust` land here.
//  - `DeviceAuthorizationManager`: `admission(for:)` decides whether a new
//    connection skips the Allow prompt; pairing by code and "Forget" change
//    the list.
//  - Remote access over VPN (S15) should admit only devices for which
//    `admission(for:)` is `.autoGrant`.
//
//  A file that can't be read is set aside (renamed `.unreadable`) and the
//  list starts empty: failing closed means paired devices get the Allow
//  prompt again, never that a stranger is let in.
//

import Combine
import Foundation
import Loom

@MainActor
final class PairedDeviceStore: ObservableObject {
    static let shared = PairedDeviceStore()

    /// Paired remotes, oldest pairing first.
    @Published private(set) var devices: [PairedDevice] = []

    private var list: TrustList {
        didSet { devices = list.devices }
    }
    private let fileURL: URL?

    /// - Parameter fileURL: Where to keep the list; `nil` keeps it in
    ///   memory only (tests, or no Application Support directory).
    init(fileURL: URL? = PairedDeviceStore.defaultFileURL) {
        self.fileURL = fileURL
        list = Self.load(from: fileURL)
        devices = list.devices
    }

    static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support
            .appendingPathComponent("Pixel Hand", isDirectory: true)
            .appendingPathComponent("PairedDevices.json")
    }

    // MARK: - Reading

    /// What to do with a connection whose identity Loom verified.
    func admission(for identity: LoomPeerIdentity?) -> PairingAdmission {
        guard let identity, let candidate = TrustCandidate(identity: identity) else { return .refuse }
        return PairingAdmission.decide(
            identityKeyID: candidate.identityKeyID,
            deviceID: candidate.deviceID,
            isIdentityAuthenticated: true,
            trustList: list
        )
    }

    func isPaired(_ ref: PairedDeviceRef) -> Bool {
        list.device(ref) != nil
    }

    // MARK: - Changing

    /// Pairs a device. Throws only for an invalid key ID, which
    /// `TrustCandidate(identity:)` already rules out.
    @discardableResult
    func pair(_ candidate: TrustCandidate, method: PairingMethod) throws -> PairedDevice {
        let record = try list.trust(candidate, method: method, at: Date())
        save()
        DeckHandLog.trust.info("🔐 Paired \(record.name, privacy: .public) (\(method.rawValue, privacy: .public)) key=\(record.identityKeyID.prefix(12), privacy: .public)…")
        return record
    }

    /// Stamps a paired device as seen, taking its current name.
    func noteSeen(_ candidate: TrustCandidate) {
        guard list.noteSeen(candidate.ref, name: candidate.name, at: Date()) else { return }
        save()
    }

    /// Forgets one device. Returns the removed record.
    @discardableResult
    func forget(_ ref: PairedDeviceRef) -> PairedDevice? {
        guard let removed = list.revoke(ref) else { return nil }
        save()
        DeckHandLog.trust.info("🔐 Forgot \(removed.name, privacy: .public) key=\(removed.identityKeyID.prefix(12), privacy: .public)…")
        return removed
    }

    /// Loom's `revokeTrust(for:)` hook: forgets whatever was paired with
    /// `deviceID`.
    @discardableResult
    func forgetAll(deviceID: UUID) -> [PairedDevice] {
        let removed = list.revokeAll(deviceID: deviceID)
        if !removed.isEmpty { save() }
        return removed
    }

    // MARK: - Storage

    private static func load(from url: URL?) -> TrustList {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return TrustList() }
        do {
            return try TrustList(storage: Data(contentsOf: url))
        } catch {
            DeckHandLog.trust.error("Paired devices file unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            let aside = url.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return TrustList()
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try list.encoded()
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            DeckHandLog.trust.error("Saving paired devices failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
