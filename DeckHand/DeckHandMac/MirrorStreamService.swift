//
//  MirrorStreamService.swift
//  DeckHandMac
//
//  Live mini-mirror stream for the iPad control surface (WID-403).
//
//  Pipeline:
//
//    SCStream (GPU-downscaled BGRA, capped fps)
//        → sample-handler queue: CVPixelBuffer → CGImage → JPEG (ImageIO)
//        → MainActor: ControlMessage.mirrorFrame broadcast to subscribers
//
//  Performance / memory invariants:
//
//   • LATEST-FRAME-WINS. While a frame is being encoded, new frames are
//     dropped at the top of the sample handler, and a subscriber whose
//     previous frame is still on the wire skips the next one — nothing is
//     ever queued, so a slow Wi-Fi link degrades to a lower effective frame
//     rate for that remote only, instead of ballooning memory and latency
//     or stalling the other remotes.
//   • The GPU does the downsample inside ScreenCaptureKit (the stream
//     configuration is sized to the *target* output), so we never touch
//     native-resolution pixels on the CPU. A ~480px frame encodes to
//     ~10–30 KB JPEG.
//   • One reusable CIContext; no per-frame context or colorspace churn.
//   • The stream is torn down when the last subscriber leaves, on
//     disconnect, and on stream error — there is no idle capture.
//

import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import LoomKit
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

/// JPEG quality for mirror frames. File-scope so the off-MainActor encoder
/// can read it without actor hops. 0.5 is the sweet spot for screen
/// content: visibly crisper text than 0.4 for roughly +35% payload, still
/// well inside LAN budgets with latest-frame-wins absorbing congestion.
private let mirrorJPEGQuality: CGFloat = 0.5

@MainActor
final class MirrorStreamService: NSObject {
    static let shared = MirrorStreamService()

    // MARK: - Tunables

    /// Hard caps regardless of what the client asks for, so a buggy or
    /// malicious client can't make the host capture at full resolution
    /// or unbounded rate.
    private static let maxAllowedFPS = 30
    /// Covers the iPad's fully pinched-out mirror at close to Retina
    /// density; still below native capture, and the latest-frame-wins
    /// policy below absorbs the extra encode cost by dropping frames
    /// rather than queueing them.
    private static let maxAllowedWidth = 1920

    // MARK: - State

    private var subscribers: [UUID: LoomConnectionHandle] = [:]
    private var stream: SCStream?
    private var output: MirrorFrameOutput?
    /// Display currently being captured. `0` is not a valid CGDirectDisplayID
    /// in practice; treated as "unset" until the first successful start.
    private var currentDisplayID: CGDirectDisplayID = 0
    private var currentFPS = 20
    private var currentMaxWidth = 640
    /// Serial queue ScreenCaptureKit delivers frames on. Encoding happens
    /// here too, keeping all pixel work off the main thread.
    private let sampleQueue = DispatchQueue(label: "com.widgetsflow.pixelhand.mirror.frames", qos: .userInteractive)
    private var screenObserver: NSObjectProtocol?
    /// Start, stop and display changes run one at a time. These methods
    /// await, so without this two `startMirror`s interleaved: both saw no
    /// stream, both built one, and the orphan kept capturing.
    private let lifecycle = SerialTaskQueue()
    /// Subscribers with a frame send still in flight. Each gets at most one
    /// at a time, and one stuck peer no longer holds up everyone else.
    private var sendingTo: Set<UUID> = []

