//
//  TransferSharedContainer.swift
//  DeckHandiOS – Transfer (also compiled into the Share extension)
//
//  S2: the folders the app and its Share extension share through the App
//  Group `group.com.widgetsflow.pixelhand`:
//
//      Transfers/
//        outbox.json          the app's outbox (only the app writes it)
//        Outbox/<id>/<file>   files waiting to go to a Mac
//        Dropbox/<id>/        what the Share extension adds:
//          item.json          a `TransferOutboxItem`
//          <file>             its file
//        macs.json            paired Macs for the extension's picker
//
//  The extension never touches `outbox.json`: it drops a folder, and the
//  app moves it into the outbox the next time it is active, so the two
//  processes never write the same file. A folder without `item.json` is
//  half-written and left alone until it is an hour old.
//
//  No UIKit or SwiftUI: the extension and the Linux type check use it.
//

import Foundation

enum TransferSharedContainer {
    static let appGroup = "group.com.widgetsflow.pixelhand"

    /// `Transfers/` in the App Group, or Application Support when the
    /// group isn't available (a build without the entitlement).
    static var root: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Transfers", isDirectory: true)
    }

    static var outboxFile: URL { root.appendingPathComponent("outbox.json") }
    static var outboxFolder: URL { root.appendingPathComponent("Outbox", isDirectory: true) }
    static var dropboxFolder: URL { root.appendingPathComponent("Dropbox", isDirectory: true) }
    static var macsFile: URL { root.appendingPathComponent("macs.json") }
    static let itemFileName = "item.json"

    static func outboxFile(for item: TransferOutboxItem) -> URL {
        outboxFolder.appendingPathComponent(item.id.uuidString, isDirectory: true).appendingPathComponent(item.fileName)
    }

    /// Paired Macs, as the app last wrote them.
    static func pairedMacs() -> [TransferMacEntry] {
        TransferMacEntry.decodeList(try? Data(contentsOf: macsFile))
    }

    static func writePairedMacs(_ macs: [TransferMacEntry]) {
        guard let data = try? JSONEncoder().encode(macs) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: macsFile, options: .atomic)
    }

    private static let sharingAllowedKey = "transfer.sharingAllowed"

    /// Whether this device has Pixel Hand Pro, as the app last saw it, so
    /// the Share extension (which has no StoreKit state) can say so before
    /// queueing. The app checks again before sending.
    static var sharingAllowed: Bool {
        UserDefaults(suiteName: appGroup)?.bool(forKey: sharingAllowedKey) ?? false
    }

    static func setSharingAllowed(_ allowed: Bool) {
        UserDefaults(suiteName: appGroup)?.set(allowed, forKey: sharingAllowedKey)
    }

    /// Drops one item for the app (the Share extension). `fill` writes
    /// the payload into the given URL. The item's description goes last,
    /// so the app never picks up a half-written folder.
    static func drop(_ item: TransferOutboxItem, fill: (URL) throws -> Void) throws {
        let folder = dropboxFolder.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try fill(folder.appendingPathComponent(item.fileName))
            let data = try JSONEncoder().encode(item)
            try data.write(to: folder.appendingPathComponent(itemFileName), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Moves every finished drop into the outbox folder and returns their
    /// items (the app adds them to `outbox.json`).
    static func collectDrops() -> [TransferOutboxItem] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dropboxFolder.path) else { return [] }
        var items: [TransferOutboxItem] = []
        for name in names {
            let folder = dropboxFolder.appendingPathComponent(name, isDirectory: true)
            let itemURL = folder.appendingPathComponent(itemFileName)
            guard let data = try? Data(contentsOf: itemURL),
                  let item = try? JSONDecoder().decode(TransferOutboxItem.self, from: data) else {
                let date = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                if Date().timeIntervalSince(date) > 3600 { try? fm.removeItem(at: folder) }
                continue
            }
            let destination = outboxFolder.appendingPathComponent(item.id.uuidString, isDirectory: true)
            do {
                try fm.createDirectory(at: outboxFolder, withIntermediateDirectories: true)
                try? fm.removeItem(at: itemURL)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: folder, to: destination)
                items.append(item)
            } catch {
                try? fm.removeItem(at: folder)
            }
        }
        return items
    }
}
