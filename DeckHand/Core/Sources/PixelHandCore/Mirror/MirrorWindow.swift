//
//  MirrorWindow.swift
//  PixelHandCore
//
//  S14: the live mirror shows one window instead of a display.
//
//  - `MirrorTarget` and `MirrorTarget.needsNewCapture`: what the Mac
//    captures and when a `mirror.start` has to replace the capture.
//  - `MirrorWindowGeometry`: the capture size that follows the window's
//    frame, the pointer mapped into the window, and the display a window
//    falls back to.
//  - `MirrorWindowTracker` (Mac): watches the window twice a second;
//    resizes (debounced, so a live drag doesn't restart the encoder at
//    every step), and the end of the window (closed, minimised, gone off
//    screen, Mac locked), after which the Mac sends `mirror.error` with a
//    `fallbackDisplayID` and mirrors that display.
//  - `MirrorWindowSelection` (remote): which window the remote asked for
//    and which one the Mac says it shows.
//
//  Behaviour re-implemented from Sill's documented single-window
//  streaming (no code copied).
//

import Foundation

// MARK: - Target

/// What the Mac's mirror capture shows.
public enum MirrorTarget: Equatable, Sendable {
    /// A display; `nil` asks for the main display.
    case display(UInt32?)
    /// One window, by `CGWindowID`.
    case window(UInt32)

    /// The target a `mirror.start` asks for. A window wins over a display.
    public static func requested(displayID: UInt32?, windowID: UInt32?) -> MirrorTarget {
        if let windowID, windowID != 0 { return .window(windowID) }
        return .display(displayID)
    }

    public var windowID: UInt32? {
        if case let .window(id) = self { return id }
        return nil
    }

    /// Whether a start asking for `requested` must replace the capture now
    /// showing `current` (`nil`: nothing is captured). A display start with
    /// no display (`nil`) keeps whatever display is shown, but leaves a
    /// window.
    public static func needsNewCapture(current: MirrorTarget?, requested: MirrorTarget) -> Bool {
        guard let current else { return true }
        switch (current, requested) {
        case let (.window(a), .window(b)):
            return a != b
        case (.window, .display):
            return true
        case (.display, .window):
            return true
        case (.display, .display(nil)):
            return false
        case let (.display(a), .display(b?)):
            return a != b
        }
    }
}

// MARK: - Geometry

public enum MirrorWindowGeometry {
    /// The tallest frame a window mirror sends, whatever its width.
    public static let maxHeight = 1920
    /// The smallest side a window frame is captured at.
    public static let minSide = 32
    /// A frame size change smaller than this (points) isn't a resize: the
    /// window server reports fractional sizes during animations.
    public static let resizeThreshold = 2.0

    /// The capture size for a window of `width` × `height` points drawn at
    /// `pixelScale` pixels a point: as wide as `maxWidth` allows but never
    /// wider than the window's own pixels, at the window's aspect, height
    /// capped at `maxHeight`, both sides even (HEVC needs it). `nil` for a
    /// window with no area.
    public static func captureSize(
        width: Double,
        height: Double,
        pixelScale: Double,
        maxWidth: Int
    ) -> (width: Int, height: Int)? {
        guard width.isFinite, height.isFinite, width >= 1, height >= 1, maxWidth > 0 else { return nil }
        let scale = pixelScale.isFinite && pixelScale > 0 ? pixelScale : 1
        let aspect = height / width
        var outWidth = min(Double(maxWidth), width * scale)
        var outHeight = outWidth * aspect
        if outHeight > Double(maxHeight) {
            outHeight = Double(maxHeight)
            outWidth = outHeight / aspect
        }
        let w = max(minSide, MirrorVideoBitrate.evenDimension(Int(outWidth.rounded())))
        let h = max(minSide, MirrorVideoBitrate.evenDimension(Int(outHeight.rounded())))
        return (w, h)
    }

