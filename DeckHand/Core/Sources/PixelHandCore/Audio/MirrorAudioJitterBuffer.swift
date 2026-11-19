//
//  MirrorAudioJitterBuffer.swift
//  PixelHandCore
//
//  S17, the remote's side of the Mac's sound: what arrives in what order,
//  how much to hold back before playing, and what to throw away so the
//  delay never grows.
//
//  The audio stream is a reliable, ordered Loom stream, so nothing is
//  reordered or lost on the way. What does happen:
//
//   • the Mac drops packets when this remote's link can't keep up
//     (`MirrorAudioSendQueue`): a gap in the sequence numbers, counted as
//     lost;
//   • Wi-Fi stalls and then delivers a burst: the buffer fills above its
//     target. Anything above target + headroom is cut from the oldest end
//     (counted as late), so the delay snaps back instead of drifting;
//   • a stall longer than the buffer: the player runs dry (an underrun),
//     fades out, plays silence and waits until the target is buffered
//     again, then fades back in.
//
//  The target follows the measured arrival jitter (RFC 3550's estimator):
//  one packet plus three times the jitter, between 60 and 150 ms. It goes
//  up at once and comes down slowly.
//
//  `MirrorAudioJitterBuffer` holds decoded PCM (interleaved Float32) in a
//  fixed ring that never grows. It isn't thread-safe: the remote guards it
//  with a lock shared by the decoder (push) and the audio render thread
//  (pull). Neither push nor pull allocates.
//

import Foundation

/// Sequence numbers in arrival order → in order, after a gap, or late.
public struct MirrorAudioSequenceTracker: Sendable, Equatable {
    public enum Verdict: Equatable, Sendable {
        /// The next packet, or the first one.
        case inOrder
        /// `lost` packets are missing just before this one. Play it (and
        /// reset a decoder that carries state between packets).
        case afterGap(lost: Int)
        /// A packet at or before one already played: drop it.
        case late
    }

    private var last: UInt32?
    public private(set) var received = 0
    public private(set) var lost = 0
    public private(set) var late = 0

    public init() {}

    public mutating func note(_ sequence: UInt32) -> Verdict {
        guard let last else {
            self.last = sequence
            received += 1
            return .inOrder
        }
        let step = sequence &- last
        // Half the number space ahead counts as ahead (wrap-around safe).
        guard step != 0, step < 1 << 31 else {
            late += 1
            return .late
        }
        self.last = sequence
        received += 1
        if step == 1 { return .inOrder }
        let missing = Int(step - 1)
        lost += missing
        return .afterGap(lost: missing)
    }

    /// A new format (a new run of sequence numbers). Counts are kept.
    public mutating func restart() {
        last = nil
    }

    /// Clears the counts for the next stats window; keeps the position.
    public mutating func takeCounts() -> (received: Int, lost: Int, late: Int) {
        defer { received = 0; lost = 0; late = 0 }
        return (received, lost, late)
    }
}

/// Interarrival jitter, as RTP measures it (RFC 3550 §6.4.1): how much the
/// gap between two packets' arrivals differs from the gap between their
/// sample times, smoothed over about 16 packets.
public struct MirrorAudioJitterEstimator: Sendable, Equatable {
    public let sampleRate: Double
    private var lastTransit: Double?
    /// Seconds.
    public private(set) var jitter: Double = 0

    public init(sampleRate: Int) {
        self.sampleRate = Double(max(sampleRate, 1))
    }

    /// A packet with `sampleTime` arrived at `arrival` (seconds, any
    /// monotonic clock on this device).
    public mutating func note(sampleTime: UInt64, arrival: Double) {
        guard arrival.isFinite else { return }
        let transit = arrival - Double(sampleTime) / sampleRate
        if let lastTransit {
            // A stall of more than a second is a pause (the Mac had
            // nothing to send), not jitter.
            let difference = min(abs(transit - lastTransit), 1)
            jitter += (difference - jitter) / 16
        }
        lastTransit = transit
    }

