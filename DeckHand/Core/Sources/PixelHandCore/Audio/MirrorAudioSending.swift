//
//  MirrorAudioSending.swift
//  PixelHandCore
//
//  S17, the Mac's side: cutting captured audio into packets, and the drop
//  policy per remote.
//

import Foundation

/// Cuts captured audio (interleaved Float32, any chunk size) into packets
/// of exactly `framesPerPacket` frames, each with its sample time.
public struct MirrorAudioChunker: Sendable {
    public struct Chunk: Equatable, Sendable {
        /// Interleaved, `framesPerPacket × channels` samples.
        public let samples: [Float]
        /// Frames since the first chunk.
        public let sampleTime: UInt64
    }

    public let channels: Int
    public let framesPerPacket: Int
    /// Most frames held waiting for a full packet; older ones are dropped
    /// (the encoder fell behind by more than this).
    public let maxPendingFrames: Int

    private var pending: [Float] = []
    public private(set) var nextSampleTime: UInt64 = 0

    public init(channels: Int, framesPerPacket: Int, maxPendingFrames: Int = 48_000) {
        self.channels = max(1, channels)
        self.framesPerPacket = max(1, framesPerPacket)
        self.maxPendingFrames = max(framesPerPacket, maxPendingFrames)
    }

    /// Frames waiting for the next packet.
    public var pendingFrames: Int { pending.count / channels }

    /// Adds samples (a trailing partial frame is ignored) and returns every
    /// packet they complete, oldest first.
    public mutating func append(_ samples: [Float]) -> [Chunk] {
        let whole = samples.count - samples.count % channels
        pending.append(contentsOf: samples[0..<whole])
        let overflow = pendingFrames - maxPendingFrames
        if overflow > 0 {
            pending.removeFirst(overflow * channels)
            nextSampleTime &+= UInt64(overflow)
        }
        var chunks: [Chunk] = []
        let packetSamples = framesPerPacket * channels
        var start = 0
        while pending.count - start >= packetSamples {
            chunks.append(Chunk(samples: Array(pending[start..<(start + packetSamples)]), sampleTime: nextSampleTime))
            nextSampleTime &+= UInt64(framesPerPacket)
            start += packetSamples
        }
        if start > 0 { pending.removeFirst(start) }
        return chunks
    }

    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        nextSampleTime = 0
    }
}

/// One remote's outgoing audio. One send is on the wire at a time; packets
/// that arrive meanwhile wait, and the waiting ones are sent together when
/// it finishes. At most `maxQueued` wait: a newer packet pushes the oldest
/// out (the remote sees a gap and counts it as lost), so a slow link costs
/// a dropout, never a growing delay.
public struct MirrorAudioSendQueue<Item: Sendable>: Sendable {
    /// About 85 ms of AAC packets.
    public static var defaultMaxQueued: Int { 4 }

    public let maxQueued: Int
    public private(set) var queued: [Item] = []
    public private(set) var isSending = false
    /// Packets pushed out since the last `takeDropped()`.
    public private(set) var dropped = 0

    public init(maxQueued: Int = Self.defaultMaxQueued) {
        self.maxQueued = max(1, maxQueued)
    }

    /// Queues `item`, dropping the oldest waiting one when full.
    public mutating func enqueue(_ item: Item) {
        queued.append(item)
        if queued.count > maxQueued {
            let excess = queued.count - maxQueued
            queued.removeFirst(excess)
            dropped += excess
        }
    }

    /// The packets to send now, oldest first, or `nil` while a send is on
    /// the wire or nothing waits. Marks a send as started.
    public mutating func takeBatch() -> [Item]? {
        guard !isSending, !queued.isEmpty else { return nil }
        isSending = true
        defer { queued.removeAll(keepingCapacity: true) }
        return queued
    }

    /// The send started by `takeBatch()` finished (or failed).
    public mutating func sendFinished() {
        isSending = false
    }

    public mutating func takeDropped() -> Int {
        defer { dropped = 0 }
        return dropped
    }

    /// Empties the queue (stream closed). A send on the wire still calls
    /// `sendFinished()`.
    public mutating func removeAll() {
        queued.removeAll()
    }
}
