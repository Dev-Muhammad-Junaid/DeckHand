//
//  MirrorVideo.swift
//  PixelHandCore
//
//  The HEVC mirror's rules (S5), pure so they are tested on Linux:
//
//  - `MirrorHEVCParameterSets`: the `hevcParameterSets` frame payload.
//  - `MirrorHEVCNALUnits`: checks a `hevcKeyFrame` / `hevcDeltaFrame`
//    payload before the remote hands it to the decoder.
//  - `MirrorKeyFramePolicy` (Mac): when the encoder must make a key frame.
//  - `MirrorVideoBackpressure` (Mac, per remote): drop deltas while the
//    link is behind, then ask for a key frame.
//  - `MirrorVideoWatchdog` (remote): no picture while frames arrive →
//    ask for a key frame, then fall back to JPEG.
//  - `MirrorCodecChoice`, `MirrorVideoBitrate`: what to ask for and how
//    many bits to spend.
//
//  Wire layout of the video kinds on `PixelHandStream.mirror`:
//
//      hevcParameterSets   MirrorHEVCParameterSets.encoded(); sent right
//                          before every key frame (same Loom payload)
//      hevcKeyFrame        one IDR access unit, NAL units each prefixed
//                          with its length (big-endian, `nalUnitHeaderLength`
//                          bytes, as VideoToolbox writes them)
//      hevcDeltaFrame      same, for a frame that needs earlier ones
//
//  A delta always follows the key frame it depends on on the same stream,
//  with nothing dropped in between: the Mac drops deltas only until it
//  sends the next key frame (`MirrorVideoBackpressure`).
//

import Foundation

// MARK: - Payloads

/// HEVC parameter sets (VPS, SPS, PPS, in the encoder's order) and the
/// size of the length prefix in front of each NAL unit in frame payloads.
///
/// Layout, big-endian: `[u8 nalUnitHeaderLength][u8 count]` then `count`
/// times `[u16 length][bytes]`.
public struct MirrorHEVCParameterSets: Equatable, Sendable {
    public static let maxSets = 16
    public static let allowedHeaderLengths: Set<Int> = [1, 2, 4]

    public enum DecodeError: Error, Equatable, Sendable {
        case truncated
        case badHeaderLength(Int)
        case badCount(Int)
        case emptySet
    }

    public let nalUnitHeaderLength: Int
    public let sets: [Data]

    public init(nalUnitHeaderLength: Int, sets: [Data]) {
        self.nalUnitHeaderLength = nalUnitHeaderLength
        self.sets = sets
    }

    public func encoded() -> Data {
        var data = Data()
        data.append(UInt8(clamping: nalUnitHeaderLength))
        let kept = sets.prefix(Self.maxSets).filter { !$0.isEmpty && $0.count <= Int(UInt16.max) }
        data.append(UInt8(kept.count))
        for set in kept {
            let length = UInt16(set.count)
            data.append(UInt8(length >> 8))
            data.append(UInt8(length & 0xFF))
            data.append(set)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> MirrorHEVCParameterSets {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw DecodeError.truncated }
        let headerLength = Int(bytes[0])
        guard allowedHeaderLengths.contains(headerLength) else { throw DecodeError.badHeaderLength(headerLength) }
        let count = Int(bytes[1])
        // VPS + SPS + PPS at least.
        guard count >= 3, count <= maxSets else { throw DecodeError.badCount(count) }
        var sets: [Data] = []
        var offset = 2
        for _ in 0..<count {
            guard offset + 2 <= bytes.count else { throw DecodeError.truncated }
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard length > 0 else { throw DecodeError.emptySet }
            guard offset + length <= bytes.count else { throw DecodeError.truncated }
            sets.append(Data(bytes[offset..<(offset + length)]))
            offset += length
        }
        return MirrorHEVCParameterSets(nalUnitHeaderLength: headerLength, sets: sets)
    }
}

/// Length-prefixed NAL units, as in a key or delta frame payload.
public enum MirrorHEVCNALUnits {
    /// Whether `payload` is one or more whole NAL units, each prefixed with
    /// its length in `headerLength` bytes. A remote checks this before
    /// decoding, so a damaged frame is dropped (and a key frame asked for)
    /// instead of reaching the decoder.
    public static func isWellFormed(_ payload: Data, headerLength: Int) -> Bool {
        guard MirrorHEVCParameterSets.allowedHeaderLengths.contains(headerLength), !payload.isEmpty else { return false }
        return payload.withUnsafeBytes { raw -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            var offset = 0
            while offset < bytes.count {
                guard offset + headerLength <= bytes.count else { return false }
                var length = 0
                for i in 0..<headerLength {
                    length = length << 8 | Int(bytes[offset + i])
                }
                offset += headerLength
                guard length > 0, offset + length <= bytes.count else { return false }
                offset += length
            }
            return true
        }
    }

