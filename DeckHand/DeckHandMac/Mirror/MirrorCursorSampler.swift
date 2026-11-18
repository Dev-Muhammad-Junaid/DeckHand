//
//  MirrorCursorSampler.swift
//  DeckHandMac
//
//  S3: reads the Mac's pointer for the mirror. The mirror is captured with
//  `showsCursor = false`; the remote draws the pointer from what this
//  sends, so it moves at 60 Hz whatever the video's frame rate.
//
//  Public API only: `CGEvent(source: nil).location` for the position
//  (global, top-left origin, the same space as `CGDisplayBounds`),
//  `CGGetDisplaysWithPoint` for the display under it, and
//  `NSCursor.currentSystem` for the shape the system is showing, in any app.
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
final class MirrorCursorSampler {
    /// The shape last read, and the bytes it was identified by, so an
    /// unchanged pointer isn't re-encoded.
    private var lastShape: MirrorCursorShape?
    private var lastShapeKey: UInt32 = 0

    /// Where the pointer is relative to `mirroredDisplayID`.
    func state(mirroredDisplayID: CGDirectDisplayID, shapeID: UInt32) -> MirrorCursorState? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        let bounds = CGDisplayBounds(mirroredDisplayID)
        let position = MirrorCursorGeometry.normalized(
            x: Double(location.x),
            y: Double(location.y),
            in: MirrorRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
        )
        return MirrorCursorState(
            x: position.x,
            y: position.y,
            shapeID: shapeID,
            displayID: Self.display(at: location) ?? 0,
            isOnMirroredDisplay: position.inside,
            isHidden: false
        )
    }

    /// The pointer image the system shows now. Cheap when it hasn't
    /// changed: only a new image is encoded as PNG.
    func currentShape() -> MirrorCursorShape? {
        guard let cursor = NSCursor.currentSystem else { return lastShape }
        let image = cursor.image
        let size = image.size
        guard size.width > 0, size.height > 0 else { return lastShape }
        // Render at 2× so the pointer stays sharp on a Retina iPad.
        var rect = CGRect(x: 0, y: 0, width: size.width * 2, height: size.height * 2)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return lastShape
        }
        // NSCursor's hot spot is measured from the image's top-left corner.
        let hotSpot = cursor.hotSpot
        guard let raw = cgImage.dataProvider?.data as Data? else { return lastShape }
        let key = MirrorCursorShape.makeID(png: raw, hotSpotX: Double(hotSpot.x), hotSpotY: Double(hotSpot.y))
        if key == lastShapeKey, let lastShape { return lastShape }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        guard let png = rep.representation(using: .png, properties: [:]),
              png.count <= MirrorCursorShape.maxImageBytes else { return lastShape }
        let shape = MirrorCursorShape(
            id: key,
            hotSpotX: Double(hotSpot.x),
            hotSpotY: Double(hotSpot.y),
            width: Double(size.width),
            height: Double(size.height),
            png: png
        )
        lastShapeKey = key
        lastShape = shape
        return shape
    }

    func reset() {
        lastShape = nil
        lastShapeKey = 0
    }

    private static func display(at point: CGPoint) -> CGDirectDisplayID? {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }
}
