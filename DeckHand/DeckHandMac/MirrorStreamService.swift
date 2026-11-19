//
//  MirrorStreamService.swift
//  DeckHandMac
//
//  The live mirror for remotes (WID-403), on its own binary Loom stream.
//
//  Pipeline:
//
//    SCStream (GPU-downscaled BGRA, capped fps, no pointer)
//        → sample-handler queue: CVPixelBuffer → CGImage → JPEG (ImageIO)
//        → MainActor: one `BinaryFrameHeader` frame per remote, on that
//          remote's `PixelHandStream.mirror` stream (`MirrorSubscriber`)
//
//    60 Hz on the MainActor while streaming:
//        pointer position and shape (`MirrorCursorSampler`) → each remote,
//        throttled; once a second, stats → each remote as
//        `diagnostics.mirrorStats`.
//
//  The control stream only carries `mirror.start` / `stop` / `displayList`
//  / `error` and the stats, so a frame never queues ahead of input or a
//  heartbeat.
//
//  Performance / memory invariants:
//
//   • LATEST-FRAME-WINS. While a frame is being encoded, new frames are
//     dropped at the top of the sample handler, and a remote whose previous
//     frame is still on the wire skips the next one. Nothing is queued, so a
//     slow link lowers that remote's frame rate instead of growing memory
//     and latency or stalling the other remotes.
//   • The GPU does the downsample inside ScreenCaptureKit (the stream
//     configuration is sized to the *target* output), so native-resolution
//     pixels never reach the CPU.
//   • One reusable CIContext; no per-frame context or colorspace churn.
//   • The capture is torn down when the last remote leaves, on disconnect,
//     and on stream error: there is no idle capture.
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
    /// Cursor sampling period (60 Hz).
    private static let cursorTick: Duration = .milliseconds(16)
    /// Read the pointer's shape every Nth cursor tick (about 10 Hz).
    private static let shapeEveryTicks = 6

    // MARK: - State

    private var subscribers: [UUID: MirrorSubscriber] = [:]
    private var stream: SCStream?
    private var output: MirrorFrameOutput?
    /// Display currently being captured. `0` is not a valid CGDirectDisplayID
    /// in practice; treated as "unset" until the first successful start.
    private var currentDisplayID: CGDirectDisplayID = 0
    private var currentFPS = 20
    private var currentMaxWidth = 640
    /// Size of the frames the capture produces, for the stats.
    private var frameWidth = 0
    private var frameHeight = 0
    /// Serial queue ScreenCaptureKit delivers frames on. Encoding happens
    /// here too, keeping all pixel work off the main thread.
    private let sampleQueue = DispatchQueue(label: "com.widgetsflow.pixelhand.mirror.frames", qos: .userInteractive)
    private var screenObserver: NSObjectProtocol?
    /// Start, stop and display changes run one at a time. These methods
    /// await, so without this two `startMirror`s interleaved: both saw no
    /// stream, both built one, and the orphan kept capturing.
    private let lifecycle = SerialTaskQueue()

    /// S3: the pointer, sampled while the capture runs.
    private let cursorSampler = MirrorCursorSampler()
    private var cursorTask: Task<Void, Never>?
    /// The capture's half of the stats (frames captured, encode time),
    /// shared by every remote.
    private var captureCounter = MirrorStatsCounter()
    private var statsWindowStart = ContinuousClock.now
    /// Each remote's last stats, for the log line when its own stats arrive.
    private(set) var lastHostStats: [UUID: MirrorHostStats] = [:]

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

    /// Adds `handle` as a mirror subscriber, starting the capture if it
    /// isn't running, and opens its binary stream. A start from a remote
    /// that is already watching changes the capture in place: another
    /// display restarts it, another rate or size updates its
    /// configuration. One capture serves every remote, so the latest
    /// request wins.
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
        let subscriber = subscribers[subscriberID] ?? MirrorSubscriber(id: subscriberID, handle: handle)
        guard await subscriber.open() else {
            subscribers.removeValue(forKey: subscriberID)
            try? await handle.send(.mirror(.error(message: "Live mirror unavailable: couldn't open the mirror stream.")))
            if subscribers.isEmpty { await teardownStream() }
            return
        }
        subscribers[subscriberID] = subscriber

        let clampedFPS = max(1, min(fps, Self.maxAllowedFPS))
        let clampedWidth = max(120, min(maxWidth, Self.maxAllowedWidth))
        let requestedID = displayID.map { CGDirectDisplayID($0) }
        let needsNewStream = stream == nil
            || (requestedID != nil && requestedID != currentDisplayID)
        let needsReconfigure = !needsNewStream
            && (clampedFPS != currentFPS || clampedWidth != currentMaxWidth)
        currentFPS = clampedFPS
        currentMaxWidth = clampedWidth

        if needsNewStream {
            await teardownStream()
            do {
                try await startStream(
                    fps: clampedFPS,
                    maxWidth: clampedWidth,
                    preferredDisplayID: requestedID
                )
                DeckHandLog.app.info("Mirror stream started (\(clampedFPS, privacy: .public) fps, \(clampedWidth, privacy: .public)px, display \(self.currentDisplayID, privacy: .public))")
            } catch {
                DeckHandLog.app.error("Mirror stream failed to start: \(error.localizedDescription, privacy: .public)")
                subscribers.removeValue(forKey: subscriberID)
                await subscriber.close()
                try? await handle.send(.mirror(.error(
                    message: "Live mirror unavailable: \(error.localizedDescription)"
                )))
                return
            }
            for other in subscribers.values { other.markFormatChanged() }
        } else if needsReconfigure {
            await reconfigureStream()
        }

        await sendDisplayList(to: handle)
    }

    /// Removes a subscriber and closes its binary stream; tears the capture
    /// down when none remain. Safe to call redundantly (disconnect path +
    /// explicit stop).
    ///
    /// Queued behind any start still in progress (so a start can't re-add a
    /// subscriber that already left) but doesn't wait for it: the caller is
    /// a connection's cleanup, which must not hang on ScreenCaptureKit.
    func stop(subscriberID: UUID) async {
        lifecycle.enqueue { [weak self] in
            guard let self,
                  let subscriber = self.subscribers.removeValue(forKey: subscriberID) else { return }
            self.lastHostStats.removeValue(forKey: subscriberID)
            await subscriber.close()
            if self.subscribers.isEmpty {
                await self.teardownStream()
            }
        }
    }

    // MARK: - Stream control

    private func configuration(for display: SCDisplay, fps: Int, maxWidth: Int) -> SCStreamConfiguration {
        let aspect = CGFloat(display.height) / CGFloat(display.width)
        let config = SCStreamConfiguration()
        config.width = maxWidth
        config.height = Int((CGFloat(maxWidth) * aspect).rounded())
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // Small queue: stale frames are worthless for a live mirror.
        config.queueDepth = 3
        // S3: the remote draws the pointer itself from the cursor updates,
        // so it moves at 60 Hz and isn't smeared by JPEG.
        config.showsCursor = false
        config.capturesAudio = false
        return config
    }

    private func startStream(
        fps: Int,
        maxWidth: Int,
        preferredDisplayID: CGDirectDisplayID?
    ) async throws {
        let display = try await ScreenCaptureService.shared.display(matching: preferredDisplayID)
        currentDisplayID = display.displayID

        let config = configuration(for: display, fps: fps, maxWidth: maxWidth)
        frameWidth = config.width
        frameHeight = config.height
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let output = MirrorFrameOutput { [weak self] source, frame in
            // Called on `sampleQueue` after encode. Hop to the MainActor to
            // hand the frame to each subscriber that's ready, then free the
            // encoder. The flag cleared is the one on the output that made
            // this frame: clearing `self.output`'s instead let an old
            // stream's frame unblock (or never unblock) a new one.
            Task { @MainActor [weak self] in
                self?.broadcast(frame, from: source)
                source.finishFrame()
            }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        startCursorLoop()
    }

    /// Applies a new rate or size to the running capture without
    /// restarting it; restarts if ScreenCaptureKit refuses.
    private func reconfigureStream() async {
        guard let stream else { return }
        do {
            let display = try await ScreenCaptureService.shared.display(matching: currentDisplayID)
            let config = configuration(for: display, fps: currentFPS, maxWidth: currentMaxWidth)
            try await stream.updateConfiguration(config)
            frameWidth = config.width
            frameHeight = config.height
            for subscriber in subscribers.values { subscriber.markFormatChanged() }
            DeckHandLog.app.info("Mirror stream reconfigured (\(self.currentFPS, privacy: .public) fps, \(self.currentMaxWidth, privacy: .public)px)")
        } catch {
            DeckHandLog.app.error("Mirror reconfigure failed, restarting: \(error.localizedDescription, privacy: .public)")
            await teardownStream()
            do {
                try await startStream(fps: currentFPS, maxWidth: currentMaxWidth, preferredDisplayID: currentDisplayID)
                for subscriber in subscribers.values { subscriber.markFormatChanged() }
            } catch {
                handleStreamFailure(error)
            }
        }
    }

    private func teardownStream() async {
        stopCursorLoop()
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
                for subscriber in subscribers.values { subscriber.markFormatChanged() }
            } catch {
                handleStreamFailure(error)
                return
            }
        }
        for subscriber in subscribers.values {
            await sendDisplayList(to: subscriber.handle)
        }
    }

    private func sendDisplayList(to handle: LoomConnectionHandle) async {
        let displays = (try? await ScreenCaptureService.shared.enumerateDisplays()) ?? []
        try? await handle.send(.mirror(.displayList(
            displays: displays,
            selectedDisplayID: currentDisplayID
        )))
    }

    /// Called by `MirrorFrameOutput` when ScreenCaptureKit reports the
    /// stream died (display unplugged, TCC revoked mid-stream, …).
    fileprivate func handleStreamFailure(_ error: Error) {
        DeckHandLog.app.error("Mirror stream error: \(error.localizedDescription, privacy: .public)")
        let dropped = Array(subscribers.values)
        subscribers.removeAll()
        lastHostStats.removeAll()
        stopCursorLoop()
        stream = nil
        output = nil
        currentDisplayID = 0
        for subscriber in dropped {
            Task {
                await subscriber.close()
                try? await subscriber.handle.send(.mirror(.error(
                    message: "Live mirror stopped: \(error.localizedDescription)"
                )))
            }
        }
    }

    /// Hands a frame to every remote; each one drops it if its previous
    /// frame is still on the wire.
    private func broadcast(_ frame: MirrorEncodedFrame, from source: MirrorFrameOutput) {
        // Drop frames from a stream that has since been replaced or stopped.
        guard source === output else { return }
        captureCounter.noteFrameIn()
        captureCounter.noteWork(seconds: frame.encodeSeconds)
        captureCounter.noteDropped(frame.droppedBefore)
        for subscriber in subscribers.values {
            subscriber.sendFrame(jpeg: frame.jpeg, presentationTimeMicros: frame.presentationTimeMicros)
        }
    }

    // MARK: - Cursor and stats loop

    private func startCursorLoop() {
        stopCursorLoop()
        cursorSampler.reset()
        captureCounter.reset()
        statsWindowStart = .now
        for subscriber in subscribers.values {
            subscriber.cursorThrottle.reset()
            subscriber.counter.reset()
        }
        cursorTask = Task { @MainActor [weak self] in
            var tick = 0
            var shape: MirrorCursorShape?
            while !Task.isCancelled {
                guard let self else { return }
                if tick % Self.shapeEveryTicks == 0 {
                    shape = self.cursorSampler.currentShape()
                }
                self.sendCursor(shape: shape)
                self.sendStatsIfDue()
                tick &+= 1
                try? await Task.sleep(for: Self.cursorTick)
            }
        }
    }

    private func stopCursorLoop() {
        cursorTask?.cancel()
        cursorTask = nil
    }

    private func sendCursor(shape: MirrorCursorShape?) {
        guard currentDisplayID != 0,
              let state = cursorSampler.state(mirroredDisplayID: currentDisplayID, shapeID: shape?.id ?? 0)
        else { return }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        let micros = DispatchTime.now().uptimeNanoseconds / 1_000
        for subscriber in subscribers.values where subscriber.cursorThrottle.shouldSend(state, now: now) {
            subscriber.sendCursor(state, shape: shape, presentationTimeMicros: micros)
        }
    }

    /// Once a second: each remote gets its stats over the control stream.
    private func sendStatsIfDue() {
        let elapsed = ContinuousClock.now - statsWindowStart
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        guard seconds >= MirrorStatsPolicy.reportInterval else { return }
        statsWindowStart = .now
        let capture = captureCounter.hostStats(codec: .jpeg, width: frameWidth, height: frameHeight, elapsed: seconds)
        captureCounter.reset()
        for subscriber in subscribers.values {
            var stats = subscriber.counter.hostStats(codec: .jpeg, width: frameWidth, height: frameHeight, elapsed: seconds)
            stats.capturedFPS = capture.capturedFPS
            stats.encodeMilliseconds = capture.encodeMilliseconds
            stats.droppedFrames += capture.droppedFrames
            subscriber.counter.reset()
            lastHostStats[subscriber.id] = stats
            let handle = subscriber.handle
            Task { try? await handle.send(.diagnostics(.mirrorStats(stats: stats))) }
        }
    }
}

