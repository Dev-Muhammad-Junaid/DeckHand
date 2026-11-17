//
//  RemoteInputValidation.swift
//  PixelHandCore
//
//  The one place the Mac checks every number a remote sends before it
//  reaches CoreGraphics, ScreenCaptureKit or an integer conversion. A remote
//  is a peer on the network, not trusted code: `Int32(-dy * 3)` used to trap
//  (and take the whole host down) on a scroll of 1e9, and JSON can carry
//  any value up to `Float.greatestFiniteMagnitude`.
//
//  Rules: non-finite values drop the message, finite values are clamped to
//  a range no real gesture exceeds. Nothing here can trap.
//

import Foundation

public enum RemoteInputValidation {
    /// Largest pointer delta (points) accepted in one `mouseDelta`. A fast
    /// swipe at 120 Hz sends well under 200.
    public static let maxPointerDelta: Float = 2_000
    /// Largest scroll delta accepted in one `mouseScroll`.
    public static let maxScrollDelta: Float = 10_000
    /// Bounds for `startMirror`. The mirror service applies the same caps;
    /// they're repeated here so this layer is complete on its own.
    public static let mirrorFPSRange: ClosedRange<Int> = 1...30
    public static let mirrorWidthRange: ClosedRange<Int> = 120...1920

    // MARK: - Message-level entry point

    /// Returns `message` with every remote-supplied number made safe, or
    /// `nil` when the message must be dropped (a non-finite float, an empty
    /// capture region). Messages without numbers pass through unchanged.
    public static func sanitize(_ message: ControlMessage) -> ControlMessage? {
        switch message {
        case let .mouseDelta(dx, dy):
            guard let safeDX = clamp(dx, limit: maxPointerDelta),
                  let safeDY = clamp(dy, limit: maxPointerDelta) else { return nil }
            return .mouseDelta(dx: safeDX, dy: safeDY)

        case let .mouseScroll(dx, dy, phase):
            guard let safeDX = clamp(dx, limit: maxScrollDelta),
                  let safeDY = clamp(dy, limit: maxScrollDelta) else { return nil }
            return .mouseScroll(dx: safeDX, dy: safeDY, phase: phase)

        case let .requestScreenshot(requestID, mode, quality):
            guard let safeMode = sanitize(mode) else { return nil }
            return .requestScreenshot(requestID: requestID, mode: safeMode, quality: quality)

        case let .startMirror(fps, maxWidth, displayID):
            return .startMirror(
                fps: clamp(fps, to: mirrorFPSRange),
                maxWidth: clamp(maxWidth, to: mirrorWidthRange),
                displayID: displayID
            )

        case let .tracked(requestID, command):
            guard let safeCommand = sanitize(command) else { return nil }
            return .tracked(requestID: requestID, command: safeCommand)

        default:
            return message
        }
    }

    /// Region captures must lie inside the display (0…1) and be non-empty.
    /// The region is intersected with the unit square rather than rejected,
    /// so a crop dragged slightly past the edge still works.
    public static func sanitize(_ mode: CaptureMode) -> CaptureMode? {
        guard case let .region(x, y, width, height) = mode else { return mode }
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }
        // Already inside: return it untouched, since recomputing the size
        // from the clipped edges can shift it by a Float rounding step.
        if x >= 0, y >= 0, x + width <= 1, y + height <= 1 { return mode }
        let minX = max(0, min(1, x))
        let minY = max(0, min(1, y))
        let maxX = max(0, min(1, x + width))
        let maxY = max(0, min(1, y + height))
        guard maxX > minX, maxY > minY else { return nil }
        return .region(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Primitives

    /// `nil` for NaN/±∞, otherwise `value` clamped to `-limit…limit`.
    public static func clamp(_ value: Float, limit: Float) -> Float? {
        guard value.isFinite else { return nil }
        return max(-limit, min(limit, value))
    }

    public static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, value))
    }

    /// Converts a scroll delta to the wheel units `CGEvent` takes
    /// (`-delta * 3`, natural direction). Never traps: non-finite input is
    /// 0 and the result is clamped to `Int32`'s range. `InputInjector` uses
    /// this as a second line of defence behind `sanitize`.
    public static func wheelUnits(forScrollDelta delta: Float) -> Int32 {
        guard delta.isFinite else { return 0 }
        let units = (-Double(delta) * 3).rounded(.towardZero)
        if units >= Double(Int32.max) { return .max }
        if units <= Double(Int32.min) { return .min }
        return Int32(units)
    }
}