    private override init() {
        super.init()
        // If a panel is unplugged mid-stream, the SCDisplay we captured
        // becomes invalid. Drop back to the main display and tell every
        // subscriber which monitors remain.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Serialized with start/stop, which also replace the stream.
                await self?.lifecycle.run {
                    await MirrorStreamService.shared.handleScreensChanged()
                }
            }
        }
    }

    // MARK: - Subscriber lifecycle

    /// Adds `handle` as a mirror subscriber, starting the capture stream
    /// if it isn't running. Passing a `displayID` that differs from the
    /// current stream retargets capture for every subscriber — one stream,
    /// one display. The first subscriber's fps/width preferences win until
    /// the stream restarts.
    func start(
        subscriberID: UUID,
        handle: LoomConnectionHandle,
        fps: Int,
        maxWidth: Int,
        displayID: UInt32?
    ) async {
        await lifecycle.run { [weak self] in
            await self?.performStart(
                subscriberID: subscriberID,
                handle: handle,
                fps: fps,
                maxWidth: maxWidth,
                displayID: displayID
            )
        }
    }

    private func performStart(
        subscriberID: UUID,
        handle: LoomConnectionHandle,
        fps: Int,
        maxWidth: Int,
        displayID: UInt32?
    ) async {
        subscribers[subscriberID] = handle

        let clampedFPS = max(1, min(fps, Self.maxAllowedFPS))
        let clampedWidth = max(120, min(maxWidth, Self.maxAllowedWidth))
        currentFPS = clampedFPS
        currentMaxWidth = clampedWidth

        let requestedID = displayID.map { CGDirectDisplayID($0) }
        let needsNewStream = stream == nil
            || (requestedID != nil && requestedID != currentDisplayID)

        if needsNewStream {
            await teardownStream()
            do {
                try await startStream(
                    fps: clampedFPS,
                    maxWidth: clampedWidth,
                    preferredDisplayID: displayID.map { CGDirectDisplayID($0) }
                )
                DeckHandLog.app.info("Mirror stream started (\(clampedFPS, privacy: .public) fps, \(clampedWidth, privacy: .public)px, display \(self.currentDisplayID, privacy: .public))")
            } catch {
                DeckHandLog.app.error("Mirror stream failed to start: \(error.localizedDescription, privacy: .public)")
                subscribers.removeValue(forKey: subscriberID)
                try? await handle.send(.screenshotError(
                    requestID: "mirror",
                    message: "Live mirror unavailable: \(error.localizedDescription)"
                ))
                return
            }
        }

        await sendDisplayList(to: handle)
    }

    /// Removes a subscriber; tears the stream down when none remain.
    /// Safe to call redundantly (disconnect path + explicit stopMirror).
    ///
    /// Queued behind any start still in progress (so a start can't re-add a
    /// subscriber that already left) but doesn't wait for it: the caller is
    /// a connection's cleanup, which must not hang on ScreenCaptureKit.
    func stop(subscriberID: UUID) async {
        lifecycle.enqueue { [weak self] in
            guard let self,
                  self.subscribers.removeValue(forKey: subscriberID) != nil else { return }
            if self.subscribers.isEmpty {
                await self.teardownStream()
            }
        }
    }

    // MARK: - Stream control

    private func startStream(
        fps: Int,
        maxWidth: Int,
        preferredDisplayID: CGDirectDisplayID?
    ) async throws {
        let display = try await ScreenCaptureService.shared.display(matching: preferredDisplayID)
        currentDisplayID = display.displayID

        let aspect = CGFloat(display.height) / CGFloat(display.width)
        let config = SCStreamConfiguration()
        config.width = maxWidth
        config.height = Int((CGFloat(maxWidth) * aspect).rounded())
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // Small queue: stale frames are worthless for a live mirror.
        config.queueDepth = 3
        config.showsCursor = true
        config.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let output = MirrorFrameOutput { [weak self] source, jpegData, seq in
            // Called on `sampleQueue` after encode. Hop to the MainActor to
            // hand the frame to each subscriber that's ready, then free the
            // encoder. The flag cleared is the one on the output that made
            // this frame: clearing `self.output`'s instead let an old
            // stream's frame unblock (or never unblock) a new one.
            Task { @MainActor [weak self] in
                self?.broadcast(jpegData, seq: seq, from: source)
                source.finishFrame()
            }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
    }

    private func teardownStream() async {
        guard let stream else { return }
        self.stream = nil
        self.output = nil
        try? await stream.stopCapture()
        DeckHandLog.app.info("Mirror stream stopped")
    }

    /// Re-resolve the captured display after a plug/unplug. If the current
    /// id is gone, drop back to the main display rather than dying.
    private func handleScreensChanged() async {
        guard stream != nil, !subscribers.isEmpty else { return }
        let displays = (try? await ScreenCaptureService.shared.enumerateDisplays()) ?? []
        let stillPresent = displays.contains { $0.displayID == currentDisplayID }
        if !stillPresent {
            await teardownStream()
            do {
                try await startStream(
                    fps: currentFPS,
                    maxWidth: currentMaxWidth,
                    preferredDisplayID: nil
                )
            } catch {
                handleStreamFailure(error)
                return
            }
        }
        for handle in subscribers.values {
            await sendDisplayList(to: handle)
        }
    }

    private func sendDisplayList(to handle: LoomConnectionHandle) async {
        let displays = (try? await ScreenCaptureService.shared.enumerateDisplays()) ?? []
        try? await handle.send(.displayListUpdate(
            displays: displays,
            selectedDisplayID: currentDisplayID
        ))
    }

    /// Called by `MirrorFrameOutput` when ScreenCaptureKit reports the
    /// stream died (display unplugged, TCC revoked mid-stream, …).
    fileprivate func handleStreamFailure(_ error: Error) {
        DeckHandLog.app.error("Mirror stream error: \(error.localizedDescription, privacy: .public)")
        let handles = Array(subscribers.values)
        subscribers.removeAll()
        stream = nil
        output = nil
        currentDisplayID = 0
        for handle in handles {
            Task {
                try? await handle.send(.screenshotError(
                    requestID: "mirror",
                    message: "Live mirror stopped: \(error.localizedDescription)"
                ))
            }
        }
    }

    /// Latest-frame-wins per subscriber: a subscriber whose previous frame
    /// is still on the wire skips this one. Sends used to run one after
    /// another while the encoder waited, so a single hung `send` froze the
    /// mirror for every remote.
    private func broadcast(_ data: Data, seq: UInt64, from source: MirrorFrameOutput) {
        // Drop frames from a stream that has since been replaced or stopped.
        guard source === output else { return }
        for (id, handle) in subscribers where !sendingTo.contains(id) {
            sendingTo.insert(id)
            Task { @MainActor [weak self] in
                try? await handle.send(.mirrorFrame(seq: seq, data: data))
                self?.sendingTo.remove(id)
            }
        }
    }
}

