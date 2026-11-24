//
//  MirrorPictureInPicture.swift
//  PixelHandCore
//
//  UX-041, the live mirror in Picture in Picture on iPhone and iPad. The
//  rules the remote's PiP code follows, kept here so they are tested:
//
//  - `MirrorPiPState`: whether PiP may start (by itself when the app
//    leaves, or from the mirror's PiP button), whether it holds the
//    session (keep-alive and heartbeat keep running in the background),
//    pause = freeze (the Mac drops to `pausedFPS` keep-alive frames), and
//    when it must close (10 minutes paused, the mirror stopping, the
//    session ending, the device locking, Pro ending).
//  - `MirrorPiPFrameMath`: the pointer drawn into the frames (no app UI
//    draws over PiP), sized for the PiP window rather than the Mac, and
//    the size a JPEG frame is redrawn at.
//  - `MirrorPiPPacer`: how often a composited frame is made: the stream's
//    rate while PiP shows, a slow warm-up rate while it could start (so
//    the PiP layer always has a picture to open with), nothing while
//    paused.
//  - `MirrorPiPDecodeHealth`: the PiP decoder's own recovery. A broken
//    decode waits for the next key frame; repeated failures give up on
//    compositing and show the stream as it is, without the pointer.
//
//  No protocol change: pausing re-sends `mirror.start` with a lower `fps`.
//

import Foundation

// MARK: - State

/// What PiP is doing and what it needs from the rest of the session.
public struct MirrorPiPState: Equatable, Sendable {
    /// Seconds PiP may stay paused before it closes.
    public static let pausedTimeout: Double = 600
    /// Frames a second the Mac is asked for while PiP is paused: enough to
    /// keep the stream and its encoder alive, little enough to cost
    /// nothing.
    public static let pausedFPS = 1

    /// Why PiP closes by itself.
    public enum CloseReason: String, Equatable, Sendable {
        case pausedTooLong
        case mirrorStopped
        case sessionEnded
        case deviceLocked
        case notEntitled
    }

    /// What changed and has to be carried out.
    public struct Effects: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// `holdsSession` changed: re-apply the network keep-alive.
        public static let sessionHoldChanged = Effects(rawValue: 1 << 0)
        /// The frame rate to ask the Mac for changed: re-send `mirror.start`.
        public static let renegotiate = Effects(rawValue: 1 << 1)
        /// Close PiP (`closeReason` says why).
        public static let close = Effects(rawValue: 1 << 2)
        /// Whether the Mac's sound should play changed.
        public static let audioChanged = Effects(rawValue: 1 << 3)
    }

    /// Settings › Live mirror › "Keep watching in Picture in Picture".
    public private(set) var autoStartEnabled = false
    /// Pixel Hand Pro (the mirror is Pro, so PiP is).
    public private(set) var entitled = false
    /// The mirror is open.
    public private(set) var mirrorActive = false
    /// PiP is on screen (from its controller's start/stop callbacks).
    public private(set) var isActive = false
    /// PiP's play/pause: paused holds the last picture.
    public private(set) var isPaused = false
    /// When the pause began (any monotonic clock, seconds).
    public private(set) var pausedSince: Double?
    /// The last reason PiP closed by itself.
    public private(set) var closeReason: CloseReason?

    public init() {}

    // MARK: Derived

    /// PiP may start at all: the mirror is open and Pro allows it.
    public var isAvailable: Bool { entitled && mirrorActive }

    /// Leaving the app while the mirror is open starts PiP.
    public var canStartAutomatically: Bool { isAvailable && autoStartEnabled }

    /// The connection, its keep-alive tick and heartbeat keep running in
    /// the background.
    public var holdsSession: Bool { isActive }

    /// PiP shows a live (not frozen) picture.
    public var isLive: Bool { isActive && !isPaused }

    /// Whether the Mac's sound may keep playing with the app in the
    /// background: only while PiP shows a live picture.
    public var allowsBackgroundAudio: Bool { isLive }

    /// The frame rate to ask the Mac for, given what the settings ask.
    public func requestedFPS(settingsFPS: Int) -> Int {
        isActive && isPaused ? Self.pausedFPS : settingsFPS
    }

    // MARK: Inputs

    public mutating func setAutoStartEnabled(_ enabled: Bool) {
        autoStartEnabled = enabled
    }

    public mutating func setEntitled(_ value: Bool) -> Effects {
        entitled = value
        return value ? [] : closeIfActive(.notEntitled)
    }

    public mutating func setMirrorActive(_ value: Bool) -> Effects {
        mirrorActive = value
        return value ? [] : closeIfActive(.mirrorStopped)
    }

    /// The session with the Mac ended.
    public mutating func sessionEnded() -> Effects {
        mirrorActive = false
        return closeIfActive(.sessionEnded)
    }

    /// The device is locking (protected data about to go away).
    public mutating func deviceLocked() -> Effects {
        closeIfActive(.deviceLocked)
    }

    /// PiP appeared.
    public mutating func didStart() -> Effects {
        guard !isActive else { return [] }
        isActive = true
        isPaused = false
        pausedSince = nil
        closeReason = nil
        return [.sessionHoldChanged, .audioChanged]
    }

    /// PiP went away (closed, or back in the app).
    public mutating func didStop() -> Effects {
        guard isActive else { return [] }
        let wasPaused = isPaused
        isActive = false
        isPaused = false
        pausedSince = nil
        var effects: Effects = [.sessionHoldChanged, .audioChanged]
        if wasPaused { effects.insert(.renegotiate) }
        return effects
    }

    /// PiP's play/pause button.
    public mutating func setPaused(_ paused: Bool, now: Double) -> Effects {
        guard isActive, paused != isPaused else { return [] }
        isPaused = paused
        pausedSince = paused ? now : nil
        return [.renegotiate, .audioChanged]
    }

    /// A clock tick: closes PiP after `pausedTimeout` paused.
    public mutating func tick(now: Double) -> Effects {
        guard isActive, isPaused, let pausedSince, now - pausedSince >= Self.pausedTimeout else { return [] }
        return closeIfActive(.pausedTooLong)
    }

    private mutating func closeIfActive(_ reason: CloseReason) -> Effects {
        guard isActive else { return [] }
        closeReason = reason
        return [.close]
    }
}