    public mutating func reset() {
        lastTransit = nil
        jitter = 0
    }
}

/// How much audio the remote holds back, and when it trims.
public struct MirrorAudioJitterPolicy: Sendable, Equatable {
    /// The smallest target delay (seconds). 60 ms rides out normal Wi-Fi.
    public var minimumTarget: Double
    /// The largest target delay, however bad the link.
    public var maximumTarget: Double
    /// How far above the target the buffer may fill before the oldest
    /// audio is cut back down to the target.
    public var headroom: Double
    /// Target = one packet + this × jitter.
    public var jitterMultiplier: Double
    /// How fast a lower target is followed, seconds per second.
    public var targetDecayPerSecond: Double
    /// Frames of fade at an underrun, a resume or a cut (~2 ms at 48 kHz).
    public var fadeFrames: Int

    public init(
        minimumTarget: Double = 0.06,
        maximumTarget: Double = 0.15,
        headroom: Double = 0.06,
        jitterMultiplier: Double = 3,
        targetDecayPerSecond: Double = 0.02,
        fadeFrames: Int = 96
    ) {
        self.minimumTarget = minimumTarget
        self.maximumTarget = maximumTarget
        self.headroom = headroom
        self.jitterMultiplier = jitterMultiplier
        self.targetDecayPerSecond = targetDecayPerSecond
        self.fadeFrames = fadeFrames
    }

    public static let standard = MirrorAudioJitterPolicy()

    /// The delay a link with `jitter` calls for.
    public func desiredTarget(jitter: Double, packetDuration: Double) -> Double {
        let wanted = packetDuration + jitterMultiplier * (jitter.isFinite ? jitter : 0)
        return min(max(wanted, minimumTarget), maximumTarget)
    }

    /// The longest the buffer can ever hold; its fixed capacity.
    public var capacitySeconds: Double { maximumTarget + headroom + 0.1 }
}

/// Decoded audio waiting to be played. See the file comment.
public struct MirrorAudioJitterBuffer: Sendable {
    public let channels: Int
    public let sampleRate: Int
    public let policy: MirrorAudioJitterPolicy

    private var ring: [Float]
    private let capacityFrames: Int
    private var readFrame = 0
    public private(set) var bufferedFrames = 0
    /// The delay aimed for, seconds.
    public private(set) var target: Double
    /// Waiting for `target` to fill before playing (at the start and after
    /// an underrun).
    public private(set) var isPrebuffering = true
    private var fadeInRemaining = 0

    /// Times playback ran dry.
    public private(set) var underruns = 0
    /// Frames cut to keep the delay down (bursts, or nobody pulling).
    public private(set) var trimmedFrames = 0

    public init(channels: Int, sampleRate: Int, policy: MirrorAudioJitterPolicy = .standard) {
        self.channels = max(1, channels)
        self.sampleRate = max(1, sampleRate)
        self.policy = policy
        self.capacityFrames = max(1, Int((policy.capacitySeconds * Double(max(1, sampleRate))).rounded(.up)))
        self.ring = [Float](repeating: 0, count: capacityFrames * max(1, channels))
        self.target = policy.minimumTarget
    }

    public var bufferedSeconds: Double { Double(bufferedFrames) / Double(sampleRate) }
    public var capacitySeconds: Double { Double(capacityFrames) / Double(sampleRate) }
    private var targetFrames: Int { Int((target * Double(sampleRate)).rounded()) }
    private var trimThresholdFrames: Int { Int(((target + policy.headroom) * Double(sampleRate)).rounded()) }

    /// Follows the delay the link calls for: up at once, down slowly.
    /// `elapsed` is the time since the last call.
    public mutating func updateTarget(desired: Double, elapsed: Double) {
        guard desired.isFinite else { return }
        let clamped = min(max(desired, policy.minimumTarget), policy.maximumTarget)
        if clamped >= target {
            target = clamped
        } else {
            let step = policy.targetDecayPerSecond * max(0, elapsed.isFinite ? elapsed : 0)
            target = max(clamped, target - step)
        }
    }