// MARK: - SCStreamOutput handler

/// Receives frames on the sample-handler queue, encodes, and forwards.
/// `@unchecked Sendable` because all mutable state is confined to the
/// sample-handler queue except `busy`, which is lock-protected (it's
/// cleared from the MainActor once the frame is handed to the senders).
private final class MirrorFrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Called with this output, the encoded JPEG and its sequence number,
    /// on the sample queue.
    private let onFrame: (MirrorFrameOutput, Data, UInt64) -> Void

    private let lock = NSLock()
    private var busy = false
    private var seq: UInt64 = 0

    /// Reused CIContext — creating one per frame would re-allocate GPU
    /// resources 20× per second.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init(onFrame: @escaping (MirrorFrameOutput, Data, UInt64) -> Void) {
        self.onFrame = onFrame
    }

    /// Clears the in-flight flag once the frame has been shipped.
    func finishFrame() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Latest-frame-wins: drop everything while a frame is in flight.
        lock.lock()
        if busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()

        guard let frameData = Self.encode(sampleBuffer, context: ciContext) else {
            finishFrame()
            return
        }

        seq &+= 1
        onFrame(self, frameData, seq)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            MirrorStreamService.shared.handleStreamFailure(error)
        }
    }

    /// CVPixelBuffer → CGImage → JPEG. Skips incomplete frames (SCK emits
    /// status markers for idle/blank ticks that carry no pixels).
    private static func encode(_ sampleBuffer: CMSampleBuffer, context: CIContext) -> Data? {
        // Only encode frames marked complete.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: mirrorJPEGQuality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