// MARK: - Frame maths

public enum MirrorPiPFrameMath {
    /// PiP windows are small: the pointer is never drawn smaller than
    /// this, relative to its size on the Mac, as the PiP window shows it.
    public static let minimumSpriteScale = 0.75
    /// The PiP window's width in points until the system says.
    public static let defaultWindowPointWidth = 320.0
    /// Largest width a JPEG frame is redrawn at for PiP.
    public static let maxJPEGWidth = 1_920

    /// Where to draw the pointer in a frame of `frameWidth` × `frameHeight`
    /// pixels, so that in a PiP window `windowPointWidth` points wide it
    /// looks the size the mirror would draw it at. `nil` when the pointer
    /// isn't on the picture, the sizes are unusable, or it falls entirely
    /// outside the frame.
    public static func cursorRect(
        state: MirrorCursorState,
        shape: MirrorCursorShape,
        displayPointWidth: Double,
        frameWidth: Int,
        frameHeight: Int,
        windowPointWidth: Double
    ) -> MirrorRect? {
        guard state.isVisibleInMirror, frameWidth > 0, frameHeight > 0 else { return nil }
        let window = windowPointWidth > 0 ? windowPointWidth : defaultWindowPointWidth
        let width = Double(frameWidth)
        let height = Double(frameHeight)
        // The pointer's scale on screen, in PiP points per Mac point.
        let onScreen = max(
            MirrorCursorGeometry.spriteScale(displayPointWidth: displayPointWidth, viewWidth: window),
            minimumSpriteScale
        )
        // Frame pixels per PiP point.
        let pixelsPerPoint = width / window
        let scale = onScreen * pixelsPerPoint
        let rect = MirrorRect(
            x: state.x * width - shape.hotSpotX * scale,
            y: state.y * height - shape.hotSpotY * scale,
            width: shape.width * scale,
            height: shape.height * scale
        )
        guard rect.width > 0, rect.height > 0,
              rect.x < width, rect.y < height,
              rect.x + rect.width > 0, rect.y + rect.height > 0 else { return nil }
        return rect
    }

    /// The same rectangle in a bottom-left-origin context (Core Graphics
    /// drawing into the pixel buffer).
    public static func flipped(_ rect: MirrorRect, frameHeight: Int) -> MirrorRect {
        MirrorRect(x: rect.x, y: Double(frameHeight) - rect.y - rect.height, width: rect.width, height: rect.height)
    }

    /// The pixel size a JPEG frame of `width` × `height` is redrawn at for
    /// PiP: no wider than `maxJPEGWidth`, aspect kept, both even and at
    /// least 2. `nil` for an empty image.
    public static func jpegBufferSize(width: Double, height: Double) -> (width: Int, height: Int)? {
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
        let scale = min(1, Double(maxJPEGWidth) / width)
        func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }
        return (even(width * scale), even(height * scale))
    }

    /// What a composited frame showed of the pointer, to tell whether a
    /// pointer update needs a new frame. Whole pixels: sub-pixel moves
    /// don't.
    public struct CursorStamp: Equatable, Sendable {
        public var shapeID: UInt32
        public var x: Int
        public var y: Int
        public var width: Int

        public init(shapeID: UInt32, rect: MirrorRect) {
            self.shapeID = shapeID
            x = Int(rect.x.rounded())
            y = Int(rect.y.rounded())
            width = Int(rect.width.rounded())
        }
    }
}

