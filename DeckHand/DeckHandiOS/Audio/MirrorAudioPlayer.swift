//
//  MirrorAudioPlayer.swift
//  DeckHandiOS
//
//  S17: plays the Mac's sound. One per connection, owned by the session
//  model (`mirrorAudio`).
//
//      reader task ─ format, packets ─▶ sequence check, jitter estimate,
//                                       decode (decodeLock)
//                                          │ interleaved Float32
//                                          ▼
//                              MirrorAudioJitterBuffer (bufferLock)
//                                          │ pull
//      AVAudioEngine render thread ◀───────┘ AVAudioSourceNode
//
//  - Late packets (at or before one already played) are dropped; a gap
//    resets the AAC decoder.
//  - The buffer aims for 60–150 ms, following the measured jitter, and
//    never grows: a burst is cut back to the target (see
//    `MirrorAudioJitterBuffer`).
//  - The audio session is `.playback` with `.mixWithOthers`: the Mac's
//    sound plays alongside the iPad's own and ignores the silent switch,
//    like a video. It is active only while sound is wanted and a stream is
//    open; background, disconnect, an interruption or turning audio off
//    stops the engine and deactivates the session.
//
//  Engine and session work runs on `controlQueue`; the render block takes
//  `bufferLock` only for the copy and never allocates.
//

import AVFoundation
import Foundation
import os

final class MirrorAudioPlayer: MirrorAudioSink, @unchecked Sendable {
    /// Largest render request served in one go; more is padded with silence.
    private static let maxRenderFrames = 8_192

    private let controlQueue = DispatchQueue(label: "com.widgetsflow.pixelhand.audio.player", qos: .userInitiated)

    // Guarded by decodeLock: what arrives.
    private let decodeLock = NSLock()
    private var decoder: MirrorAudioDecoder?
    private var tracker = MirrorAudioSequenceTracker()
    private var estimator = MirrorAudioJitterEstimator(sampleRate: MirrorAudioFormat.preferredSampleRate)
    private var lastArrival: Double?
    private var currentStream: ObjectIdentifier?

    // Guarded by bufferLock: what plays. Pulled by the render thread.
    private let bufferLock: UnsafeMutablePointer<os_unfair_lock>
    private var buffer: MirrorAudioJitterBuffer?
    private let scratch: UnsafeMutablePointer<Float>

    // controlQueue only.
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var engineFormat: (sampleRate: Int, channels: Int)?
    private var wanted = false
    private var observers: [NSObjectProtocol] = []

    init() {
        bufferLock = .allocate(capacity: 1)
        bufferLock.initialize(to: os_unfair_lock())
        scratch = .allocate(capacity: Self.maxRenderFrames * 2)
        scratch.initialize(repeating: 0, count: Self.maxRenderFrames * 2)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
                guard let self else { return }
                let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
                self.controlQueue.async { self.interrupted(ended: ended) }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                // Route change (headphones, AirPlay): the engine stopped.
                self.controlQueue.async { self.restartEngineIfNeeded(rebuild: true) }
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        engine?.stop()
        bufferLock.deinitialize(count: 1)
        bufferLock.deallocate()
        scratch.deallocate()
    }

    // MARK: Control (any thread)

    /// Whether sound should play. Returns `false` when nothing changed.
    @discardableResult
    func setWanted(_ wanted: Bool) -> Bool {
        controlQueue.sync {
            guard self.wanted != wanted else { return false }
            self.wanted = wanted
            if wanted {
                restartEngineIfNeeded()
            } else {
                stopEngine()
                withBuffer { $0?.reset() }
            }
            return true
        }
    }

    var isWanted: Bool { controlQueue.sync { wanted } }

    /// The audio part of this second's stats, or `nil` while no audio
    /// arrives.
    func takeStats() -> MirrorAudioClientStats? {
        decodeLock.lock()
        guard let decoder else {
            decodeLock.unlock()
            return nil
        }
        let counts = tracker.takeCounts()
        let jitter = estimator.jitter
        let framesPerPacket = decoder.format.framesPerPacket
        decodeLock.unlock()
        return withBuffer { buffer -> MirrorAudioClientStats? in
            guard let taken = buffer?.takeCounts(),
                  let buffered = buffer?.bufferedSeconds,
                  let target = buffer?.target
            else { return nil }
            return MirrorAudioClientStats.make(
                counts: counts,
                underruns: taken.underruns,
                trimmedFrames: taken.trimmedFrames,
                framesPerPacket: framesPerPacket,
                bufferedSeconds: buffered,
                targetSeconds: target,
                jitterSeconds: jitter
            )
        }
    }

    // MARK: MirrorAudioSink (reader task)

