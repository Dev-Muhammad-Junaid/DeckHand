//
//  MacPointerAcceleration.swift
//  PixelHandCore
//
//  The pointer curve the Mac applies to every `mouseDelta`, per axis:
//  under 3 pt a delta moves 1:1, above it the gain ramps by 0.12 per point
//  (`InputInjector.moveCursor`). Shared so the remote can predict where a
//  delta lands (`PicturePointerGuard`) with the Mac's own maths.
//

import Foundation

public enum MacPointerAcceleration {
    /// Deltas below this many points move 1:1.
    public static let linearLimit = 3.0
    /// Extra gain per point above `linearLimit`.
    public static let ramp = 0.12

    /// The distance the Mac moves the pointer for one axis of a delta.
    public static func apply(_ delta: Double) -> Double {
        guard delta.isFinite else { return 0 }
        let magnitude = abs(delta)
        let factor = magnitude < linearLimit ? 1 : 1 + (magnitude - linearLimit) * ramp
        return delta * factor
    }

    /// The delta that makes the Mac move the pointer by `moved` on one
    /// axis: the inverse of `apply` (which is strictly increasing).
    public static func inverse(_ moved: Double) -> Double {
        guard moved.isFinite else { return 0 }
        let magnitude = abs(moved)
        guard magnitude >= linearLimit else { return moved }
        // ramp·m² + (1 − ramp·linearLimit)·m − moved = 0
        let b = 1 - ramp * linearLimit
        let m = (-b + (b * b + 4 * ramp * magnitude).squareRoot()) / (2 * ramp)
        return moved < 0 ? -m : m
    }
}
