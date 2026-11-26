//
//  CapturePreviewLayout.swift
//  PixelHandCore
//
//  The capture preview's picture and zoom (owner testing, build 26,
//  OT-10). The picture takes all the room between the header and the
//  action dock, aspect-fit and centred, in both orientations; the dock is
//  anchored at the bottom. Build 18's fix (VQ-051) hugged the picture to
//  the width with the dock right under it, which in portrait left a small
//  picture at the top and half the screen empty under the dock.
//
//  Zoom: pinch between 1× and `maximumZoom`; double-tap zooms in on the
//  tapped point, or back to 1×; a drag pans while zoomed, never past the
//  picture's edges. The views apply `scaleEffect(zoom)` around the
//  picture's centre and then `offset(pan)`; everything here uses that
//  model and works in the picture's own points (top-left origin).
//

import Foundation

public enum CapturePreviewLayout {
    /// Picture inset from the stage's sides (the compact margin).
    public static let sideInset = 16.0
    /// Gap between the header, the picture and the dock.
    public static let gap = 12.0
    /// The dock never stretches wider than this (iPad landscape keeps five
    /// actions together instead of spreading them over 1180 pt).
    public static let dockMaximumWidth = 560.0

    /// Pinch range.
    public static let minimumZoom = 1.0
    public static let maximumZoom = 6.0
    /// Where a double-tap zooms to.
    public static let doubleTapZoom = 2.5
    /// Above this the picture counts as zoomed (drags pan instead of
    /// closing the sheet).
    public static let zoomedThreshold = 1.01

    // MARK: Fit

    /// The picture's frame inside `area` (the room between header and
    /// dock, less the side insets): aspect-fit, centred, on whole points so
    /// the picture and its well never sit at a fractional offset
    /// (`07-Polish-Spec.md` §5.3).
    public static func pictureFrame(imageWidth: Double, imageHeight: Double, in area: MirrorRect) -> MirrorRect {
        let fit = CaptureGeometry.fittedRect(contentWidth: imageWidth, contentHeight: imageHeight, in: area)
        guard fit.width > 0, fit.height > 0 else { return fit }
        let width = fit.width.rounded(.down)
        let height = fit.height.rounded(.down)
        return MirrorRect(
            x: (area.x + (area.width - width) / 2).rounded(.down),
            y: (area.y + (area.height - height) / 2).rounded(.down),
            width: width,
            height: height
        )
    }

    /// The area the picture may use in a stage of `width` × `height` with
    /// the header and dock heights taken off.
    public static func pictureArea(stageWidth: Double, stageHeight: Double, headerHeight: Double, dockHeight: Double) -> MirrorRect {
        let top = headerHeight + gap
        let available = stageHeight - top - gap - dockHeight
        return MirrorRect(
            x: sideInset,
            y: top,
            width: max(0, stageWidth - 2 * sideInset),
            height: max(0, available)
        )
    }

    // MARK: Zoom and pan

    public static func isZoomed(_ zoom: Double) -> Bool {
        zoom > zoomedThreshold
    }

    public static func clampedZoom(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return minimumZoom }
        return min(max(zoom, minimumZoom), maximumZoom)
    }

    /// `pan` limited so the zoomed picture always covers its frame
    /// (`width` × `height`): at most half the extra size each way, and none
    /// at 1×.
    public static func clampedPan(x: Double, y: Double, zoom: Double, width: Double, height: Double) -> (x: Double, y: Double) {
        let zoom = clampedZoom(zoom)
        let limitX = max(0, width * (zoom - 1) / 2)
        let limitY = max(0, height * (zoom - 1) / 2)
        return (min(max(x, -limitX), limitX), min(max(y, -limitY), limitY))
    }

    /// A pinch: the zoom it started from times the gesture's
    /// magnification, clamped; the pan scales with it so the same part of
    /// the picture stays in view, then is clamped.
    public static func pinch(
        startZoom: Double,
        magnification: Double,
        startPan: (x: Double, y: Double),
        width: Double,
        height: Double
    ) -> (zoom: Double, pan: (x: Double, y: Double)) {
        let zoom = clampedZoom(startZoom * magnification)
        let ratio = startZoom > 0 ? zoom / startZoom : 1
        guard isZoomed(zoom) else { return (minimumZoom, (0, 0)) }
        let pan = clampedPan(x: startPan.x * ratio, y: startPan.y * ratio, zoom: zoom, width: width, height: height)
        return (zoom, pan)
    }

    /// A double-tap at `point` (picture points, top-left origin): zoomed
    /// in, it goes back to 1×; at 1× it zooms to `doubleTapZoom` keeping the
    /// tapped point under the finger (as far as the edges allow).
    public static func doubleTap(
        at point: (x: Double, y: Double),
        zoom: Double,
        width: Double,
        height: Double
    ) -> (zoom: Double, pan: (x: Double, y: Double)) {
        guard !isZoomed(zoom) else { return (minimumZoom, (0, 0)) }
        let target = doubleTapZoom
        let px = min(max(point.x, 0), width)
        let py = min(max(point.y, 0), height)
        // scaleEffect around the centre c, then offset: p ↦ c + (p − c)·z + pan.
        // Keeping p in place: pan = (c − p)·(z − 1).
        let pan = clampedPan(
            x: (width / 2 - px) * (target - 1),
            y: (height / 2 - py) * (target - 1),
            zoom: target,
            width: width,
            height: height
        )
        return (target, pan)
    }
}
