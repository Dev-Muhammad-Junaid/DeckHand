//
//  MirrorStreamService.swift
//  DeckHandMac
//
//  The live mirror for remotes (WID-403), on its own binary Loom stream.
//
//  Pipeline:
//
//    SCStream (GPU-downscaled, capped fps, no pointer; BGRA, or NV12
//    `420v` while an HEVC remote watches)
//        → sample-handler queue, per codec the remotes asked for:
//            JPEG: CVPixelBuffer → CGImage → JPEG (ImageIO)
//            HEVC (S5): CVPixelBuffer → VTCompressionSession
//              (`Mirror/MirrorHEVCEncoder.swift`)
//        → MainActor: `BinaryFrameHeader` frames to each remote of that
//          codec, on its `PixelHandStream.mirror` stream (`MirrorSubscriber`)
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
//   • HEVC frames depend on each other: they go out in order, and a remote
//     that falls behind drops deltas until the next key frame
//     (`MirrorVideoBackpressure`), which the encoder makes on request
//     (`MirrorKeyFramePolicy`) and every ~2 s anyway.
//   • LATEST-FRAME-WINS (JPEG). While a frame is being encoded, new frames are
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
import VideoToolbox

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
    /// The capture's pixel format: NV12 while an HEVC remote watches (the
    /// encoder's native input), BGRA otherwise.
    private var currentPixelFormat: OSType = kCVPixelFormatType_32BGRA
    /// No HEVC encoder could be made on this Mac; every remote gets JPEG.
    private var hevcUnavailable = false
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
        displayID: UInt32?,
        codec: MirrorCodec
    ) async {
        await lifecycle.run { [weak self] in
            await self?.performStart(
                subscriberID: subscriberID,
                handle: handle,
                fps: fps,
                maxWidth: maxWidth,
                displayID: displayID,
                codec: codec
            )
        }
    }

    /// A remote's HEVC picture broke (`mirror.requestKeyFrame`).
    func requestKeyFrame(subscriberID: UUID) {
        guard subscribers[subscriberID]?.codec == .hevc else { return }
        output?.requestKeyFrame()
    }

    private func performStart(
        subscriberID: UUID,
        handle: LoomConnectionHandle,
        fps: Int,
        maxWidth: Int,
        displayID: UInt32?,
        codec: MirrorCodec
    ) async {
        let subscriber = subscribers[subscriberID] ?? MirrorSubscriber(id: subscriberID, handle: handle)
        // This Mac has no HEVC encoder: JPEG it is (the remote shows what
        // arrives, and the stats say JPEG).
        subscriber.codec = hevcUnavailable ? .jpeg : codec
        subscriber.onNeedsKeyFrame = { [weak self] in self?.output?.requestKeyFrame() }
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
            && (clampedFPS != currentFPS || clampedWidth != currentMaxWidth || pixelFormat != currentPixelFormat)
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
        updateOutputModes()

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
            } else {
                self.updateOutputModes()
            }
        }
    }

    // MARK: - Stream control

    /// The pixel format the remotes watching now call for.
    private var pixelFormat: OSType {
        subscribers.values.contains { $0.codec == .hevc }
            ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            : kCVPixelFormatType_32BGRA
    }

    private func configuration(for display: SCDisplay, fps: Int, maxWidth: Int) -> SCStreamConfiguration {
        let aspect = CGFloat(display.height) / CGFloat(display.width)
        let config = SCStreamConfiguration()
        // Even sizes: HEVC needs them, JPEG doesn't mind.
        config.width = MirrorVideoBitrate.evenDimension(maxWidth)
        config.height = MirrorVideoBitrate.evenDimension(Int((CGFloat(maxWidth) * aspect).rounded()))
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        let format = pixelFormat
        config.pixelFormat = format
        currentPixelFormat = format
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

        let output = MirrorFrameOutput(fps: fps) { [weak self] source, frame in
            // Called on `sampleQueue` after encode. Hop to the MainActor to
            // hand the frame to each subscriber that's ready, then free the
            // encoder. The flag cleared is the one on the output that made
            // this frame: clearing `self.output`'s instead let an old
            // stream's frame unblock (or never unblock) a new one.
            Task { @MainActor [weak self] in
                self?.broadcast(frame, from: source)
                source.finishFrame()
            }
        } onHEVCFrame: { source, frame in
            // VideoToolbox's thread. `DispatchQueue.main` keeps encode
            // order, which HEVC needs (Tasks don't promise it).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MirrorStreamService.shared.broadcastHEVC(frame, from: source)
                }
            }
        } onHEVCUnavailable: {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MirrorStreamService.shared.handleHEVCUnavailable()
                }
            }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        updateOutputModes()
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
            output?.setFrameRate(currentFPS)
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
        let hasHEVC = subscribers.values.contains { $0.codec == .hevc }
        if !hasHEVC { captureCounter.noteFrameIn() } // else counted by broadcastHEVC
        captureCounter.noteWork(seconds: frame.encodeSeconds)
        captureCounter.noteDropped(frame.droppedBefore)
        for subscriber in subscribers.values where subscriber.codec == .jpeg {
            subscriber.sendFrame(jpeg: frame.jpeg, presentationTimeMicros: frame.presentationTimeMicros)
        }
    }

    /// Hands an HEVC frame to every HEVC remote, in encode order.
    fileprivate func broadcastHEVC(_ frame: MirrorHEVCEncodedFrame, from source: MirrorFrameOutput) {
        guard source === output else { return }
        captureCounter.noteFrameIn()
        captureCounter.noteWork(seconds: frame.encodeSeconds)
        captureCounter.noteDropped(source.takeHEVCSkippedCount())
        for subscriber in subscribers.values where subscriber.codec == .hevc {
            subscriber.sendHEVC(frame)
        }
    }

    /// No HEVC encoder on this Mac: switch every HEVC remote to JPEG.
    fileprivate func handleHEVCUnavailable() {
        guard !hevcUnavailable else { return }
        hevcUnavailable = true
        for subscriber in subscribers.values where subscriber.codec == .hevc {
            subscriber.codec = .jpeg
        }
        updateOutputModes()
        lifecycle.enqueue { [weak self] in
            await self?.reconfigureStream() // back to BGRA
        }
    }

    /// Tells the frame output which encoders the remotes need.
    private func updateOutputModes() {
        let codecs = Set(subscribers.values.map(\.codec))
        output?.setModes(jpeg: codecs.contains(.jpeg), hevc: codecs.contains(.hevc))
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
            var stats = subscriber.counter.hostStats(codec: subscriber.codec, width: frameWidth, height: frameHeight, elapsed: seconds)
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
/// sample-handler queue except `busy`, `skipped` and the modes, which are
/// lock-protected (`busy` is cleared from the MainActor once the frame is
/// handed to the senders). The HEVC encoder has its own lock.
private final class MirrorFrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Called with this output and the encoded frame, on the sample queue.
    private let onFrame: (MirrorFrameOutput, MirrorEncodedFrame) -> Void

    private let lock = NSLock()
    private var busy = false
    private var skipped = 0
    private var wantsJPEG = true
    private var wantsHEVC = false
    /// Made on the first HEVC frame, released with this output.
    private var hevc: MirrorHEVCEncoder?
    private let hevcLock = NSLock()
    private var fps: Int
    private let onHEVCFrame: @Sendable (MirrorFrameOutput, MirrorHEVCEncodedFrame) -> Void
    private let onHEVCUnavailable: @Sendable () -> Void

    /// Reused CIContext — creating one per frame would re-allocate GPU
    /// resources 20× per second.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init(
        fps: Int,
        onFrame: @escaping (MirrorFrameOutput, MirrorEncodedFrame) -> Void,
        onHEVCFrame: @escaping @Sendable (MirrorFrameOutput, MirrorHEVCEncodedFrame) -> Void,
        onHEVCUnavailable: @escaping @Sendable () -> Void
    ) {
        self.fps = fps
        self.onFrame = onFrame
        self.onHEVCFrame = onHEVCFrame
        self.onHEVCUnavailable = onHEVCUnavailable
    }

    deinit {
        hevc?.invalidate()
    }

    /// Which encoders run for each captured frame.
    func setModes(jpeg: Bool, hevc: Bool) {
        lock.lock()
        wantsJPEG = jpeg
        wantsHEVC = hevc
        lock.unlock()
    }

    func setFrameRate(_ fps: Int) {
        hevcLock.lock()
        self.fps = fps
        let encoder = hevc
        hevcLock.unlock()
        encoder?.setFrameRate(fps)
    }

    func requestKeyFrame() {
        hevcLock.lock()
        let encoder = hevc
        hevcLock.unlock()
        encoder?.requestKeyFrame()
    }

    func takeHEVCSkippedCount() -> Int {
        hevcLock.lock()
        let encoder = hevc
        hevcLock.unlock()
        return encoder?.takeSkippedCount() ?? 0
    }

    private func hevcEncoder() -> MirrorHEVCEncoder {
        hevcLock.lock()
        defer { hevcLock.unlock() }
        if let hevc { return hevc }
        let encoder = MirrorHEVCEncoder { [weak self] frame in
            guard let self else { return }
            self.onHEVCFrame(self, frame)
        } onUnavailable: { [onHEVCUnavailable] in
            onHEVCUnavailable()
        }
        encoder.setFrameRate(fps)
        hevc = encoder
        return encoder
    }

    /// Clears the in-flight flag once the frame has been shipped.
    func finishFrame() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, Self.isComplete(sampleBuffer) else { return }

        lock.lock()
        let jpeg = wantsJPEG
        let hevc = wantsHEVC
        lock.unlock()

        if hevc, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            hevcEncoder().encode(pixelBuffer, presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        if jpeg {
            encodeJPEG(sampleBuffer)
        }
    }

    private func encodeJPEG(_ sampleBuffer: CMSampleBuffer) {
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

    /// SCK emits status markers for idle/blank ticks that carry no pixels;
    /// only frames marked complete are encoded.
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return false
        }
        return true
    }

    /// CVPixelBuffer (BGRA or NV12) → CGImage → JPEG.
    private static func encode(_ sampleBuffer: CMSampleBuffer, context: CIContext) -> Data? {
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
