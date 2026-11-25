//
//  PicturePointer.swift
//  PixelHandCore – Mirror
//
//  OR-16, pointer control on the mirror picture. In the screen-only
//  arrangement (the picture full size, no trackpad under it) a toolbar
//  toggle makes the picture work as a trackpad. This file holds the parts
//  that can be tested without UIKit:
//
//  - `PictureZoom`: the picture's pinch zoom and pan, as one transform
//    (scale around the view's centre, then offset), with the inverse, the
//    limits that keep the picture covering the view, anchor-preserving
//    zoom, and the pan that keeps the Mac's pointer in view while zoomed.
//  - `PicturePointerMapping`: a finger's movement on the picture to the
//    pointer movement sent to the Mac. Relative, like the Pointer surface
//    (the same sensitivity and the Mac's acceleration apply after it),
//    divided by the zoom so a zoomed picture gives finer control. Pan never
//    changes it.
//  - `PicturePointerMemory`: on or off per Mac. Off the first time the
//    screen-only arrangement opens for a Mac, then the last choice
//    (owner answer 1, `DECISIONS.md` 2026-11-25).
//
//  Gesture arbitration (pinch vs two-finger scroll vs pan) is
//  `TwoFingerArbiter` in Input.
//

import Foundation

// MARK: - Frame

/// Where the picture sits in its view: aspect-fit and centred, as the
/// mirror pane draws it. Points.
public struct PictureFrame: Equatable, Sendable {
    public var viewWidth: Double
    public var viewHeight: Double
    public var pictureWidth: Double
    public var pictureHeight: Double

    public init(viewWidth: Double, viewHeight: Double, pictureWidth: Double, pictureHeight: Double) {
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
        self.pictureWidth = pictureWidth
        self.pictureHeight = pictureHeight
    }

    /// The picture at `aspect` (width / height) fitted into the view.
    public static func fitted(viewWidth: Double, viewHeight: Double, aspect: Double) -> PictureFrame {
        let safeAspect = aspect > 0 ? aspect : 16.0 / 10.0
        guard viewWidth > 0, viewHeight > 0 else {
            return PictureFrame(viewWidth: max(viewWidth, 0), viewHeight: max(viewHeight, 0), pictureWidth: 0, pictureHeight: 0)
        }
        let byWidth = viewWidth / safeAspect
        if byWidth <= viewHeight {
            return PictureFrame(viewWidth: viewWidth, viewHeight: viewHeight, pictureWidth: viewWidth, pictureHeight: byWidth)
        }
        return PictureFrame(viewWidth: viewWidth, viewHeight: viewHeight, pictureWidth: viewHeight * safeAspect, pictureHeight: viewHeight)
    }

    public var centerX: Double { viewWidth / 2 }
    public var centerY: Double { viewHeight / 2 }
    public var pictureMinX: Double { (viewWidth - pictureWidth) / 2 }
    public var pictureMinY: Double { (viewHeight - pictureHeight) / 2 }

    /// A point on the Mac's display (0…1 from the top-leading corner) in
    /// the unzoomed view.
    public func point(normalizedX x: Double, normalizedY y: Double) -> TouchPoint {
        TouchPoint(x: pictureMinX + x * pictureWidth, y: pictureMinY + y * pictureHeight)
    }
}

// MARK: - Zoom and pan

/// The picture's zoom and pan: `screen = centre + (content − centre) × scale + offset`.
public struct PictureZoom: Equatable, Sendable {
    public static let minimumScale: Double = 1
    public static let maximumScale: Double = 4
    /// How close (points) the pointer may come to the view's edge before a
    /// zoomed picture pans to keep it in view.
    public static let followMargin: Double = 32

    public private(set) var scale: Double
    public private(set) var offsetX: Double
    public private(set) var offsetY: Double

