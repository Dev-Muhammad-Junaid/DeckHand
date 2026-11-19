//
//  RemoteHostsStore.swift
//  DeckHandiOS
//
//  S15: the addresses this device uses to reach its paired Macs over a VPN
//  (Tailscale, WireGuard, …) when Bonjour can't see them. PixelHandCore's
//  `RemoteHostBook` holds the rules; this file keeps it on disk, feeds
//  Loom's overlay directory, and serves Settings › Remote Access.
//
//  Only paired Macs (PairedMacsStore) get hosts, and only their hosts are
//  probed: forgetting a Mac drops its addresses from the probe list at once.
//

import Foundation
import LoomKit
import Observation

@MainActor
@Observable
final class RemoteHostsStore {
    static let shared = RemoteHostsStore()

    /// Bumped on every change, for views.
    private(set) var revision = 0
    @ObservationIgnored private var book: RemoteHostBook
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let pairing: PairedMacsStore

    init(fileURL: URL? = RemoteHostsStore.defaultFileURL, pairing: PairedMacsStore = .shared) {
        self.fileURL = fileURL
        self.pairing = pairing
        book = Self.load(from: fileURL)
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RemoteHosts.json")
    }

    /// The pairing list as Core sees it.
    var pairedMacs: TrustList { TrustList(devices: pairing.macs) }

    func hosts(for mac: PairedDeviceRef) -> [SavedRemoteHost] {
        _ = revision
        return book.hosts(for: mac)
    }

    /// Saves a typed host for a paired Mac.
    func add(_ input: String, for mac: PairedDeviceRef) -> Result<RemoteHost, RemoteHostBook.AddError> {
        let result = book.add(input, for: mac, pairedMacs: pairedMacs, at: Date())
        if case .success = result { changed() }
        return result
    }

    func remove(_ host: RemoteHost, for mac: PairedDeviceRef) {
        if book.remove(host, for: mac) { changed() }
    }

    /// The Mac's `session.remoteHosts`, for the Mac of the live session.
    /// Ignored unless that Mac is paired.
    func macReported(_ hosts: [String], mac: PairedDeviceRef) {
        if book.macReported(hosts, mac: mac, pairedMacs: pairedMacs, at: Date()) {
            DeckHandLog.connection.info("Remote access: saved \(self.book.hosts(for: mac).filter { $0.source == .mac }.count, privacy: .public) VPN address(es) the Mac reported")
            changed()
        }
    }

    /// What Loom's overlay directory probes: hosts of Macs still paired.
    /// Also drops the hosts of forgotten Macs from disk.
    func currentSeeds() -> [LoomOverlaySeed] {
        let paired = pairedMacs
        if book.prune(pairedMacs: paired) { changed() }
        return book.seeds(pairedMacs: paired).map { LoomOverlaySeed(host: $0.value) }
    }

    // MARK: - Loom

    /// The remote's overlay directory: probes each saved host on Loom's
    /// default overlay probe port; a Mac that answers shows up in the
    /// picker as a non-nearby peer. Dialling it goes through `RemoteConnect`
    /// (paired only, key pinned).
    static let overlayConfiguration = LoomOverlayDirectoryConfiguration(
        refreshInterval: .seconds(30),
        probeTimeout: .seconds(2),
        probeAttempts: 2,
        probeRetryDelay: .milliseconds(400),
        seedProvider: {
            await MainActor.run { RemoteHostsStore.shared.currentSeeds() }
        }
    )

    // MARK: - Storage

    private func changed() {
        revision &+= 1
        save()
    }

    private static func load(from url: URL?) -> RemoteHostBook {
        guard let url, let data = try? Data(contentsOf: url) else { return RemoteHostBook() }
        do {
            return try RemoteHostBook(storage: data)
        } catch {
            // Fail closed: a file that doesn't validate is set aside.
            DeckHandLog.connection.error("Remote hosts file unreadable, starting empty: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: url)
            return RemoteHostBook()
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try book.encoded().write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            DeckHandLog.connection.error("Saving remote hosts failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
