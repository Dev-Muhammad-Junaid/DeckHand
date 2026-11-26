//
//  SidebarCardPlan.swift
//  PixelHandCore
//
//  The iPad Macs sidebar's compact card at each Dynamic Type band (build
//  24, VQ-099). At AX3 in landscape the cards cut names and statuses
//  mid-word ("Muh / am…", "AH’s / Ma…", "Text…", "Near…"): beside the
//  44 pt tile, a 176 pt sidebar leaves about 96 pt for text.
//
//  At the Huge band the card stacks: the tile on top, then the name and
//  the status under it across the card's whole width, each on up to two
//  lines broken only between words (the pill's `WholeWordName` layout,
//  shrinking to real smaller sizes before it ever cuts a word). The Large
//  Content Viewer and VoiceOver give the full name and status.
//

import Foundation

public enum SidebarCardPlan {
    /// The card's arrangement.
    public enum Arrangement: Equatable, Sendable {
        /// Tile, then name and status beside it, one line each.
        case row
        /// Tile on top; name and status under it, whole words only.
        case stacked
    }

    public static func arrangement(band: TypeBand) -> Arrangement {
        band == .huge ? .stacked : .row
    }

    /// Lines for the name: one at the Standard band (tail-truncated, where
    /// it fits), two from AX1, broken only between words.
    public static func nameLines(band: TypeBand) -> Int {
        band == .standard ? 1 : 2
    }

    /// Lines for the status line.
    public static func statusLines(band: TypeBand) -> Int {
        band == .huge ? 2 : 1
    }

    /// Whether the name and status use the whole-word layout (never a
    /// mid-word cut). At the Standard band one tail-truncated line reads
    /// fine.
    public static func usesWholeWords(band: TypeBand) -> Bool {
        band != .standard
    }

    /// The width the stacked card gives its text: the sidebar less its
    /// leading margin and the card's own padding.
    public static func stackedTextWidth(sidebarWidth: Double, leadingMargin: Double, cardPadding: Double) -> Double {
        max(0, sidebarWidth - leadingMargin - 2 * cardPadding)
    }

    /// The width the row card gives its text, beside the tile.
    public static func rowTextWidth(sidebarWidth: Double, leadingMargin: Double, cardPadding: Double, tileWidth: Double, spacing: Double) -> Double {
        max(0, sidebarWidth - leadingMargin - 2 * cardPadding - tileWidth - spacing)
    }
}
