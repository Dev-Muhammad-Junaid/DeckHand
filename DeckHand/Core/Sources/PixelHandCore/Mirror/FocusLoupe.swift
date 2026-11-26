//
//  FocusLoupe.swift
//  PixelHandCore
//
//  The Type panel's loupe (OT-12): which part of the mirrored display to
//  show, given the Mac's `FocusedFieldSnapshot` and the loupe's size.
//
//  - Zoom fits the field's width (plus a little padding) into the loupe,
//    between `minZoom` and `maxZoom`, and never so low that the crop would
//    be larger than the display.
//  - On each axis the crop centres the field when it fits; when it doesn't
//    (a tall text area, a long line), it follows the caret with
//    hysteresis: the previous crop stays until the caret comes within
//    `panMargin` of its edge, then recentres on it. Without a caret it
//    shows the field's top-leading corner.
//  - Without a field frame (`source == .pointer`, or a caret alone) it
//    zooms by `pointerZoom` around the pointer (or caret), with the same
//    hysteresis.
//  - The crop is clamped inside the display and returned in normalized
//    display coordinates (0…1, top-left), which is also the mirror video's
//    frame: the Mac scales the whole display into the video without
//    letterboxing, so `videoRect` is one multiplication. On iOS the
//    normalized rect can go straight into `CALayer.contentsRect`.
//
//  A loupe zoom is loupe points per display point.
//

import Foundation

/// A rect in normalized display (or video) coordinates: 0…1, top-left.
public struct LoupeRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A rect in the mirror video's pixels, top-left.
public struct LoupePixelRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct FocusLoupeConfiguration: Sendable, Hashable {
    public var minZoom: Double
    public var maxZoom: Double
    /// Zoom around the pointer (or a caret without a field).
    public var pointerZoom: Double
    /// Display points kept around the field on each side.
    public var fieldPadding: Double
    /// How near an edge (a fraction of the crop's size) the caret or the
    /// pointer may come before the crop recentres on it.
    public var panMargin: Double
    /// A new zoom within this fraction of the previous one keeps the
    /// previous one, so a field that grows by a pixel doesn't jiggle.
    public var zoomHysteresis: Double

    public init(minZoom: Double = 1.5, maxZoom: Double = 6, pointerZoom: Double = 3, fieldPadding: Double = 8, panMargin: Double = 0.2, zoomHysteresis: Double = 0.08) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.pointerZoom = pointerZoom
        self.fieldPadding = fieldPadding
        self.panMargin = panMargin
        self.zoomHysteresis = zoomHysteresis
    }

    public static let standard = FocusLoupeConfiguration()
}

/// What the loupe shows.
public struct FocusLoupeCrop: Sendable, Hashable {
    public enum Mode: String, Sendable, Hashable {
        /// The whole field fits (or, without a caret, its top-leading part).
        case field
        /// Following the caret along an axis the field doesn't fit.
        case caret
        /// Around the pointer (no field frame).
        case pointer
    }

    /// Normalized display coordinates (0…1, top-left).
    public var rect: LoupeRect
    /// Loupe points per display point.
    public var zoom: Double
    public var mode: Mode

    public init(rect: LoupeRect, zoom: Double, mode: Mode) {
        self.rect = rect
        self.zoom = zoom
        self.mode = mode
    }
}

