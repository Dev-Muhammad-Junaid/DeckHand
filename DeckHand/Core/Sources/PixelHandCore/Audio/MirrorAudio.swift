//
//  MirrorAudio.swift
//  PixelHandCore
//
//  S17, the Mac's sound on the remote while mirroring. Off by default; the
//  remote turns it on with `mirror.audio(enabled: true)` and the Mac opens
//  `PixelHandStream.audio` towards it. The Mac captures system audio
//  (ScreenCaptureKit, without Pixel Hand's own sound), encodes it in
//  packets of about 20 ms and sends each in a `BinaryFrameHeader` frame.
//  The remote decodes them into a small, adaptive jitter buffer
//  (`MirrorAudioJitterBuffer`) and plays from it.
//
//  Two payloads, both big-endian (see `BinaryFrame.swift` for the header):
//
//  `audioFormat` (`MirrorAudioFormat`, 12 bytes + magic cookie)
//
//      offset size field
//      0      1    codec (`MirrorAudioCodec`)
//      1      1    channels (1 or 2)
//      2      2    frames per packet
//      4      4    sample rate, Hz
//      8      2    reserved, 0
//      10     2    magic cookie length n
//      12     n    the encoder's magic cookie (AAC: AudioSpecificConfig),
//                  may be empty
//
//  `audioPacket` (`MirrorAudioPacket`, 14 bytes + data)
//
//      offset size field
//      0      4    sequence: +1 per packet on a stream; a gap is a packet
//                  the Mac dropped
//      4      8    sample time: frames since the stream's first packet
//      12     2    frames in this packet
//      14     n    one AAC access unit, or interleaved Int16 PCM
//
//  A new `audioFormat` starts a new run: the remote resets its decoder,
//  sequence tracking and buffer.
//

import Foundation

/// How audio packets are encoded.
public enum MirrorAudioCodec: UInt8, Codable, Sendable, CaseIterable {
    /// AAC-LC, 1024 frames a packet (21.3 ms at 48 kHz). The default.
    case aacLC = 1
    /// Interleaved signed 16-bit PCM, 960 frames a packet (20 ms at
    /// 48 kHz). The Mac falls back to it when it can't make an AAC
    /// encoder; about 1.5 Mb/s for stereo.
    case pcm16 = 2

    /// Frames in one packet of this codec.
    public var framesPerPacket: Int {
        switch self {
        case .aacLC: return 1024
        case .pcm16: return 960
        }
    }

    /// Short name for the stats line.
    public var label: String {
        switch self {
        case .aacLC: return "AAC"
        case .pcm16: return "PCM"
        }
    }
}

/// The stream's audio format, sent before its first packet.
public struct MirrorAudioFormat: Equatable, Sendable {
    public static let headerByteCount = 12
    /// Largest magic cookie accepted (an AAC one is a few bytes).
    public static let maxCookieLength = 1024
    /// The capture rate the Mac asks ScreenCaptureKit for.
    public static let preferredSampleRate = 48_000
    public static let sampleRateRange: ClosedRange<Int> = 8_000...96_000

    public enum DecodeError: Error, Equatable, Sendable {
        case truncated
        case unknownCodec(UInt8)
        case badChannels(Int)
        case badSampleRate(Int)
        case badFramesPerPacket(Int)
        case cookieTooLong(Int)
    }

    public var codec: MirrorAudioCodec
    public var channels: Int
    public var framesPerPacket: Int
    public var sampleRate: Int
    public var magicCookie: Data

    public init(codec: MirrorAudioCodec, channels: Int, framesPerPacket: Int? = nil, sampleRate: Int, magicCookie: Data = Data()) {
        self.codec = codec
        self.channels = channels
        self.framesPerPacket = framesPerPacket ?? codec.framesPerPacket
        self.sampleRate = sampleRate
        self.magicCookie = magicCookie
    }

    /// One packet's length in seconds.
    public var packetDuration: Double {
        Double(framesPerPacket) / Double(max(sampleRate, 1))
    }

    public func encoded() -> Data {
        var data = Data(capacity: Self.headerByteCount + magicCookie.count)
        data.append(codec.rawValue)
        data.append(UInt8(clamping: channels))
        MirrorBytes.append(UInt16(clamping: framesPerPacket), to: &data)
        MirrorBytes.append(UInt32(clamping: sampleRate), to: &data)
        MirrorBytes.append(UInt16(0), to: &data)
        let cookie = magicCookie.prefix(Self.maxCookieLength)
        MirrorBytes.append(UInt16(cookie.count), to: &data)
        data.append(cookie)
        return data
    }