    /// Adds decoded audio (interleaved; a trailing partial frame is
    /// ignored). Cuts the oldest audio when the buffer fills past target +
    /// headroom.
    public mutating func push(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { push($0) }
    }

    public mutating func push(_ samples: UnsafeBufferPointer<Float>) {
        let frames = samples.count / channels
        guard frames > 0 else { return }
        // More than fits: only the newest part matters.
        let skip = max(0, frames - capacityFrames)
        var writeFrame = (readFrame + bufferedFrames) % capacityFrames
        for frame in skip..<frames {
            if bufferedFrames == capacityFrames {
                // Full: drop the oldest frame.
                readFrame = (readFrame + 1) % capacityFrames
                bufferedFrames -= 1
                trimmedFrames += 1
            }
            let source = frame * channels
            let destination = writeFrame * channels
            for channel in 0..<channels {
                ring[destination + channel] = samples[source + channel]
            }
            writeFrame = (writeFrame + 1) % capacityFrames
            bufferedFrames += 1
        }
        trimmedFrames += skip
        if bufferedFrames > trimThresholdFrames {
            let cut = bufferedFrames - targetFrames
            readFrame = (readFrame + cut) % capacityFrames
            bufferedFrames -= cut
            trimmedFrames += cut
            if !isPrebuffering { fadeInRemaining = policy.fadeFrames }
        }
    }

    /// Fills `output` with `frameCount` interleaved frames for the
    /// speaker. Returns how many frames were real audio; the rest is
    /// silence (prebuffering or an underrun).
    @discardableResult
    public mutating func pull(frameCount: Int, into output: UnsafeMutableBufferPointer<Float>) -> Int {
        let frameCount = max(0, min(frameCount, output.count / channels))
        if isPrebuffering {
            if bufferedFrames >= targetFrames, bufferedFrames > 0 {
                isPrebuffering = false
                fadeInRemaining = policy.fadeFrames
            } else {
                zero(output, fromFrame: 0, toFrame: frameCount)
                return 0
            }
        }
        let available = min(frameCount, bufferedFrames)
        for frame in 0..<available {
            var gain: Float = 1
            if fadeInRemaining > 0 {
                let done = policy.fadeFrames - fadeInRemaining
                gain = Float(done + 1) / Float(policy.fadeFrames + 1)
                fadeInRemaining -= 1
            }
            let source = ((readFrame + frame) % capacityFrames) * channels
            let destination = frame * channels
            for channel in 0..<channels {
                output[destination + channel] = ring[source + channel] * gain
            }
        }
        readFrame = (readFrame + available) % capacityFrames
        bufferedFrames -= available
        if available < frameCount {
            // Ran dry: fade out what was played, then wait for the target.
            let fade = min(policy.fadeFrames, available)
            for index in 0..<fade {
                let frame = available - fade + index
                let gain = Float(fade - index) / Float(fade + 1)
                for channel in 0..<channels {
                    output[frame * channels + channel] *= gain
                }
            }
            zero(output, fromFrame: available, toFrame: frameCount)
            underruns += 1
            isPrebuffering = true
        }
        return available
    }

    /// Empties the buffer and starts prebuffering again (a new format, a
    /// stop). Counts are kept.
    public mutating func reset() {
        readFrame = 0
        bufferedFrames = 0
        isPrebuffering = true
        fadeInRemaining = 0
    }

    /// Clears the underrun and trim counts for the next stats window.
    public mutating func takeCounts() -> (underruns: Int, trimmedFrames: Int) {
        defer { underruns = 0; trimmedFrames = 0 }
        return (underruns, trimmedFrames)
    }

    private func zero(_ output: UnsafeMutableBufferPointer<Float>, fromFrame start: Int, toFrame end: Int) {
        guard end > start else { return }
        for index in (start * channels)..<(end * channels) {
            output[index] = 0
        }
    }
}
