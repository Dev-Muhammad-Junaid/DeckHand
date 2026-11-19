//
//  MirrorAudioService.swift
//  DeckHandMac
//
//  S17: the Mac's sound on remotes while they mirror. Off by default; a
//  remote turns it on with `mirror.audio(enabled: true)`.
//
//  Pipeline:
//
//    SCStream, audio only (`MirrorAudioCapture`: system audio without
//    Pixel Hand's own, 48 kHz stereo)
//        → capture queue: Float32 → 1024-frame packets → AAC-LC
//          (`MirrorAudioEncoder`; 16-bit PCM if no AAC encoder)
//        → main queue, in order: one `audioPacket` frame to each listening
//          remote on its `PixelHandStream.audio` stream
//          (`MirrorAudioSubscriber`, drop-oldest send queue)
//
//  The audio capture is its own SCStream, not the mirror's: the mirror's
//  capture is replaced whenever the remote picks another display or a
//  window (S14) or the codec changes, and audio would click and stall each
//  time. One audio capture serves every listening remote; it stops when
//  the last one leaves, on `mirror.stop`, on disconnect and off console
//  (`MirrorStreamService.stop` calls `stop(subscriberID:)` here).
//

import Foundation
import LoomKit

@MainActor
final class MirrorAudioService {
    static let shared = MirrorAudioService()

    private var subscribers: [UUID: MirrorAudioSubscriber] = [:]
    private var capture: MirrorAudioCapture?
    /// Start and stop run one at a time (capture start awaits).
    private let lifecycle = SerialTaskQueue()

    private init() {}

    // MARK: Subscribers

    /// `mirror.audio(enabled:)` from a remote.
    func setEnabled(_ enabled: Bool, subscriberID: UUID, handle: LoomConnectionHandle) async {
        await lifecycle.run { [weak self] in
            guard let self else { return }
            if enabled {
                await self.performEnable(subscriberID: subscriberID, handle: handle)
            } else {
                await self.performDisable(subscriberID: subscriberID)
            }
        }
    }

    /// The remote's mirror stopped or it disconnected. Doesn't wait for a
    /// start in progress (the caller is a connection's cleanup).
    func stop(subscriberID: UUID) {
        lifecycle.enqueue { [weak self] in
            await self?.performDisable(subscriberID: subscriberID)
        }
    }

    /// This remote's audio stats for the mirror's stats report, starting a
    /// new window. `nil` while it isn't listening.
    func takeStats(subscriberID: UUID, elapsed: Double) -> MirrorAudioHostStats? {
        subscribers[subscriberID]?.takeStats(elapsed: elapsed)
    }

    private func performEnable(subscriberID: UUID, handle: LoomConnectionHandle) async {
        let subscriber = subscribers[subscriberID] ?? MirrorAudioSubscriber(id: subscriberID, handle: handle)
        guard await subscriber.open() else {
            subscribers.removeValue(forKey: subscriberID)
            try? await handle.send(.mirror(.audioError(message: "The Mac's sound couldn't be sent: the audio stream didn't open.")))
            await stopCaptureIfIdle()
            return
        }
        subscribers[subscriberID] = subscriber
        guard capture == nil else { return }

        let capture = MirrorAudioCapture()
        capture.onPacket = { format, packet, micros in
            // Main queue, FIFO: packets reach the subscribers in order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MirrorAudioService.shared.deliver(packet, format: format, presentationTimeMicros: micros)
                }
            }
        }
        capture.onFailure = { [weak capture] message in
            guard let capture else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MirrorAudioService.shared.captureFailed(message, from: capture)
                }
            }
        }
        self.capture = capture
        do {
            try await capture.start()
            DeckHandLog.app.info("Mirror audio started")
        } catch {
            DeckHandLog.app.error("Mirror audio failed to start: \(error.localizedDescription, privacy: .public)")
            self.capture = nil
            await failAll(message: Self.unavailableMessage(error.localizedDescription))
        }
    }

    private func performDisable(subscriberID: UUID) async {
        guard let subscriber = subscribers.removeValue(forKey: subscriberID) else { return }
        await subscriber.close()
        await stopCaptureIfIdle()
    }

    private func stopCaptureIfIdle() async {
        guard subscribers.isEmpty, let capture else { return }
        self.capture = nil
        await capture.stop()
        DeckHandLog.app.info("Mirror audio stopped")
    }

    // MARK: Capture output

    private func deliver(_ packet: MirrorAudioPacket, format: MirrorAudioFormat, presentationTimeMicros: UInt64) {
        for subscriber in subscribers.values {
            subscriber.send(packet, format: format, presentationTimeMicros: presentationTimeMicros)
        }
    }

    private func captureFailed(_ message: String, from failed: MirrorAudioCapture) {
        guard failed === capture else { return } // an old capture's late error
        DeckHandLog.app.error("Mirror audio stopped: \(message, privacy: .public)")
        lifecycle.enqueue { [weak self] in
            guard let self, failed === self.capture else { return }
            self.capture = nil
            await failed.stop()
            await self.failAll(message: Self.unavailableMessage(message))
        }
    }

    /// Tells every listening remote and closes their streams.
    private func failAll(message: String) async {
        let all = Array(subscribers.values)
        subscribers.removeAll()
        for subscriber in all {
            await subscriber.close()
            try? await subscriber.handle.send(.mirror(.audioError(message: message)))
        }
    }

    static func unavailableMessage(_ reason: String) -> String {
        "The Mac's sound couldn't be played here (\(reason)). The mirror carries on without it."
    }
}