    /// Reads a format and checks it is one the remote can play.
    public static func decode(_ data: Data) throws -> MirrorAudioFormat {
        let bytes = [UInt8](data)
        guard bytes.count >= headerByteCount else { throw DecodeError.truncated }
        guard let codec = MirrorAudioCodec(rawValue: bytes[0]) else { throw DecodeError.unknownCodec(bytes[0]) }
        let channels = Int(bytes[1])
        guard (1...2).contains(channels) else { throw DecodeError.badChannels(channels) }
        let frames = Int(MirrorBytes.read(bytes, at: 2, count: 2))
        guard (64...4_096).contains(frames) else { throw DecodeError.badFramesPerPacket(frames) }
        let rate = Int(MirrorBytes.read(bytes, at: 4, count: 4))
        guard sampleRateRange.contains(rate) else { throw DecodeError.badSampleRate(rate) }
        let cookieLength = Int(MirrorBytes.read(bytes, at: 10, count: 2))
        guard cookieLength <= maxCookieLength else { throw DecodeError.cookieTooLong(cookieLength) }
        guard bytes.count >= headerByteCount + cookieLength else { throw DecodeError.truncated }
        let cookie = Data(bytes[headerByteCount..<(headerByteCount + cookieLength)])
        return MirrorAudioFormat(codec: codec, channels: channels, framesPerPacket: frames, sampleRate: rate, magicCookie: cookie)
    }
}

/// One encoded packet of audio.
public struct MirrorAudioPacket: Equatable, Sendable {
    public static let headerByteCount = 14
    /// Largest packet accepted: 4096 stereo PCM16 frames.
    public static let maxDataLength = 4_096 * 2 * 2

    public enum DecodeError: Error, Equatable, Sendable {
        case truncated
        case empty
        case tooLarge(Int)
    }

    public var sequence: UInt32
    public var sampleTime: UInt64
    public var frameCount: Int
    public var data: Data

    public init(sequence: UInt32, sampleTime: UInt64, frameCount: Int, data: Data) {
        self.sequence = sequence
        self.sampleTime = sampleTime
        self.frameCount = frameCount
        self.data = data
    }

    public func encoded() -> Data {
        var bytes = Data(capacity: Self.headerByteCount + data.count)
        MirrorBytes.append(sequence, to: &bytes)
        MirrorBytes.append(sampleTime, to: &bytes)
        MirrorBytes.append(UInt16(clamping: frameCount), to: &bytes)
        bytes.append(data)
        return bytes
    }

    public static func decode(_ payload: Data) throws -> MirrorAudioPacket {
        guard payload.count >= headerByteCount else { throw DecodeError.truncated }
        let head = [UInt8](payload.prefix(headerByteCount))
        let dataLength = payload.count - headerByteCount
        guard dataLength > 0 else { throw DecodeError.empty }
        guard dataLength <= maxDataLength else { throw DecodeError.tooLarge(dataLength) }
        let start = payload.startIndex + headerByteCount
        return MirrorAudioPacket(
            sequence: UInt32(MirrorBytes.read(head, at: 0, count: 4)),
            sampleTime: MirrorBytes.read(head, at: 4, count: 8),
            frameCount: Int(MirrorBytes.read(head, at: 12, count: 2)),
            data: Data(payload[start...])
        )
    }
}

/// Interleaved Int16 PCM, the `pcm16` codec's packet data. Big-endian like
/// every other field on the wire.
public enum MirrorAudioPCM16 {
    /// Interleaved Float32 samples (−1…1, clipped) → packet data.
    public static func encode(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = sample.isFinite ? max(-1, min(1, sample)) : 0
            MirrorBytes.append(Int16((value * 32_767).rounded()), to: &data)
        }
        return data
    }

    /// Packet data → interleaved Float32 samples. An odd trailing byte is
    /// ignored.
    public static func decode(_ data: Data) -> [Float] {
        let bytes = [UInt8](data)
        var samples = [Float]()
        samples.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            let raw = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            samples.append(Float(Int16(bitPattern: raw)) / 32_767)
            index += 2
        }
        return samples
    }
}