public enum FocusLoupe {
    /// The crop for `snapshot` in a loupe of `loupeWidth` × `loupeHeight`
    /// points. `mirroredDisplayID`: the display the mirror shows (`nil`:
    /// don't check). `previous`: the last crop, for hysteresis. `nil` when
    /// there's nothing to show: a snapshot for another display, `.none`,
    /// no rects, or sizes that aren't positive and finite.
    public static func crop(
        for snapshot: FocusedFieldSnapshot,
        mirroredDisplayID: UInt32?,
        loupeWidth: Double,
        loupeHeight: Double,
        previous: FocusLoupeCrop? = nil,
        configuration c: FocusLoupeConfiguration = .standard
    ) -> FocusLoupeCrop? {
        if let mirroredDisplayID, mirroredDisplayID != snapshot.displayID { return nil }
        let dw = snapshot.displayWidth, dh = snapshot.displayHeight
        guard dw.isFinite, dh.isFinite, dw > 0, dh > 0,
              loupeWidth.isFinite, loupeHeight.isFinite, loupeWidth > 0, loupeHeight > 0 else { return nil }

        // The lowest zoom at which the crop still fits the display.
        let fitZoom = max(loupeWidth / dw, loupeHeight / dh)
        func clampZoom(_ z: Double) -> Double {
            max(fitZoom, min(c.maxZoom, max(c.minZoom, z)))
        }
        func usable(_ r: FocusRect?) -> FocusRect? {
            guard let r, r.isValid else { return nil }
            return r
        }
        let field = usable(snapshot.field).flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        let caret = usable(snapshot.caret)
        let pointer = usable(snapshot.pointer)

        var mode: FocusLoupeCrop.Mode
        var zoom: Double
        if snapshot.source == .accessibility, let field {
            mode = .field
            zoom = clampZoom(loupeWidth / (field.width + 2 * c.fieldPadding))
        } else if snapshot.source == .accessibility, caret != nil {
            mode = .caret
            zoom = clampZoom(c.pointerZoom)
        } else if snapshot.source != .none, pointer != nil {
            mode = .pointer
            zoom = clampZoom(c.pointerZoom)
        } else {
            return nil
        }

        // Keep the previous zoom when the new one is close: same family of
        // crop (pointer or not) and still inside the allowed range.
        let comparable = previous.map { ($0.mode == .pointer) == (mode == .pointer) } ?? false
        if comparable, let previous, previous.zoom.isFinite, previous.zoom > 0,
           abs(zoom / previous.zoom - 1) < c.zoomHysteresis,
           previous.zoom >= fitZoom, previous.zoom <= max(c.maxZoom, fitZoom) {
            zoom = previous.zoom
        }

        let cw = loupeWidth / zoom
        let ch = loupeHeight / zoom
        let sameSize = comparable && previous.map { abs($0.zoom - zoom) < 1e-9 } == true
        let previousOrigin = sameSize ? previous.map { (x: $0.rect.x * dw, y: $0.rect.y * dh) } : nil

        /// The crop's origin on one axis, following `target` with
        /// hysteresis against the previous origin.
        func follow(_ target: Double, size: Double, previous: Double?) -> Double {
            if let previous {
                let margin = size * c.panMargin
                if target >= previous + margin, target <= previous + size - margin { return previous }
            }
            return target - size / 2
        }

        var x: Double
        var y: Double
        switch mode {
        case .field:
            let field = field!
            let pad = c.fieldPadding
            if field.width + 2 * pad <= cw {
                x = field.midX - cw / 2
            } else if let caret {
                x = follow(caret.midX, size: cw, previous: previousOrigin?.x)
                mode = .caret
            } else {
                x = field.minX - pad
            }
            if field.height + 2 * pad <= ch {
                y = field.midY - ch / 2
            } else if let caret {
                y = follow(caret.midY, size: ch, previous: previousOrigin?.y)
                mode = .caret
            } else {
                y = field.minY - pad
            }
        case .caret:
            let caret = caret!
            x = follow(caret.midX, size: cw, previous: previousOrigin?.x)
            y = follow(caret.midY, size: ch, previous: previousOrigin?.y)
        case .pointer:
            let pointer = pointer!
            x = follow(pointer.midX, size: cw, previous: previousOrigin?.x)
            y = follow(pointer.midY, size: ch, previous: previousOrigin?.y)
        }

        // Inside the display.
        x = min(max(0, x), max(0, dw - cw))
        y = min(max(0, y), max(0, dh - ch))
        let rect = LoupeRect(x: x / dw, y: y / dh, width: min(1, cw / dw), height: min(1, ch / dh))
        return FocusLoupeCrop(rect: rect, zoom: zoom, mode: mode)
    }

    /// `rect` (display points) in normalized display coordinates, `nil`
    /// for a display size that isn't positive and finite.
    public static func normalized(_ rect: FocusRect, displayWidth: Double, displayHeight: Double) -> LoupeRect? {
        guard rect.isValid, displayWidth.isFinite, displayHeight.isFinite, displayWidth > 0, displayHeight > 0 else { return nil }
        return LoupeRect(x: rect.x / displayWidth, y: rect.y / displayHeight, width: rect.width / displayWidth, height: rect.height / displayHeight)
    }

    /// Where `rect` (normalized display coordinates) lands inside a loupe
    /// showing `crop`, for drawing the caret or the field's outline over
    /// it: 0…1 inside the loupe, outside that range when it's off the crop.
    public static func position(of rect: LoupeRect, inCrop crop: LoupeRect) -> LoupeRect? {
        guard crop.width > 0, crop.height > 0 else { return nil }
        return LoupeRect(
            x: (rect.x - crop.x) / crop.width,
            y: (rect.y - crop.y) / crop.height,
            width: rect.width / crop.width,
            height: rect.height / crop.height
        )
    }

    /// The crop in the mirror video's pixels. The video is the whole
    /// display scaled to `videoWidth` × `videoHeight` (no letterbox), so
    /// normalized coordinates scale straight across.
    public static func videoRect(for crop: LoupeRect, videoWidth: Double, videoHeight: Double) -> LoupePixelRect {
        LoupePixelRect(
            x: crop.x * videoWidth,
            y: crop.y * videoHeight,
            width: crop.width * videoWidth,
            height: crop.height * videoHeight
        )
    }

    /// Video pixels behind each loupe point; under the screen's scale (2 on
    /// an iPad) the loupe is upscaling and looks soft.
    public static func videoPixelsPerLoupePoint(crop: LoupeRect, videoWidth: Double, loupeWidth: Double) -> Double {
        guard loupeWidth > 0 else { return 0 }
        return crop.width * videoWidth / loupeWidth
    }

    /// The mirror width (`mirror.start`'s `maxWidth`) at which the crop
    /// would be sharp on a screen of `screenScale`, capped at `maxWidth`
    /// (the Mac's cap, 1920).
    public static func recommendedMirrorWidth(crop: LoupeRect, loupeWidth: Double, screenScale: Double, maxWidth: Int = 1_920) -> Int {
        guard crop.width > 0, loupeWidth > 0, screenScale > 0 else { return maxWidth }
        let wanted = loupeWidth * screenScale / crop.width
        guard wanted.isFinite else { return maxWidth }
        return min(maxWidth, max(120, Int(wanted.rounded(.up))))
    }
}
