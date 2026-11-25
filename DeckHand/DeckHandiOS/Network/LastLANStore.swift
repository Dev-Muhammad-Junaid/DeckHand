//
//  LastLANStore.swift
//  DeckHandiOS
//
//  VQ-069: the paired Macs' last LAN addresses (`LastLANBook` in Core) on
//  disk. The session records the address it runs over on Wi-Fi or
//  Ethernet; `RemoteHostsStore.currentSeeds()` hands them to Loom's
//  overlay directory with the VPN hosts, so a paired Mac answers even
//  while Bonjour is quiet. Dialling such a Mac goes through
//  `RemoteConnect` (paired only, key pinned).
//

import Foundation

@MainActor
final class LastLANStore {
    static let shared = LastLANStore()

    private var book: LastLANBook
    private let fileURL: URL?
    private let pairing: PairedMacsStore

    init(fileURL: URL? = LastLANStore.defaultFileURL, pairing: PairedMacsStore = .shared) {
        self.fileURL = fileURL
        self.pairing = pairing
        book = Self.load(from: fileURL)
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LastLANAddresses.json")
    }

    private var pairedMacs: TrustList { TrustList(devices: pairing.macs) }

    /// The session to `mac` runs over `host` on `link`.
    func sessionRan(overHost host: String?, link: LinkKind, mac: PairedDeviceRef) {
        guard book.sessionRan(overHost: host, link: link, mac: mac, pairedMacs: pairedMacs, at: Date()) else { return }
        DeckHandLog.connection.info("Saved the paired Mac's LAN address for when Bonjour is quiet")
        save()
    }

    /// The addresses to probe, paired Macs only. Also drops forgotten Macs
    /// from disk.
    func currentSeeds() -> [RemoteHost] {
        let paired = pairedMacs
        if book.prune(pairedMacs: paired) { save() }
        return book.seeds(pairedMacs: paired, now: Date())
    }

    // MARK: - Storage

    private static func load(from url: URL?) -> LastLANBook {
        guard let url, let data = try? Data(contentsOf: url) else { return LastLANBook() }
        do {
            return try LastLANBook(storage: data)
        } catch {
            // Fail closed: a file that doesn't validate is set aside.
            DeckHandLog.connection.error("Last LAN addresses unreadable, starting empty: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: url)
            return LastLANBook()
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try book.encoded().write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            DeckHandLog.connection.error("Saving last LAN addresses failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
