//
//  AppIconPolicy.swift
//  PixelHandCore
//
//  How the Mac sends app icons and how the iPhone and iPad draw them
//  (owner testing, build 24, OT-1). Icons used to go as 64 × 64 JPEG,
//  which has no alpha: every icon sat on a white (light) or black (dark)
//  square. They now go with transparency, so the dock shows the real icon
//  shape with nothing behind it, like the macOS Dock.
//
//  Format: PNG, or HEIC with alpha when the Mac can write it, it really
//  kept the alpha, and it came out smaller. `InstalledAppInfo.iconData`
//  stays plain `Data` that `UIImage(data:)` decodes, so no protocol bump.
//

import Foundation

public enum AppIconPolicy {
    /// The largest size an app icon is drawn at on the iPhone or iPad, in
    /// points: the app dock's icon (`dockIconSide`) is the largest of the
    /// places that draw the full list (dock, strip chip, deck keys, app
    /// grid); the shortcuts sheet's 44 pt header icon is a single app and
    /// asks for no more.
    public static let largestDrawnSide: Double = dockIconSide
    /// The icon's pixel size: 2× the largest drawn side.
    public static let pixelSide = Int(largestDrawnSide * 2)

    /// Each icon's byte budget. An encode over it is dropped for the
    /// smaller format, and an icon that can't get under it at all is sent
    /// at `fallbackPixelSide` instead, so ~500 apps stay a few MB.
    public static let maximumBytesPerIcon = 16 * 1024
    public static let fallbackPixelSide = 48

    /// The whole list's budget for about 500 apps; past it, icons beyond
    /// the running apps are sent at `fallbackPixelSide`.
    public static let listByteBudget = 6 * 1024 * 1024

    public enum Format: String, Sendable, Hashable {
        case png, heic
    }

    /// One encode of an icon.
    public struct Encoded: Sendable, Hashable {
        public let format: Format
        public let byteCount: Int
        /// Whether the encode kept an alpha channel (checked by decoding it
        /// back on the Mac: a HEIC writer may drop it silently).
        public let keepsAlpha: Bool

        public init(format: Format, byteCount: Int, keepsAlpha: Bool) {
            self.format = format
            self.byteCount = byteCount
            self.keepsAlpha = keepsAlpha
        }
    }

    /// Picks what to send: the smallest encode that kept its alpha. An
    /// encode without alpha is never chosen: that's the white/black square
    /// this policy exists to remove. `nil` when none qualify.
    public static func choose(_ candidates: [Encoded]) -> Encoded? {
        candidates
            .filter { $0.keepsAlpha && $0.byteCount > 0 }
            .min { lhs, rhs in
                lhs.byteCount != rhs.byteCount ? lhs.byteCount < rhs.byteCount : lhs.format == .png
            }
    }

    /// Whether an encode fits the per-icon budget.
    public static func fitsBudget(_ encoded: Encoded) -> Bool {
        encoded.byteCount <= maximumBytesPerIcon
    }

    /// The pixel side to render the icon at, given how many bytes the list
    /// has used so far and whether the app is running (running apps always
    /// get the full size: they're the dock).
    public static func pixelSide(usedBytes: Int, isRunning: Bool) -> Int {
        isRunning || usedBytes < listByteBudget ? pixelSide : fallbackPixelSide
    }

    // MARK: Drawing (iPhone and iPad)

    /// The dock icon's side, in points.
    public static let dockIconSide: Double = 36
    /// The front-app indicator: a dot under the icon in the accent colour,
    /// like the macOS Dock's running light (replaces the build 24 ring box).
    public static let frontDotSide: Double = 4
    /// The gap between the icon's foot and the dot.
    public static let frontDotGap: Double = 4
    /// The press response: a small dip in scale, no plate behind the icon.
    public static let pressedScale: Double = 0.9
    /// Space between dock icons (centre slots are 44 pt targets).
    public static let dockSpacing: Double = 8
}
