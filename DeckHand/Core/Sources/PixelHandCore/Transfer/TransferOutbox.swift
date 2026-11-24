//
//  TransferOutbox.swift
//  PixelHandCore
//
//  S1/S2: items waiting to go to a Mac. The device keeps them on disk
//  (in the App Group, so the Share extension can add to it) until the Mac
//  says it saved or refused them, so a dropped connection resumes instead
//  of starting over:
//
//  - Each item's id is also its Loom transfer id. Offered again after a
//    reconnect with the same id, the Mac finds its partial file and
//    accepts from where it stopped (`TransferResume`).
//  - An item names the Mac it is for, or none ("the next Mac I connect
//    to", the Share extension's default when only one Mac is paired).
//  - Cancel removes the item and its partial on both ends.
//  - Interrupted items retry on the next connection, up to `maxAttempts`;
//    refused ones are dropped at once (with the reason shown).
//
//  Pure value type; the app stores it as JSON (`encoded()`).
//

import Foundation

public struct TransferOutboxItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    public enum State: String, Codable, Sendable, Hashable {
        /// Waiting for its Mac to connect.
        case queued
        /// Offered or moving bytes on the current connection.
        case sending
        /// Interrupted; offered again on the next connection.
        case paused
    }

    public let id: UUID
    public var kind: TransferKind
    /// The file's name inside the item's folder; also the offered name.
    public var fileName: String
    public var byteCount: UInt64
    public var contentType: String?
    /// The Mac's Loom device ID, or `nil` for the next Mac that connects.
    public var targetDeviceID: UUID?
    /// The Mac's name when the item was made, for "Waiting for Studio".
    public var targetName: String?
    public var createdAt: Date
    public var attempts: Int
    public var state: State

    public init(
        id: UUID = UUID(),
        kind: TransferKind,
        fileName: String,
        byteCount: UInt64,
        contentType: String?,
        targetDeviceID: UUID?,
        targetName: String?,
        createdAt: Date,
        attempts: Int = 0,
        state: State = .queued
    ) {
        self.id = id
        self.kind = kind
        self.fileName = TransferFileName.sanitized(fileName, kind: kind)
        self.byteCount = byteCount
        self.contentType = contentType
        self.targetDeviceID = targetDeviceID
        self.targetName = targetName
        self.createdAt = createdAt
        self.attempts = attempts
        self.state = state
    }

    public var manifest: TransferManifest {
        TransferManifest(kind: kind, name: fileName, byteCount: byteCount, contentType: contentType)
    }

    /// Whether this item may go to `deviceID`.
    public func isFor(_ deviceID: UUID) -> Bool {
        targetDeviceID == nil || targetDeviceID == deviceID
    }
}

public struct TransferOutbox: Codable, Equatable, Sendable {
    /// Offers per item before it is given up as failed.
    public static let maxAttempts = 8
    /// Items older than this are dropped unsent.
    public static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    public private(set) var items: [TransferOutboxItem]

    public init(items: [TransferOutboxItem] = []) {
        self.items = items
    }

    /// Reads stored JSON; empty when missing or unreadable.
    public init(storage: Data?) {
        if let storage, let decoded = try? JSONDecoder().decode(TransferOutbox.self, from: storage) {
            self = decoded
        } else {
            self.init()
        }
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public var isFull: Bool { items.count >= TransferPolicy.maxOutboxItems }

    /// Adds an item. `false` when the outbox is full or the id is taken.
    @discardableResult
    public mutating func add(_ item: TransferOutboxItem) -> Bool {
        guard !isFull, !items.contains(where: { $0.id == item.id }) else { return false }
        items.append(item)
        return true
    }

    /// Items to offer now to the Mac `deviceID`, oldest first: everything
    /// for it (or for any Mac) that isn't already moving.
    public func ready(for deviceID: UUID) -> [TransferOutboxItem] {
        items.filter { $0.isFor(deviceID) && $0.state != .sending }
    }

    /// An item was offered on a connection.
    public mutating func markSending(_ id: UUID, to deviceID: UUID, name: String?) {
        update(id) {
            $0.state = .sending
            $0.attempts += 1
            // An item for "any Mac" belongs to the first one it goes to,
            // so a resume goes to the Mac that has the partial file.
            if $0.targetDeviceID == nil {
                $0.targetDeviceID = deviceID
                $0.targetName = name
            }
        }
    }

    /// The connection ended or the transfer broke off. Returns `true` when
    /// the item stays for another try, `false` when it was given up.
    @discardableResult
    public mutating func markInterrupted(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        if item.attempts >= Self.maxAttempts {
            remove(id)
            return false
        }
        update(id) { $0.state = .paused }
        return true
    }

    /// Every item moving on a connection that ended goes back to waiting.
    public mutating func connectionEnded() {
        for item in items where item.state == .sending {
            markInterrupted(item.id)
        }
    }

    /// Saved, refused or cancelled: the item is done.
    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Drops items older than `maxAge`. Returns the ids dropped, so their
    /// files can go too.
    public mutating func prune(now: Date) -> [UUID] {
        let old = items.filter { now.timeIntervalSince($0.createdAt) > Self.maxAge }.map(\.id)
        items.removeAll { old.contains($0.id) }
        return old
    }

    private mutating func update(_ id: UUID, _ body: (inout TransferOutboxItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
    }
}

/// S1: where a receiver resumes a transfer it saw before.
public enum TransferResume {
    /// The partial file's name for a transfer: its id, so a peer's name
    /// never reaches the path.
    public static func partialFileName(for transferID: UUID) -> String {
        transferID.uuidString.lowercased() + ".part"
    }

    /// The offset to accept from: the partial file's size when it is a
    /// prefix of the offer (no bigger than it), else 0 (start over).
    public static func offset(partialBytes: UInt64?, totalBytes: UInt64) -> UInt64 {
        guard let partialBytes, partialBytes > 0, partialBytes < totalBytes else { return 0 }
        return partialBytes
    }

    /// Partial files older than this are deleted.
    public static let maxPartialAge: TimeInterval = 3 * 24 * 60 * 60
}
