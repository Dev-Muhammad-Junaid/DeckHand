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
//  S14, one window instead of a display: `mirror.start(windowID:)` captures
//  with `SCContentFilter(desktopIndependentWindow:)`, sized to the window's
//  frame (`MirrorWindowGeometry`). Twice a second the window is looked at
//  (`MirrorWindowProbe` → `MirrorWindowTracker`): a resize updates the
//  capture's size in place (a new HEVC session, so a key frame, and a new
//  `displayList` with the window's size); a window that closed, was
//  minimised or left the screen, or a Mac that locked, ends the window
//  mirror: each remote gets `mirror.error` with a `fallbackDisplayID` and
//  the capture switches to the display the window was on. The pointer is
//  sent as fractions of the window.
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
    /// While a window is mirrored: the display it sits on (the fallback).
    private var currentDisplayID: CGDirectDisplayID = 0
    /// What the capture shows; `nil` while nothing is captured.
    private var currentTarget: MirrorTarget?
    /// S14: the mirrored window, as told to the remotes, its tracker and
    /// its pixels per point. `nil` while a display is mirrored.
    private var currentWindow: MirroredWindow?
    private var windowTracker: MirrorWindowTracker?
    private var windowPixelScale: Double = 2
    /// Look at the window every Nth cursor tick (about twice a second).
    private static let windowEveryTicks = 30
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
        codec: MirrorCodec,
        windowID: UInt32? = nil
    ) async {
        await lifecycle.run { [weak self] in
            await self?.performStart(
                subscriberID: subscriberID,
                handle: handle,
                fps: fps,
                maxWidth: maxWidth,
                displayID: displayID,
                codec: codec,
                windowID: windowID
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
        codec: MirrorCodec,
        windowID: UInt32?
    ) async {
        let subscriber = subscribers[subscriberID] ?? MirrorSubscriber(id: subscriberID, handle: handle)
        // This Mac has no HEVC encoder: JPEG it is (the remote shows what
        // arrives, and the stats say JPEG).
        subscriber.codec = hevcUnavailable ? .jpeg : codec
        subscriber.onNeedsKeyFrame = { [weak self] in self?.output?.requestKeyFrame() }
        guard await subscriber.open() else {
            subscribers.removeValue(forKey: subscriberID)
            let failure = CaptureFailure.reported(for: nil, fallback: .streamOpenFailed)
            try? await handle.send(.mirror(.error(message: failure.message(isMirror: true))))
            if subscribers.isEmpty { await teardownStream() }
            return
        }
        subscribers[subscriberID] = subscriber

        let clampedFPS = max(1, min(fps, Self.maxAllowedFPS))
        let clampedWidth = max(120, min(maxWidth, Self.maxAllowedWidth))
        let requestedID = displayID.map { CGDirectDisplayID($0) }
        let target = MirrorTarget.requested(displayID: displayID, windowID: windowID)
        let needsNewStream = stream == nil
            || MirrorTarget.needsNewCapture(current: currentTarget, requested: target)
        let needsReconfigure = !needsNewStream
            && (clampedFPS != currentFPS || clampedWidth != currentMaxWidth || pixelFormat != currentPixelFormat)
        currentFPS = clampedFPS
        currentMaxWidth = clampedWidth

        if needsNewStream {
            await teardownStream()
            do {
                if case let .window(id) = target {
                    try await startWindowOrFallBack(
                        windowID: id,
                        fps: clampedFPS,
                        maxWidth: clampedWidth,
                        fallbackDisplayID: requestedID
                    )
                } else {
                    try await startStream(
                        fps: clampedFPS,
                        maxWidth: clampedWidth,
                        preferredDisplayID: requestedID
                    )
                }
                DeckHandLog.app.info("Mirror stream started (\(clampedFPS, privacy: .public) fps, \(clampedWidth, privacy: .public)px, display \(self.currentDisplayID, privacy: .public), window \(self.currentWindow?.windowID ?? 0, privacy: .public))")
            } catch {
                DeckHandLog.app.error("Mirror stream failed to start: \(error.localizedDescription, privacy: .public)")
                subscribers.removeValue(forKey: subscriberID)
                await subscriber.close()
                // Build 19: a sentence, never the raw error; "The Mac is
                // locked." while it is locked.
                let failure = CaptureFailure.reported(for: error)
                try? await handle.send(.mirror(.error(message: failure.message(isMirror: true))))
                return
            }
            for other in subscribers.values { other.markFormatChanged() }
            updateOutputModes()
            // Every remote shares the capture: tell them all what it shows.
            await broadcastDisplayList()
            return
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
        // S17: the Mac's sound stops with the mirror (stop, disconnect,
        // off console).
        MirrorAudioService.shared.stop(subscriberID: subscriberID)
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

    /// S14: a window's capture, sized to its frame. `nil` when the window
    /// has no area.
    private func windowConfiguration(windowWidth: Double, windowHeight: Double, fps: Int, maxWidth: Int) -> SCStreamConfiguration? {
        guard let size = MirrorWindowGeometry.captureSize(
            width: windowWidth,
            height: windowHeight,
            pixelScale: windowPixelScale,
            maxWidth: maxWidth
        ) else { return nil }
        let config = SCStreamConfiguration()
        config.width = size.width
        config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        let format = pixelFormat
        config.pixelFormat = format
        currentPixelFormat = format
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        // The window's content fills the frame (its aspect is the frame's),
        // without the drop shadow, so pointer fractions of the window's
        // frame land on the same pixels.
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.ignoreShadowsSingleWindow = true
        return config
    }

    /// Display mode: captures `preferredDisplayID` (or the main display).
    private func startStream(
        fps: Int,
        maxWidth: Int,
        preferredDisplayID: CGDirectDisplayID?
    ) async throws {
        let display = try await ScreenCaptureService.shared.display(matching: preferredDisplayID)
        currentDisplayID = display.displayID

        let config = configuration(for: display, fps: fps, maxWidth: maxWidth)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        try await runCapture(filter: filter, config: config)
        currentTarget = .display(display.displayID)
        currentWindow = nil
        windowTracker = nil
    }

    /// S14: captures the window, or, when it isn't on screen any more,
    /// falls back to `fallbackDisplayID` and tells the remotes why.
    private func startWindowOrFallBack(
        windowID: UInt32,
        fps: Int,
        maxWidth: Int,
        fallbackDisplayID: CGDirectDisplayID?
    ) async throws {
        if MacLockMonitor.shared.state.isLocked {
            // The gate refuses this start while locked; a lock that came in
            // between still mustn't capture a window.
            try await startStream(fps: fps, maxWidth: maxWidth, preferredDisplayID: fallbackDisplayID)
            await sendWindowEnded(message: MirrorWindowCopy.ended(.locked, appName: "", displayName: await currentDisplayName()))
            return
        }
        if let window = try await ScreenCaptureService.shared.window(matching: windowID),
           window.frame.width >= 1, window.frame.height >= 1 {
            do {
                try await startWindowStream(window, fps: fps, maxWidth: maxWidth)
                return
            } catch {
                DeckHandLog.app.error("Mirror: window \(windowID, privacy: .public) couldn't be captured: \(error.localizedDescription, privacy: .public)")
                try await startStream(fps: fps, maxWidth: maxWidth, preferredDisplayID: Self.homeDisplay(of: window.frame) ?? fallbackDisplayID)
                await sendWindowEnded(message: MirrorWindowCopy.ended(
                    .captureFailed,
                    appName: window.owningApplication?.applicationName ?? "",
                    displayName: await currentDisplayName()
                ))
                return
            }
        }
        try await startStream(fps: fps, maxWidth: maxWidth, preferredDisplayID: fallbackDisplayID)
        await sendWindowEnded(message: MirrorWindowCopy.notFound(displayName: await currentDisplayName()))
    }

    private func startWindowStream(_ window: SCWindow, fps: Int, maxWidth: Int) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // Points of the window's content and pixels per point (macOS 14).
        windowPixelScale = Double(filter.pointPixelScale)
        let frame = window.frame
        guard let config = windowConfiguration(
            windowWidth: Double(frame.width),
            windowHeight: Double(frame.height),
            fps: fps,
            maxWidth: maxWidth
        ) else { throw ScreenCaptureService.CaptureError.windowNotFound }
        try await runCapture(filter: filter, config: config)
        currentDisplayID = Self.homeDisplay(of: frame) ?? CGMainDisplayID()
        currentTarget = .window(window.windowID)
        currentWindow = MirroredWindow(
            windowID: window.windowID,
            title: window.title ?? "",
            appName: window.owningApplication?.applicationName ?? "",
            width: Int(frame.width.rounded()),
            height: Int(frame.height.rounded())
        )
        windowTracker = MirrorWindowTracker(frame: Self.rect(frame), now: Self.uptime())
    }

    /// Builds the frame output and the stream for `filter`, and starts it.
    private func runCapture(filter: SCContentFilter, config: SCStreamConfiguration) async throws {
        frameWidth = config.width
        frameHeight = config.height
        let fps = currentFPS

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

    // MARK: - Window mirror (S14)

    /// Twice a second while a window is mirrored, from the cursor loop.
    private func checkWindow() {
        guard case let .window(windowID) = currentTarget, var tracker = windowTracker, !tracker.hasEnded else { return }
        let event = tracker.observe(MirrorWindowProbe.observe(windowID: windowID), now: Self.uptime())
        windowTracker = tracker
        handleWindowEvent(event)
    }

    private func handleWindowEvent(_ event: MirrorWindowTracker.Event) {
        switch event {
        case .none:
            break
        case let .resize(width, height):
            lifecycle.enqueue { [weak self] in
                await self?.resizeWindowCapture(width: width, height: height)
            }
        case let .ended(reason):
            let appName = currentWindow?.appName ?? ""
            let frame = windowTracker?.frame
            lifecycle.enqueue { [weak self] in
                await self?.fallBackFromWindow(reason: reason, appName: appName, lastFrame: frame)
            }
        }
    }

    /// The window was resized: capture at its new size, in place.
    private func resizeWindowCapture(width: Double, height: Double) async {
        guard let stream, currentTarget?.windowID != nil,
              let config = windowConfiguration(windowWidth: width, windowHeight: height, fps: currentFPS, maxWidth: currentMaxWidth)
        else { return }
        do {
            try await stream.updateConfiguration(config)
        } catch {
            DeckHandLog.app.error("Mirror: window resize not applied: \(error.localizedDescription, privacy: .public)")
            return
        }
        frameWidth = config.width
        frameHeight = config.height
        // A new size makes a new HEVC session, whose first frame is a key frame.
        for subscriber in subscribers.values { subscriber.markFormatChanged() }
        if let window = currentWindow {
            currentWindow = MirroredWindow(
                windowID: window.windowID,
                title: window.title,
                appName: window.appName,
                width: Int(width.rounded()),
                height: Int(height.rounded())
            )
        }
        if let frame = windowTracker?.frame {
            currentDisplayID = Self.homeDisplay(of: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)) ?? currentDisplayID
        }
        await broadcastDisplayList()
    }

    /// The window ended: tell every remote, then mirror its display.
    private func fallBackFromWindow(reason: MirrorWindowTracker.EndReason, appName: String, lastFrame: MirrorRect?) async {
        guard currentTarget?.windowID != nil, !subscribers.isEmpty else { return }
        let home = lastFrame.flatMap {
            Self.homeDisplay(of: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height))
        } ?? currentDisplayID
        DeckHandLog.app.info("Mirror: window mirror ended (\(reason.rawValue, privacy: .public)), back to display \(home, privacy: .public)")
        await teardownStream()
        do {
            try await startStream(fps: currentFPS, maxWidth: currentMaxWidth, preferredDisplayID: home == 0 ? nil : home)
        } catch {
            handleStreamFailure(error)
            return
        }
        for subscriber in subscribers.values { subscriber.markFormatChanged() }
        updateOutputModes()
        await sendWindowEnded(message: MirrorWindowCopy.ended(reason, appName: appName, displayName: await currentDisplayName()))
        await broadcastDisplayList()
    }

    /// `mirror.error` with the display now shown: every remote keeps its
    /// mirror open.
    private func sendWindowEnded(message: String) async {
        let displayID = currentDisplayID
        for subscriber in subscribers.values {
            try? await subscriber.handle.send(.mirror(.error(message: message, fallbackDisplayID: displayID)))
        }
    }

    private func currentDisplayName() async -> String {
        let displays = (try? await ScreenCaptureService.shared.enumerateDisplays()) ?? []
        return displays.first { $0.displayID == currentDisplayID }?.name ?? "the display"
    }

    /// The active display a window frame overlaps most.
    private static func homeDisplay(of frame: CGRect) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        let displays = ids.prefix(Int(count)).map { id in
            (id: UInt32(id), bounds: rect(CGDisplayBounds(id)))
        }
        return MirrorWindowGeometry.homeDisplay(window: rect(frame), displays: displays)
    }

    private static func rect(_ r: CGRect) -> MirrorRect {
        MirrorRect(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.width), height: Double(r.height))
    }

    private static func uptime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    /// Applies a new rate or size to the running capture without
    /// restarting it; restarts if ScreenCaptureKit refuses.
    private func reconfigureStream() async {
        guard let stream else { return }
        do {
            let config: SCStreamConfiguration
            if currentTarget?.windowID != nil, let frame = windowTracker?.capturedSize,
               let windowConfig = windowConfiguration(windowWidth: frame.width, windowHeight: frame.height, fps: currentFPS, maxWidth: currentMaxWidth) {
                config = windowConfig
            } else {
                let display = try await ScreenCaptureService.shared.display(matching: currentDisplayID)
                config = configuration(for: display, fps: currentFPS, maxWidth: currentMaxWidth)
            }
            try await stream.updateConfiguration(config)
            frameWidth = config.width
            frameHeight = config.height
            output?.setFrameRate(currentFPS)
            for subscriber in subscribers.values { subscriber.markFormatChanged() }
            DeckHandLog.app.info("Mirror stream reconfigured (\(self.currentFPS, privacy: .public) fps, \(self.currentMaxWidth, privacy: .public)px)")
        } catch {
            DeckHandLog.app.error("Mirror reconfigure failed, restarting: \(error.localizedDescription, privacy: .public)")
            let windowID = currentTarget?.windowID
            await teardownStream()
            do {
                if let windowID {
                    try await startWindowOrFallBack(windowID: windowID, fps: currentFPS, maxWidth: currentMaxWidth, fallbackDisplayID: currentDisplayID)
                } else {
                    try await startStream(fps: currentFPS, maxWidth: currentMaxWidth, preferredDisplayID: currentDisplayID)
                }
                for subscriber in subscribers.values { subscriber.markFormatChanged() }
                if windowID != nil { await broadcastDisplayList() }
            } catch {
                handleStreamFailure(error)
            }
        }
    }

    private func teardownStream() async {
        stopCursorLoop()
        currentTarget = nil
        currentWindow = nil
        windowTracker = nil
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
        if currentTarget?.windowID != nil {
            // A window capture doesn't depend on a display; only its home
            // (the fallback) may have moved.
            if let frame = windowTracker?.frame {
                currentDisplayID = Self.homeDisplay(of: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)) ?? CGMainDisplayID()
            }
        } else if !stillPresent {
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
        await broadcastDisplayList()
    }

    private func sendDisplayList(to handle: LoomConnectionHandle) async {
        let displays = (try? await ScreenCaptureService.shared.enumerateDisplays()) ?? []
        try? await handle.send(.mirror(.displayList(
            displays: displays,
            selectedDisplayID: currentDisplayID,
            window: currentWindow
        )))
    }

    private func broadcastDisplayList() async {
        for subscriber in subscribers.values {
            await sendDisplayList(to: subscriber.handle)
        }
    }

    /// Why a running stream stopped, for the remote: Screen Recording
    /// turned off, or "the live screen stopped".
    private static func stoppedFailure(for error: Error) -> CaptureFailure {
        CaptureFailure.cause(of: error) == .screenRecordingDenied ? .screenRecordingDenied : .streamStopped
    }

    /// Called by `MirrorFrameOutput` when ScreenCaptureKit reports the
    /// stream died (display unplugged, TCC revoked mid-stream, …).
    fileprivate func handleStreamFailure(_ error: Error, from source: MirrorFrameOutput? = nil) {
        // A stream that has since been replaced reports nothing.
        if let source, source !== output { return }
        if source != nil, currentTarget?.windowID != nil, windowTracker?.hasEnded == false {
            // S14: a window capture stops when its window goes away. Fall
            // back to its display instead of ending every mirror.
            DeckHandLog.app.info("Mirror: window capture stopped: \(error.localizedDescription, privacy: .public)")
            let windowID = currentTarget?.windowID ?? 0
            let reason: MirrorWindowTracker.EndReason = MirrorWindowProbe.listing(windowID: windowID) == nil ? .closed : .captureFailed
            if var tracker = windowTracker {
                let event = tracker.end(reason)
                windowTracker = tracker
                handleWindowEvent(event)
            }
            return
        }
        DeckHandLog.app.error("Mirror stream error: \(error.localizedDescription, privacy: .public)")
        let dropped = Array(subscribers.values)
        subscribers.removeAll()
        lastHostStats.removeAll()
        stopCursorLoop()
        stream = nil
        output = nil
        currentDisplayID = 0
        currentTarget = nil
        currentWindow = nil
        windowTracker = nil
        let failure = CaptureFailure.reported(for: nil, fallback: Self.stoppedFailure(for: error))
        for subscriber in dropped {
            Task {
                await subscriber.close()
                try? await subscriber.handle.send(.mirror(.error(message: failure.message(isMirror: true))))
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
                if tick % Self.windowEveryTicks == 0 {
                    self.checkWindow()
                }
                self.checkLockForWindow()
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

    /// S14: a window capture draws the window over the lock screen; a lock
    /// ends it at once (read every tick, it's a stored property).
    private func checkLockForWindow() {
        guard currentTarget?.windowID != nil, MacLockMonitor.shared.state.isLocked,
              var tracker = windowTracker, !tracker.hasEnded else { return }
        let event = tracker.end(.locked)
        windowTracker = tracker
        // Stop sending its frames now, before the fallback has run.
        output?.setModes(jpeg: false, hevc: false)
        handleWindowEvent(event)
    }

    private func sendCursor(shape: MirrorCursorShape?) {
        let state: MirrorCursorState?
        if currentTarget?.windowID != nil {
            // S14: fractions of the window; "on the mirrored display" means
            // over the window.
            guard let frame = windowTracker?.frame, windowTracker?.hasEnded == false else { return }
            state = cursorSampler.state(in: frame, shapeID: shape?.id ?? 0)
        } else {
            guard currentDisplayID != 0 else { return }
            state = cursorSampler.state(mirroredDisplayID: currentDisplayID, shapeID: shape?.id ?? 0)
        }
        guard let state else { return }
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
            stats.audio = MirrorAudioService.shared.takeStats(subscriberID: subscriber.id, elapsed: seconds)
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
        Task { @MainActor [weak self] in
            MirrorStreamService.shared.handleStreamFailure(error, from: self)
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