    public init(scale: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.scale = min(max(scale, Self.minimumScale), Self.maximumScale)
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public static let identity = PictureZoom()

    public var isZoomed: Bool { scale > 1.001 }

    /// An unzoomed view point to where it shows now.
    public func toScreen(_ point: TouchPoint, in frame: PictureFrame) -> TouchPoint {
        TouchPoint(
            x: frame.centerX + (point.x - frame.centerX) * scale + offsetX,
            y: frame.centerY + (point.y - frame.centerY) * scale + offsetY
        )
    }

    /// Where a point on screen is in the unzoomed view.
    public func toContent(_ point: TouchPoint, in frame: PictureFrame) -> TouchPoint {
        TouchPoint(
            x: frame.centerX + (point.x - frame.centerX - offsetX) / scale,
            y: frame.centerY + (point.y - frame.centerY - offsetY) / scale
        )
    }

    /// The Mac's pointer (0…1 on the mirrored display) on screen.
    public func pointerOnScreen(normalizedX x: Double, normalizedY y: Double, in frame: PictureFrame) -> TouchPoint {
        toScreen(frame.point(normalizedX: x, normalizedY: y), in: frame)
    }

    /// Largest offset on each axis that still keeps the zoomed picture over
    /// the whole view (or centred, on an axis where it is smaller).
    public func offsetLimits(in frame: PictureFrame) -> (x: Double, y: Double) {
        (
            max(0, (frame.pictureWidth * scale - frame.viewWidth) / 2),
            max(0, (frame.pictureHeight * scale - frame.viewHeight) / 2)
        )
    }

    /// Zooms by `factor` keeping the content under `anchor` (screen point)
    /// where it is, within the scale limits, then clamps the offset.
    public mutating func zoom(by factor: Double, anchor: TouchPoint, in frame: PictureFrame) {
        guard factor.isFinite, factor > 0 else { return }
        let content = toContent(anchor, in: frame)
        let next = min(max(scale * factor, Self.minimumScale), Self.maximumScale)
        scale = next
        offsetX = anchor.x - frame.centerX - (content.x - frame.centerX) * next
        offsetY = anchor.y - frame.centerY - (content.y - frame.centerY) * next
        clamp(in: frame)
    }

    /// Moves the zoomed picture with the fingers.
    public mutating func pan(dx: Double, dy: Double, in frame: PictureFrame) {
        guard dx.isFinite, dy.isFinite else { return }
        offsetX += dx
        offsetY += dy
        clamp(in: frame)
    }

    /// Keeps the picture covering the view; back to fit at scale 1.
    public mutating func clamp(in frame: PictureFrame) {
        if !isZoomed {
            self = .identity
            return
        }
        let limits = offsetLimits(in: frame)
        offsetX = min(max(offsetX, -limits.x), limits.x)
        offsetY = min(max(offsetY, -limits.y), limits.y)
    }

    /// Pans the least needed to bring `screenPoint` (the Mac's pointer)
    /// inside the view, `followMargin` from its edges. Unzoomed, nothing.
    public mutating func follow(_ screenPoint: TouchPoint, in frame: PictureFrame) {
        guard isZoomed else { return }
        let margin = min(Self.followMargin, frame.viewWidth / 4, frame.viewHeight / 4)
        var dx = 0.0
        var dy = 0.0
        if screenPoint.x < margin { dx = margin - screenPoint.x }
        if screenPoint.x > frame.viewWidth - margin { dx = frame.viewWidth - margin - screenPoint.x }
        if screenPoint.y < margin { dy = margin - screenPoint.y }
        if screenPoint.y > frame.viewHeight - margin { dy = frame.viewHeight - margin - screenPoint.y }
        guard dx != 0 || dy != 0 else { return }
        pan(dx: dx, dy: dy, in: frame)
    }
}

// MARK: - Finger to pointer

public enum PicturePointerMapping {
    /// The pointer movement for a finger's movement on the picture, before
    /// the Pointer surface's sensitivity and the Mac's acceleration (which
    /// apply unchanged). Relative: where the finger is doesn't matter, and
    /// pan doesn't either. Zoomed in, the same finger travel moves the
    /// pointer less, so it crosses the same part of the picture on screen.
    public static func pointerDelta(dx: Double, dy: Double, zoom: PictureZoom) -> (dx: Double, dy: Double) {
        let scale = max(zoom.scale, PictureZoom.minimumScale)
        return (dx / scale, dy / scale)
    }

    /// The factor `TouchTrackingView` multiplies finger movement by on the
    /// picture: the Pointer surface's sensitivity over the zoom.
    public static func sensitivity(_ pointerSensitivity: Double, zoom: PictureZoom) -> Double {
        pointerSensitivity / max(zoom.scale, PictureZoom.minimumScale)
    }
}

// MARK: - On or off, per Mac

/// Whether pointer control on the picture is on, per Mac. Off until the
/// person turns it on for that Mac; then whatever they chose last.
/// Stored as JSON (`@AppStorage` string) on this device.
public struct PicturePointerMemory: Codable, Equatable, Sendable {
    /// More Macs than anyone uses; keeps the stored string small.
    public static let capacity = 16
    /// Used when the Mac's identity isn't known yet.
    public static let unknownMacKey = "unknown"

    public struct Entry: Codable, Equatable, Sendable {
        public var mac: String
        public var isOn: Bool
    }

    /// Least recently set first.
    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = Array(entries.suffix(Self.capacity))
    }

    /// Reads the stored JSON; anything unreadable is an empty memory.
    public init(json: String) {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PicturePointerMemory.self, from: data) else {
            self.init()
            return
        }
        self.init(entries: decoded.entries)
    }

    public var json: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func key(_ mac: UUID?) -> String {
        mac?.uuidString ?? unknownMacKey
    }

    /// Off unless the last choice for this Mac was on.
    public func isOn(for mac: UUID?) -> Bool {
        let key = Self.key(mac)
        return entries.last { $0.mac == key }?.isOn ?? false
    }

    /// Remembers the choice for this Mac, most recent last.
    public mutating func set(_ isOn: Bool, for mac: UUID?) {
        let key = Self.key(mac)
        entries.removeAll { $0.mac == key }
        entries.append(Entry(mac: key, isOn: isOn))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }
}

// MARK: - When it's offered

public enum PicturePointerControl {
    /// The toggle shows only where the picture has no trackpad beside it:
    /// the screen-only arrangement, or a Screen tab too short for the pad.
    public static func isOffered(screenOnly: Bool, showsTrackpad: Bool) -> Bool {
        screenOnly && !showsTrackpad
    }

    /// Control is live when offered, on for this Mac, and the mirror (Pro)
    /// is allowed. The mirror itself is already behind `.requiresPro(.mirror)`;
    /// this only keeps a stale "on" from driving a picture that isn't there.
    public static func isActive(offered: Bool, isOn: Bool, mirrorAllowed: Bool, hasPicture: Bool) -> Bool {
        offered && isOn && mirrorAllowed && hasPicture
    }

    /// VoiceOver's name for the toolbar toggle.
    public static let toggleLabel = "Control the pointer from the picture"
    /// Its accessibility identifier (UI tests).
    public static let toggleIdentifier = "ph.mirror.pointerControl"
}