// MARK: - Pacing

/// How often PiP's layer gets a new composited frame. A frame is made when
/// there is something new (a picture or a pointer move) and the last one
/// is at least the interval old; a change inside the interval is made when
/// it ends, so the last pointer position always lands.
public struct MirrorPiPPacer: Equatable, Sendable {
    /// While PiP could start but isn't showing: two frames a second keep
    /// its layer current for the moment it opens.
    public static let warmInterval = 0.5
    /// Never more often than this while showing.
    public static let maxRate = 30.0

    public enum Mode: Equatable, Sendable {
        /// PiP can't start: nothing is made.
        case off
        /// PiP could start: `warmInterval`.
        case warm
        /// PiP shows the stream at `fps` (capped at `maxRate`).
        case live(fps: Int)
        /// PiP is paused: the picture is held.
        case frozen
    }

    public enum Decision: Equatable, Sendable {
        case none
        case now
        /// Make it after this many seconds (once; later changes ride along).
        case after(Double)
    }

    public private(set) var mode: Mode = .off
    public private(set) var lastFrameAt: Double?
    public private(set) var pending = false

    public init() {}

    public static func mode(for state: MirrorPiPState, streamFPS: Int) -> Mode {
        guard state.isAvailable || state.isActive else { return .off }
        if state.isActive {
            return state.isPaused ? .frozen : .live(fps: streamFPS)
        }
        return .warm
    }

    public var interval: Double? {
        switch mode {
        case .off, .frozen: return nil
        case .warm: return Self.warmInterval
        case let .live(fps): return 1 / min(max(Double(fps), 1), Self.maxRate)
        }
    }

    /// Switches mode. Going live makes a frame at once.
    public mutating func setMode(_ new: Mode) -> Decision {
        guard new != mode else { return .none }
        mode = new
        guard interval != nil else {
            pending = false
            return .none
        }
        if case .live = new {
            lastFrameAt = nil
            return .now
        }
        return .none
    }

    /// Something new to show arrived.
    public mutating func somethingChanged(now: Double) -> Decision {
        guard let interval else { return .none }
        if let lastFrameAt, now - lastFrameAt < interval {
            guard !pending else { return .none }
            pending = true
            return .after(interval - (now - lastFrameAt))
        }
        return .now
    }

    /// A frame was made.
    public mutating func frameMade(now: Double) {
        lastFrameAt = now
        pending = false
    }

    /// The `.after` delay ended: make the frame if it's still wanted.
    public mutating func deferredFire(now: Double) -> Bool {
        guard pending, interval != nil else {
            pending = false
            return false
        }
        return true
    }
}

// MARK: - Decoder health

/// The PiP decoder's recovery. After a failure, only a key frame is
/// decoded (and one is asked for); `maxConsecutiveFailures` failures in a
/// row switch PiP to passthrough: the compressed stream goes straight to
/// PiP's layer, without the pointer, for the rest of the mirror.
public struct MirrorPiPDecodeHealth: Equatable, Sendable {
    public static let maxConsecutiveFailures = 3

    public enum Verdict: Equatable, Sendable {
        /// Decode this frame.
        case decode
        /// Skip it: a delta while waiting for a key frame.
        case skip
        /// Hand it to PiP's layer as it is.
        case passthrough
    }

    public private(set) var waitingForKeyFrame = true
    public private(set) var consecutiveFailures = 0
    public private(set) var isPassthrough = false

    public init() {}

    public func verdict(isKeyFrame: Bool) -> Verdict {
        if isPassthrough { return .passthrough }
        if waitingForKeyFrame && !isKeyFrame { return .skip }
        return .decode
    }

    public mutating func decoded(isKeyFrame: Bool) {
        consecutiveFailures = 0
        if isKeyFrame { waitingForKeyFrame = false }
    }

    /// A frame failed to decode. Returns `true` when a key frame should be
    /// asked for (not in passthrough, which the inline watchdog covers).
    public mutating func failed() -> Bool {
        guard !isPassthrough else { return false }
        consecutiveFailures += 1
        waitingForKeyFrame = true
        if consecutiveFailures >= Self.maxConsecutiveFailures {
            isPassthrough = true
        }
        return true
    }

    /// A new stream (mirror restarted, codec changed): start over.
    public mutating func reset() {
        self = MirrorPiPDecodeHealth()
    }
}