    /// Prefixes each NAL unit with its length (test and tooling helper).
    public static func join(_ units: [Data], headerLength: Int) -> Data {
        var data = Data()
        for unit in units {
            var length = unit.count
            var prefix = [UInt8](repeating: 0, count: headerLength)
            for i in stride(from: headerLength - 1, through: 0, by: -1) {
                prefix[i] = UInt8(length & 0xFF)
                length >>= 8
            }
            data.append(contentsOf: prefix)
            data.append(unit)
        }
        return data
    }
}

// MARK: - Mac: key frames

/// When the Mac's HEVC encoder must make a key frame.
///
/// The encoder makes one on its own at least every `interval` seconds. On
/// top of that a key frame is forced for the first frame, and when a
/// remote needs one (it joined, it fell behind, or it asked with
/// `mirror.requestKeyFrame`). Forced key frames are at least
/// `minForcedSpacing` apart, so a remote asking in a loop can't turn the
/// stream into key frames only; a request inside that window waits for it.
public struct MirrorKeyFramePolicy: Sendable, Equatable {
    /// `kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration`.
    public static let interval: Double = 2
    public static let minForcedSpacing: Double = 0.5

    public private(set) var pending = false
    private var lastKeyFrameAt: Double?

    public init() {}

    /// A remote needs a key frame.
    public mutating func request() {
        pending = true
    }

    /// Asked for each captured frame before it is encoded.
    public mutating func shouldForceKeyFrame(now: Double) -> Bool {
        guard let lastKeyFrameAt else {
            pending = false
            return true
        }
        guard pending, now - lastKeyFrameAt >= Self.minForcedSpacing else { return false }
        pending = false
        return true
    }

    /// The encoder produced a key frame (forced or its own). It serves every
    /// request made before it.
    public mutating func noteKeyFrame(at now: Double) {
        lastKeyFrameAt = now
        pending = false
    }

    /// A new encoder: its first frame is a key frame.
    public mutating func reset() {
        lastKeyFrameAt = nil
        pending = false
    }
}

// MARK: - Mac: per-remote backpressure

/// Video sends to one remote. Deltas are dropped while more than
/// `maxUnacked` sends are still on the wire; once one is dropped, the
/// following deltas are useless to the decoder, so everything waits for
/// the next key frame, which is asked for as soon as the link has room.
public struct MirrorVideoBackpressure: Sendable, Equatable {
    /// Deltas are dropped while more than this many sends are un-acked.
    public static let maxUnacked = 2
    /// A key frame is dropped too while this many are un-acked (the link is
    /// far behind; another key frame is asked for once it drains).
    public static let maxUnackedForKeyFrame = 4

    public enum Decision: Equatable, Sendable {
        case send
        /// Don't send. `requestKeyFrame`: ask the encoder for a key frame
        /// now (the link has room again).
        case drop(requestKeyFrame: Bool)
    }

    public private(set) var unacked = 0
    /// A remote starts at a key frame, and returns to one after a drop.
    public private(set) var needsKeyFrame = true

    public init() {}

    public mutating func decide(isKeyFrame: Bool) -> Decision {
        if isKeyFrame {
            guard unacked < Self.maxUnackedForKeyFrame else {
                needsKeyFrame = true
                return .drop(requestKeyFrame: false)
            }
            needsKeyFrame = false
            unacked += 1
            return .send
        }
        if needsKeyFrame {
            return .drop(requestKeyFrame: unacked <= Self.maxUnacked)
        }
        if unacked > Self.maxUnacked {
            needsKeyFrame = true
            return .drop(requestKeyFrame: false)
        }
        unacked += 1
        return .send
    }

    /// One send finished (sent or failed). Returns `true` when this is the
    /// moment to ask for the key frame a drop left waiting.
    public mutating func noteAcked() -> Bool {
        let wasBehind = unacked > Self.maxUnacked
        unacked = max(0, unacked - 1)
        return needsKeyFrame && wasBehind && unacked <= Self.maxUnacked
    }

    /// A new stream to this remote.
    public mutating func reset() {
        unacked = 0
        needsKeyFrame = true
    }
}

// MARK: - Remote: watchdog

/// The remote's view of an HEVC mirror: decode only what can decode, ask
/// for a key frame when the picture is broken, and give up on HEVC (ask the
/// Mac for JPEG) when key frames don't bring it back.
///
/// "Stalled" means frames keep arriving but none has been shown for
/// `stallTimeout`. An idle Mac screen sends no frames, which is not a
/// stall.
public struct MirrorVideoWatchdog: Sendable, Equatable {
    public static let stallTimeout: Double = 2
    /// Key frame requests without a picture before falling back to JPEG.
    public static let maxKeyFrameRequests = 2
    /// Requests for a decode problem are at least this far apart.
    public static let requestSpacing: Double = 0.5

