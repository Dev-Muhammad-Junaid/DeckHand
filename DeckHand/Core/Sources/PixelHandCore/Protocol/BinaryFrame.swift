//
//  BinaryFrame.swift
//  PixelHandCore
//
//  Framing for bulk binary data on its own Loom stream, kept apart from the
//  JSON control stream so a large frame never queues ahead of input or a
//  heartbeat. The mirror stream carries JPEG frames today (HEVC with S5),
//  plus the Mac's cursor position and shape, which the remote draws over
//  the video itself (S3).
//
//  Layout, big-endian, 28 bytes, then `payloadLength` bytes of payload:
//
//      offset size field
//      0      4    magic "PHBF"
//      4      1    format version (1)
//      5      1    kind (BinaryFrameHeader.Kind)
//      6      2    flags (BinaryFrameHeader.Flags)
//      8      8    seq: increases by one per frame within a stream
//      16     8    presentation time, microseconds on the sender's clock
//      24     4    payload length
//
//  Negotiation stays on the control stream: the remote sends
//  `mirror.start`, the host opens `PixelHandStream.mirror` towards it
//  (once per connection, reused across restarts) and announces
//  `ProtocolFeature.binaryMirrorStream` in `HostStatus`. One Loom payload
//  carries one whole frame; `BinaryFrameReader` also copes with payloads
//  that were split or joined on the way.
//
//  Payload by kind:
//
//      jpeg            a JPEG image of the captured display
//      hevc*           reserved for S5
//      cursor          `MirrorCursorState.encoded()` (18 bytes)
//      cursorShape     `MirrorCursorShape.encoded()` (20 bytes + PNG)
//

import Foundation

/// Names of the Loom streams the apps open. The control stream is LoomKit's
/// default message stream.
public enum PixelHandStream {
    /// Mirror video and cursor, framed with `BinaryFrameHeader`. Opened by
    /// the Mac towards a remote that sent `mirror.start`.
    public static let mirror = "pixelhand.mirror"
}

public struct BinaryFrameHeader: Equatable, Sendable {
    public static let magic: [UInt8] = Array("PHBF".utf8)
    public static let formatVersion: UInt8 = 1
    public static let byteCount = 28
    /// Largest payload a receiver accepts in one frame (16 MB).
    public static let maxPayloadLength: UInt32 = 16 * 1024 * 1024

    public enum Kind: UInt8, Sendable, CaseIterable {
        /// A self-contained JPEG image.
        case jpeg = 1
        /// HEVC parameter sets (VPS/SPS/PPS), sent before a key frame.
        case hevcParameterSets = 2
        /// An HEVC key frame (IDR).
        case hevcKeyFrame = 3
        /// An HEVC frame that depends on earlier ones.
        case hevcDeltaFrame = 4
        /// Where the Mac's pointer is, and which shape it has (S3). Small
        /// and frequent; never dropped in favour of a video frame.
        case cursor = 5
        /// A pointer image the remote caches by id (S3). Sent the first
        /// time a shape appears on a stream.
        case cursorShape = 6
    }

