//
//  PickerTopBarPlan.swift
//  PixelHandCore
//
//  The picker's top bar (Pair and Settings) over its scrolling column
//  (build 24, VQ-102): at AX5 the subtitle slid under the two buttons,
//  which had no backdrop. Once the column scrolls under the bar, the bar
//  gets a scroll-edge backdrop: the picker's own background, opaque down
//  to just under the buttons, then fading out.
//

import Foundation

public enum PickerTopBarPlan {
    /// How far the column must scroll (points) before the backdrop shows,
    /// so a rubber-band nudge at rest doesn't flash it.
    public static let scrollThreshold: Double = 2
    /// The backdrop's opaque part ends this far under the buttons.
    public static let bottomPadding: Double = 8
    /// Then it fades out over this height.
    public static let fadeHeight: Double = 16

    /// Whether the backdrop shows, from the top of the scrolling content
    /// relative to the scroll view (0 at rest, negative once scrolled).
    public static func showsBackdrop(contentTop: Double) -> Bool {
        contentTop < -scrollThreshold
    }

    /// Where the backdrop's opaque part ends, from the bottom of the button
    /// row, in the same coordinates.
    public static func opaqueBottom(buttonRowBottom: Double) -> Double {
        max(0, buttonRowBottom + bottomPadding)
    }
}