    /// Whether the window's size moved far enough from `old` to resize the
    /// capture.
    public static func sizeChanged(from old: MirrorRect, to new: MirrorRect) -> Bool {
        abs(old.width - new.width) >= resizeThreshold || abs(old.height - new.height) >= resizeThreshold
    }

    /// The pointer at global `x`, `y` (points, top-left origin, the space
    /// of `CGDisplayBounds` and `SCWindow.frame`) as fractions of the
    /// window, and whether it is over the window.
    public static func cursor(x: Double, y: Double, window: MirrorRect) -> (x: Double, y: Double, inside: Bool) {
        MirrorCursorGeometry.normalized(x: x, y: y, in: window)
    }

    /// The display a window sits on: the one it overlaps most; ties go to
    /// the first listed. `nil` when it overlaps none.
    public static func homeDisplay(window: MirrorRect, displays: [(id: UInt32, bounds: MirrorRect)]) -> UInt32? {
        var best: (id: UInt32, area: Double)?
        for display in displays {
            let area = overlap(window, display.bounds)
            guard area > 0 else { continue }
            if best == nil || area > best!.area {
                best = (display.id, area)
            }
        }
        return best?.id
    }

    static func overlap(_ a: MirrorRect, _ b: MirrorRect) -> Double {
        let w = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let h = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        return w > 0 && h > 0 ? w * h : 0
    }
}

// MARK: - Tracker (Mac)

/// Watches a mirrored window from periodic observations: when to resize
/// the capture and when the window has ended.
public struct MirrorWindowTracker: Sendable, Equatable {
    /// How often the Mac should look (seconds).
    public static let pollInterval = 0.5
    /// Resizes are applied at most this often (seconds); the last size of a
    /// live drag is applied once the drag pauses or ends.
    public static let resizeInterval = 0.5
    /// Missing from the window list this many looks in a row: closed. (One
    /// miss can be the window server between two lists.)
    public static let missingLooks = 2
    /// Off screen this long with no way to tell why: treated as gone.
    public static let hiddenGrace = 3.0

    /// What one look at the window found.
    public enum Observation: Equatable, Sendable {
        /// Not in the window list: closed (or its app quit).
        case missing
        /// On screen, at `frame` (global points, top-left origin).
        case onScreen(frame: MirrorRect)
        /// In the list but not on screen. `minimized`: the Mac could tell
        /// it was minimised (`true`), or that it wasn't (`false`: on
        /// another Space, or its app hidden: the capture keeps the last
        /// picture and resumes), or couldn't tell (`nil`).
        case offScreen(frame: MirrorRect, minimized: Bool?)
    }

    /// Why a window mirror ended.
    public enum EndReason: String, Sendable, Equatable, CaseIterable {
        case closed
        case minimized
        /// Off screen for `hiddenGrace` seconds and the Mac couldn't tell why.
        case hidden
        /// The Mac locked: a window capture would show the window over the
        /// lock screen (the locked-Mac gate refuses window captures too).
        case locked
        /// ScreenCaptureKit couldn't capture it.
        case captureFailed
    }

    public enum Event: Equatable, Sendable {
        case none
        /// Capture at this window size now (points).
        case resize(width: Double, height: Double)
        /// Fall back to the window's display; nothing more will be reported.
        case ended(EndReason)
    }

    /// The window's latest frame, for mapping the pointer.
    public private(set) var frame: MirrorRect
    /// The size the capture was last sized for.
    public private(set) var capturedSize: MirrorRect
    public private(set) var hasEnded = false
    private var missingCount = 0
    private var offScreenSince: Double?
    private var lastResizeAt: Double

    public init(frame: MirrorRect, now: Double) {
        self.frame = frame
        self.capturedSize = frame
        self.lastResizeAt = now
    }

