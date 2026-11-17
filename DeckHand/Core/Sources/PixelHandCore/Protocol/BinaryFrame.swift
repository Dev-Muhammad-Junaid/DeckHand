//
//  BinaryFrame.swift
//  PixelHandCore
//
//  Framing for bulk binary data on its own Loom stream, kept apart from the
//  JSON control stream so a large frame never queues ahead of input or a
//  heartbeat. Designed for the binary mirror stream (S5: HEVC); nothing uses
//  it yet, and the mirror still sends JPEG `MirrorMessage.frame`s.
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
//  Negotiation stays on the control stream: the host announces
//  `ProtocolFeature.binaryMirrorStream` in `HostStatus`, and the mirror lane
//  adds the start/keyframe-request messages to `MirrorMessage`.
//

import Foundation

/// Names of the Loom streams the apps open. The control stream is LoomKit's
/// default message stream.
public enum PixelHandStream {
    /// Mirror video, framed with `BinaryFrameHeader`.
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