    public struct Flags: OptionSet, Sendable, Equatable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        /// The sender dropped frames just before this one (backpressure).
        public static let afterDrop = Flags(rawValue: 1 << 0)
        /// The display or its size changed with this frame.
        public static let formatChanged = Flags(rawValue: 1 << 1)
    }

    public enum DecodeError: Error, Equatable, Sendable {
        case truncated(needed: Int, available: Int)
        case badMagic
        case unsupportedVersion(UInt8)
        case unknownKind(UInt8)
        case payloadTooLarge(UInt32)
    }

    public var kind: Kind
    public var flags: Flags
    public var seq: UInt64
    public var presentationTimeMicros: UInt64
    public var payloadLength: UInt32

    public init(kind: Kind, flags: Flags = [], seq: UInt64, presentationTimeMicros: UInt64, payloadLength: UInt32) {
        self.kind = kind
        self.flags = flags
        self.seq = seq
        self.presentationTimeMicros = presentationTimeMicros
        self.payloadLength = payloadLength
    }

    /// The header's 28 bytes.
    public func encoded() -> Data {
        var data = Data(capacity: Self.byteCount)
        data.append(contentsOf: Self.magic)
        data.append(Self.formatVersion)
        data.append(kind.rawValue)
        Self.append(flags.rawValue, to: &data)
        Self.append(seq, to: &data)
        Self.append(presentationTimeMicros, to: &data)
        Self.append(payloadLength, to: &data)
        return data
    }

    /// A whole frame: header followed by `payload`.
    public static func frame(
        kind: Kind,
        flags: Flags = [],
        seq: UInt64,
        presentationTimeMicros: UInt64,
        payload: Data
    ) -> Data {
        let header = BinaryFrameHeader(
            kind: kind,
            flags: flags,
            seq: seq,
            presentationTimeMicros: presentationTimeMicros,
            payloadLength: UInt32(clamping: payload.count)
        )
        return header.encoded() + payload
    }

    /// Reads a header from the start of `data`.
    public static func decode(_ data: Data) throws -> BinaryFrameHeader {
        let bytes = [UInt8](data.prefix(byteCount))
        guard bytes.count == byteCount else {
            throw DecodeError.truncated(needed: byteCount, available: bytes.count)
        }
        guard Array(bytes[0..<4]) == magic else { throw DecodeError.badMagic }
        guard bytes[4] == formatVersion else { throw DecodeError.unsupportedVersion(bytes[4]) }
        guard let kind = Kind(rawValue: bytes[5]) else { throw DecodeError.unknownKind(bytes[5]) }
        let length = UInt32(read(bytes, at: 24, count: 4))
        guard length <= maxPayloadLength else { throw DecodeError.payloadTooLarge(length) }
        return BinaryFrameHeader(
            kind: kind,
            flags: Flags(rawValue: UInt16(read(bytes, at: 6, count: 2))),
            seq: read(bytes, at: 8, count: 8),
            presentationTimeMicros: read(bytes, at: 16, count: 8),
            payloadLength: length
        )
    }

    /// Splits a whole frame into its header and payload. Fails if the
    /// payload is shorter than the header says.
    public static func decodeFrame(_ data: Data) throws -> (header: BinaryFrameHeader, payload: Data) {
        let header = try decode(data)
        let needed = byteCount + Int(header.payloadLength)
        guard data.count >= needed else {
            throw DecodeError.truncated(needed: needed, available: data.count)
        }
        let start = data.startIndex + byteCount
        return (header, Data(data[start..<(start + Int(header.payloadLength))]))
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private static func read(_ bytes: [UInt8], at offset: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in bytes[offset..<(offset + count)] {
            value = value << 8 | UInt64(byte)
        }
        return value
    }
}

/// Turns the bytes of a binary stream back into whole frames.
///
/// Loom keeps payload boundaries, so normally every `append` holds exactly
/// one frame. The reader doesn't rely on that: it buffers a partial frame
/// until the rest arrives and returns every complete frame in order. After
/// a framing error (bad magic, oversize length) the stream can't be
/// resynchronised, so the reader stays failed and the caller drops the
/// stream.
public struct BinaryFrameReader: Sendable {
    public struct Frame: Equatable, Sendable {
        public let header: BinaryFrameHeader
        public let payload: Data
    }

    /// Most bytes held waiting for the rest of a frame: one maximum
    /// payload plus its header.
    public static let maxBufferedBytes = BinaryFrameHeader.byteCount + Int(BinaryFrameHeader.maxPayloadLength)

    private var buffer = Data()
    public private(set) var failure: BinaryFrameHeader.DecodeError?

    public init() {}

    /// Bytes received but not yet part of a returned frame.
    public var bufferedByteCount: Int { buffer.count }

    /// Adds `bytes` and returns every frame completed by them, oldest first.
    public mutating func append(_ bytes: Data) throws -> [Frame] {
        if let failure { throw failure }
        buffer.append(bytes)
        var frames: [Frame] = []
        while buffer.count >= BinaryFrameHeader.byteCount {
            let header: BinaryFrameHeader
            do {
                header = try BinaryFrameHeader.decode(buffer)
            } catch let error as BinaryFrameHeader.DecodeError {
                failure = error
                buffer = Data()
                throw error
            }
            let total = BinaryFrameHeader.byteCount + Int(header.payloadLength)
            guard buffer.count >= total else { break }
            let start = buffer.startIndex + BinaryFrameHeader.byteCount
            let end = buffer.startIndex + total
            frames.append(Frame(header: header, payload: Data(buffer[start..<end])))
            buffer = Data(buffer[end...])
        }
        return frames
    }
}