    func audioFormatArrived(_ format: MirrorAudioFormat, stream: ObjectIdentifier) {
        decodeLock.lock()
        currentStream = stream
        decoder = MirrorAudioDecoder(format: format)
        tracker.restart()
        estimator = MirrorAudioJitterEstimator(sampleRate: format.sampleRate)
        lastArrival = nil
        let usable = decoder != nil
        decodeLock.unlock()
        guard usable else {
            DeckHandLog.connection.error("Mirror audio: this device can't decode \(format.codec.label, privacy: .public)")
            return
        }
        withBuffer { buffer in
            if buffer?.sampleRate != format.sampleRate || buffer?.channels != format.channels {
                buffer = MirrorAudioJitterBuffer(channels: format.channels, sampleRate: format.sampleRate)
            } else {
                buffer?.reset()
            }
        }
        controlQueue.async { [self] in
            engineFormat = (format.sampleRate, format.channels)
            restartEngineIfNeeded(rebuild: true)
        }
    }

    func audioPacketArrived(_ packet: MirrorAudioPacket, arrival: Double, stream: ObjectIdentifier) {
        decodeLock.lock()
        guard stream == currentStream, let decoder else {
            decodeLock.unlock()
            return
        }
        switch tracker.note(packet.sequence) {
        case .late:
            decodeLock.unlock()
            return
        case .afterGap:
            decoder.reset()
        case .inOrder:
            break
        }
        estimator.note(sampleTime: packet.sampleTime, arrival: arrival)
        let elapsed = lastArrival.map { arrival - $0 } ?? 0
        lastArrival = arrival
        let desired = MirrorAudioJitterPolicy.standard.desiredTarget(
            jitter: estimator.jitter,
            packetDuration: decoder.format.packetDuration
        )
        let samples = decoder.decode(packet.data)
        decodeLock.unlock()

        withBuffer { buffer in
            buffer?.updateTarget(desired: desired, elapsed: elapsed)
            if !samples.isEmpty { buffer?.push(samples) }
        }
    }

    func audioStreamEnded(stream: ObjectIdentifier) {
        decodeLock.lock()
        let isCurrent = stream == currentStream
        if isCurrent {
            currentStream = nil
            decoder = nil
        }
        decodeLock.unlock()
        guard isCurrent else { return }
        withBuffer { $0?.reset() }
        controlQueue.async { [self] in
            stopEngine()
        }
    }

    // MARK: Engine (controlQueue)

    private func restartEngineIfNeeded(rebuild: Bool = false) {
        guard wanted, let format = engineFormat else { return }
        if rebuild || engine == nil {
            stopEngine()
            buildEngine(sampleRate: format.sampleRate, channels: format.channels)
        }
        guard let engine, !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
            engine.prepare()
            try engine.start()
        } catch {
            DeckHandLog.connection.error("Mirror audio: couldn't start playback: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func buildEngine(sampleRate: Int, channels: Int) {
        guard let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels)
        ) else { return }
        let engine = AVAudioEngine()
        let node = AVAudioSourceNode(format: renderFormat) { [unowned self] isSilence, _, frameCount, audioBufferList in
            self.render(frameCount: Int(frameCount), channels: channels, into: audioBufferList, isSilence: isSilence)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: renderFormat)
        self.engine = engine
        self.sourceNode = node
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.stop()
        if let sourceNode { engine.detach(sourceNode) }
        self.engine = nil
        sourceNode = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func interrupted(ended: Bool) {
        if ended {
            restartEngineIfNeeded()
        } else {
            // The system stopped the engine; start over when it ends.
            withBuffer { $0?.reset() }
        }
    }

    // MARK: Render thread

    private func render(
        frameCount: Int,
        channels: Int,
        into audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        isSilence: UnsafeMutablePointer<ObjCBool>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let frames = min(frameCount, Self.maxRenderFrames)
        let interleaved = UnsafeMutableBufferPointer(start: scratch, count: frames * channels)
        os_unfair_lock_lock(bufferLock)
        let played = buffer?.pull(frameCount: frames, into: interleaved) ?? 0
        os_unfair_lock_unlock(bufferLock)
        if played == 0 {
            interleaved.update(repeating: 0)
        }
        for (channel, audioBuffer) in buffers.enumerated() {
            guard let data = audioBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let capacity = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let source = min(channel, channels - 1)
            for frame in 0..<min(frameCount, capacity) {
                data[frame] = frame < frames ? interleaved[frame * channels + source] : 0
            }
        }
        isSilence.pointee = ObjCBool(played == 0)
        return noErr
    }

    // MARK: Helpers

    @discardableResult
    private func withBuffer<T>(_ body: (inout MirrorAudioJitterBuffer?) -> T) -> T {
        os_unfair_lock_lock(bufferLock)
        defer { os_unfair_lock_unlock(bufferLock) }
        return body(&buffer)
    }
}