    /// Feeds one look at the window, at time `now` (seconds).
    public mutating func observe(_ observation: Observation, now: Double) -> Event {
        guard !hasEnded else { return .none }
        switch observation {
        case .missing:
            missingCount += 1
            return missingCount >= Self.missingLooks ? end(.closed) : .none

        case let .offScreen(frame, minimized):
            missingCount = 0
            if valid(frame) { self.frame = frame }
            switch minimized {
            case true?:
                return end(.minimized)
            case false?:
                offScreenSince = nil
                return .none
            case nil:
                let since = offScreenSince ?? now
                offScreenSince = since
                return now - since >= Self.hiddenGrace ? end(.hidden) : .none
            }

        case let .onScreen(frame):
            missingCount = 0
            offScreenSince = nil
            guard valid(frame) else { return .none }
            self.frame = frame
            return resizeIfDue(now: now)
        }
    }

    /// The Mac locked, or the capture failed: end now.
    public mutating func end(_ reason: EndReason) -> Event {
        guard !hasEnded else { return .none }
        hasEnded = true
        return .ended(reason)
    }

    private mutating func resizeIfDue(now: Double) -> Event {
        guard MirrorWindowGeometry.sizeChanged(from: capturedSize, to: frame),
              now - lastResizeAt >= Self.resizeInterval else { return .none }
        capturedSize = frame
        lastResizeAt = now
        return .resize(width: frame.width, height: frame.height)
    }

    private func valid(_ frame: MirrorRect) -> Bool {
        frame.width.isFinite && frame.height.isFinite && frame.width >= 1 && frame.height >= 1
            && frame.x.isFinite && frame.y.isFinite
    }
}

// MARK: - Copy

public enum MirrorWindowCopy {
    /// What the remote shows when a window mirror ends and the mirror
    /// falls back to `displayName`.
    public static func ended(_ reason: MirrorWindowTracker.EndReason, appName: String, displayName: String) -> String {
        let window = appName.isEmpty ? "The window" : "The \(appName) window"
        let tail = "Showing \(displayName) instead."
        switch reason {
        case .closed: return "\(window) closed. \(tail)"
        case .minimized: return "\(window) was minimised. \(tail)"
        case .hidden: return "\(window) is no longer on screen. \(tail)"
        case .locked: return "The Mac is locked, so the window can't be mirrored. \(tail)"
        case .captureFailed: return "\(window) couldn't be captured. \(tail)"
        }
    }

    /// A start asked for a window the Mac doesn't list (closed since the
    /// window list was read).
    public static func notFound(displayName: String) -> String {
        "That window isn't open any more. Showing \(displayName) instead."
    }
}

// MARK: - Selection (remote)

/// The remote's side: the window it asked the Mac to mirror and the one
/// the Mac confirmed in `mirror.displayList`.
public struct MirrorWindowSelection: Equatable, Sendable {
    /// Sent in every `mirror.start` (re-negotiations included) until the
    /// remote picks a display or the Mac falls back.
    public private(set) var requestedWindowID: UInt32?
    /// What the Mac says the stream shows.
    public private(set) var window: MirroredWindow?

    public init() {}

    /// The mirror is showing, or about to show, a window.
    public var isActive: Bool { requestedWindowID != nil || window != nil }

    public mutating func selectWindow(_ windowID: UInt32) {
        requestedWindowID = windowID
        if window?.windowID != windowID { window = nil }
    }

    /// The user picked a display.
    public mutating func selectDisplay() {
        requestedWindowID = nil
        window = nil
    }

    /// `mirror.displayList`'s `window`: what the shared capture shows now
    /// (another remote may have picked it; the latest start wins, as for
    /// displays). The request is left alone: a list without a window while
    /// one is requested answers an earlier start or a screen change, and
    /// the request stands until the Mac falls back with `mirror.error`.
    public mutating func hostReported(window: MirroredWindow?) {
        self.window = window
    }

    /// `mirror.error` with a `fallbackDisplayID`: the window ended.
    public mutating func windowEnded() {
        requestedWindowID = nil
        window = nil
    }

    /// The pointer's sprite scale reference: the window's width in points
    /// while one is shown, else `displayWidth`.
    public func pointWidth(displayWidth: Double) -> Double {
        guard let window, window.width > 0 else { return displayWidth }
        return Double(window.width)
    }
}