    public enum FrameKind: Sendable, Equatable {
        case parameterSets, keyFrame, deltaFrame
    }

    public enum Phase: Sendable, Equatable {
        /// Nothing decodable yet: deltas are dropped.
        case waitingForKeyFrame
        case playing
        /// The picture broke: deltas are dropped until a key frame.
        case recovering
        /// HEVC gave up; the remote asks for JPEG.
        case fellBack
    }

    public enum Action: Sendable, Equatable {
        case none
        case requestKeyFrame
        case fallBackToJPEG
    }

    public private(set) var phase: Phase = .waitingForKeyFrame
    public private(set) var keyFrameRequests = 0
    private var startedAt: Double
    private var lastDisplayAt: Double?
    private var lastArrivalAt: Double?
    private var lastRequestAt: Double?

    public init(now: Double) {
        startedAt = now
    }

    /// A new stream or a new picture size: start over (not after a
    /// fallback, which lasts for the session).
    public mutating func reset(now: Double) {
        guard phase != .fellBack else { return }
        self = MirrorVideoWatchdog(now: now)
    }

    /// A video frame arrived. `decode`: hand it to the decoder.
    public mutating func frameArrived(_ kind: FrameKind, afterDrop: Bool = false, now: Double) -> (decode: Bool, action: Action) {
        guard phase != .fellBack else { return (false, .none) }
        lastArrivalAt = now
        switch kind {
        case .parameterSets:
            return (true, .none)
        case .keyFrame:
            phase = .playing
            return (true, .none)
        case .deltaFrame:
            if afterDrop, phase == .playing {
                // The Mac dropped what this delta depends on.
                phase = .recovering
            }
            guard phase == .playing else { return (false, requestIfDue(now: now)) }
            return (true, .none)
        }
    }

    /// The decoder showed a frame.
    public mutating func frameDisplayed(now: Double) {
        guard phase != .fellBack else { return }
        lastDisplayAt = now
        keyFrameRequests = 0
        if phase == .recovering { return } // wait for the key frame
        phase = .playing
    }

    /// The decoder or the display layer failed on a frame.
    public mutating func decodeFailed(now: Double) -> Action {
        guard phase != .fellBack else { return .none }
        phase = .recovering
        return requestIfDue(now: now)
    }

    /// HEVC can't work here (no decoder, layer failed for good).
    public mutating func fallBack() -> Action {
        guard phase != .fellBack else { return .none }
        phase = .fellBack
        return .fallBackToJPEG
    }

    /// Called a few times a second.
    public mutating func tick(now: Double) -> Action {
        guard phase != .fellBack,
              let lastArrivalAt, now - lastArrivalAt < Self.stallTimeout else { return .none }
        let shownAt = lastDisplayAt ?? startedAt
        guard now - shownAt >= Self.stallTimeout else { return .none }
        // Stalled. Wait a full timeout after each request before the next
        // step.
        if let lastRequestAt, now - lastRequestAt < Self.stallTimeout { return .none }
        if keyFrameRequests >= Self.maxKeyFrameRequests {
            phase = .fellBack
            return .fallBackToJPEG
        }
        phase = phase == .playing ? .recovering : phase
        keyFrameRequests += 1
        lastRequestAt = now
        return .requestKeyFrame
    }

    private mutating func requestIfDue(now: Double) -> Action {
        if let lastRequestAt, now - lastRequestAt < Self.requestSpacing { return .none }
        guard keyFrameRequests < Self.maxKeyFrameRequests else { return .none } // tick() decides the fallback
        keyFrameRequests += 1
        lastRequestAt = now
        return .requestKeyFrame
    }
}

// MARK: - Choice and bitrate

public enum MirrorCodecChoice {
    /// The codec a remote asks for in `mirror.start`.
    public static func requested(prefersHEVC: Bool, hevcDecodeAvailable: Bool, fellBack: Bool) -> MirrorCodec {
        prefersHEVC && hevcDecodeAvailable && !fellBack ? .hevc : .jpeg
    }
}

public enum MirrorVideoBitrate {
    public static let bitsPerPixelPerFrame = 0.12
    public static let range: ClosedRange<Double> = 1_000_000...12_000_000

    /// `kVTCompressionPropertyKey_AverageBitRate` for a stream of this size
    /// and rate. Screen content is mostly still, so this mostly bounds
    /// bursts (scrolling, video playback).
    public static func averageBitsPerSecond(width: Int, height: Int, fps: Int) -> Int {
        let raw = Double(max(width, 0)) * Double(max(height, 0)) * Double(max(fps, 1)) * bitsPerPixelPerFrame
        return Int(min(max(raw, range.lowerBound), range.upperBound))
    }

    /// HEVC wants even dimensions.
    public static func evenDimension(_ value: Int) -> Int {
        max(2, value & ~1)
    }
}
