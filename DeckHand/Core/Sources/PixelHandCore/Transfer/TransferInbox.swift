//
//  TransferInbox.swift
//  PixelHandCore
//
//  S2: the device's Inbox of received items, newest first. The app keeps
//  the files in its Documents folder ("Pixel Hand Inbox", visible in
//  Files) and this list as JSON beside them. Links and text keep their
//  text here as well, so the row can open or copy it without a file read.
//

import Foundation

public struct TransferInboxItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var kind: TransferKind
    /// The file's name in the Inbox folder.
    public var fileName: String
    public var byteCount: UInt64
    public var contentType: String?
    /// Who sent it ("Studio").
    public var senderName: String
    public var receivedAt: Date
    /// A link's or text's content, ≤ `TransferPolicy.maxInlineBytes`.
    public var text: String?
    /// Opened, saved or shared at least once (the row loses its dot).
    public var isSeen: Bool

    public init(
        id: UUID,
        kind: TransferKind,
        fileName: String,
        byteCount: UInt64,
        contentType: String?,
        senderName: String,
        receivedAt: Date,
        text: String? = nil,
        isSeen: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.byteCount = byteCount
        self.contentType = contentType
        self.senderName = senderName
        self.receivedAt = receivedAt
        self.text = text
        self.isSeen = isSeen
    }

    /// The row's title: the host for a link, the first line of text, else
    /// the file name.
    public var title: String {
        if let text, kind.isInline { return TransferInlineText.title(for: text) }
        return fileName
    }

    /// The link to open, for a link item.
    public var link: URL? {
        guard kind == .link, let text else { return nil }
        return TransferInlineText.webLink(text)
    }

    /// Whether Save to Photos applies (an image or a movie).
    public var isPhotoLibraryCompatible: Bool {
        if kind == .photo { return true }
        guard let type = contentType?.lowercased() else {
            let ext = TransferFileName.split(fileName).ext.lowercased()
            return ["jpg", "jpeg", "png", "heic", "heif", "gif", "mov", "mp4", "m4v"].contains(ext)
        }
        return type.hasPrefix("public.") && (
            ["public.jpeg", "public.png", "public.heic", "public.heif", "public.image", "public.movie", "public.mpeg-4", "com.apple.quicktime-movie", "com.compuserve.gif"].contains(type)
        )
    }
}

public struct TransferInbox: Codable, Equatable, Sendable {
    /// Items kept; older ones (and their files) are removed.
    public static let maxItems = 200

    public private(set) var items: [TransferInboxItem]

    public init(items: [TransferInboxItem] = []) {
        self.items = items.sorted { $0.receivedAt > $1.receivedAt }
    }

    public init(storage: Data?) {
        if let storage, let decoded = try? JSONDecoder().decode(TransferInbox.self, from: storage) {
            self.init(items: decoded.items)
        } else {
            self.init()
        }
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public var unseenCount: Int { items.filter { !$0.isSeen }.count }

    /// Adds an item at the top. Returns items pushed out by the cap, whose
    /// files should be deleted.
    @discardableResult
    public mutating func add(_ item: TransferInboxItem) -> [TransferInboxItem] {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        items.sort { $0.receivedAt > $1.receivedAt }
        guard items.count > Self.maxItems else { return [] }
        let dropped = Array(items[Self.maxItems...])
        items.removeLast(items.count - Self.maxItems)
        return dropped
    }

    public mutating func markSeen(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSeen = true
    }

    public mutating func markAllSeen() {
        for index in items.indices { items[index].isSeen = true }
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> TransferInboxItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// File names in use, for `TransferFileName.unique`.
    public var fileNames: Set<String> { Set(items.map(\.fileName)) }
}