// MARK: - SCStreamOutput handler

/// One encoded frame and what it cost.
private struct MirrorEncodedFrame: Sendable {
    let jpeg: Data
    let presentationTimeMicros: UInt64
    let encodeSeconds: Double
    /// Frames ScreenCaptureKit delivered while the encoder was busy, since
    /// the previous encoded frame.
    let droppedBefore: Int
}

/// Receives frames on the sample-handler queue, encodes, and forwards.
/// `@unchecked Sendable` because all mutable state is confined to the
/// sample-handler queue except `busy` and `skipped`, which are
/// lock-protected (`busy` is cleared from the MainActor once the frame is
/// handed to the senders).
private final class MirrorFrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Called with this output and the encoded frame, on the sample queue.
    private let onFrame: (MirrorFrameOutput, MirrorEncodedFrame) -> Void

    private let lock = NSLock()
    private var busy = false
    private var skipped = 0

    /// Reused CIContext — creating one per frame would re-allocate GPU
    /// resources 20× per second.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init(onFrame: @escaping (MirrorFrameOutput, MirrorEncodedFrame) -> Void) {
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
            skipped += 1
            lock.unlock()
            return
        }
        busy = true
        let droppedBefore = skipped
        skipped = 0
        lock.unlock()

        let started = DispatchTime.now().uptimeNanoseconds
        guard let jpeg = Self.encode(sampleBuffer, context: ciContext) else {
            finishFrame()
            return
        }
        let encodeSeconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let micros = pts.isValid && pts.seconds.isFinite && pts.seconds >= 0
            ? UInt64(pts.seconds * 1_000_000)
            : DispatchTime.now().uptimeNanoseconds / 1_000
        onFrame(self, MirrorEncodedFrame(
            jpeg: jpeg,
            presentationTimeMicros: micros,
            encodeSeconds: encodeSeconds,
            droppedBefore: droppedBefore
        ))
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
