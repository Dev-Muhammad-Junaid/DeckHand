//
//  TransferManifest.swift
//  PixelHandCore
//
//  S1: what one transfer carries, as both apps describe it. Bytes travel
//  through Loom's transfer engine (`LoomTransferEngine`, one per
//  connection), which has its own control stream and one data stream per
//  transfer, chunks, windows, resumes from a contiguous offset and checks
//  a SHA-256. Nothing bulk ever goes in the JSON control stream.
//
//  The engine's offer has a logical name, a byte length, a content type
//  and a string metadata dictionary. This file maps a Pixel Hand item onto
//  those fields and, on the receiving side, reads them back with every
//  string and number checked, because they come from the network:
//
//      logicalName   the file name (`TransferFileName.sanitized`)
//      byteLength    the item's size, ≤ `TransferPolicy.maxFileBytes`
//                    (≤ `maxInlineBytes` for a link or text)
//      contentType   a UTI, ≤ 128 printable ASCII characters, else dropped
//      metadata      "ph.kind" = file / photo / link / text,
//                    "ph.m" = manifest version (1)
//
//  A link or text is sent as its UTF-8 bytes, like a tiny file, so every
//  item takes the same path (progress, cancel, resume, receipts).
//

import Foundation

/// What kind of item a transfer carries. Decides where it lands.
public enum TransferKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Any file. Mac: `~/Downloads/Pixel Hand`, revealed in Finder.
    /// Device: the Inbox (Files can see it).
    case file
    /// A photo or video from the library. Mac: as a file. Device: the
    /// Inbox, with Save to Photos.
    case photo
    /// One http(s) URL as UTF-8 text. Mac: opens in the default browser.
    /// Device: the Inbox, tap to open.
    case link
    /// Plain UTF-8 text. Mac: a `.txt` in Downloads and on the clipboard.
    /// Device: the Inbox, with Copy.
    case text

    /// Carried as UTF-8 text rather than file bytes.
    public var isInline: Bool { self == .link || self == .text }
}

public struct TransferManifest: Equatable, Sendable, Hashable {
    /// Metadata keys in the Loom offer.
    public enum Key {
        public static let kind = "ph.kind"
        public static let version = "ph.m"
    }

    public static let version = "1"
    /// Longest content type accepted.
    public static let maxContentTypeLength = 128

    public var kind: TransferKind
    /// Clean file name, never empty.
    public var name: String
    public var byteCount: UInt64
    /// A UTI such as `public.jpeg`, or `nil`.
    public var contentType: String?

    public init(kind: TransferKind, name: String, byteCount: UInt64, contentType: String?) {
        self.kind = kind
        self.name = TransferFileName.sanitized(name, kind: kind)
        self.byteCount = byteCount
        self.contentType = Self.cleanContentType(contentType)
    }

    /// The offer's metadata dictionary.
    public var metadata: [String: String] {
        [Key.kind: kind.rawValue, Key.version: Self.version]
    }

    /// Why an offer from the network can't be taken.
    public enum ReadError: Error, Equatable, Sendable {
        /// Not a Pixel Hand item, or a manifest version this build can't read.
        case unsupported
        /// Over the size cap for its kind.
        case tooLarge
    }

    /// Reads a Loom offer's fields back into a manifest, cleaning the name
    /// and content type. Fails for a missing or unknown kind, another
    /// manifest version, or a size over the cap.
    public static func read(
        logicalName: String,
        byteLength: UInt64,
        contentType: String?,
        metadata: [String: String]
    ) -> Result<TransferManifest, ReadError> {
        guard metadata[Key.version] == version,
              let raw = metadata[Key.kind],
              let kind = TransferKind(rawValue: raw) else {
            return .failure(.unsupported)
        }
        guard byteLength <= TransferPolicy.maxBytes(for: kind) else {
            return .failure(.tooLarge)
        }
        if kind.isInline, byteLength == 0 { return .failure(.unsupported) }
        return .success(TransferManifest(kind: kind, name: logicalName, byteCount: byteLength, contentType: contentType))
    }

    /// A UTI-shaped string or `nil`: printable ASCII without spaces, at
    /// most `maxContentTypeLength` characters.
    static func cleanContentType(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= maxContentTypeLength else { return nil }
        let allowed = raw.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && scalar.value > 0x20 && scalar.value < 0x7F
        }
        return allowed ? raw : nil
    }
}
