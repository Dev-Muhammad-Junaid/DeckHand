//
//  ControlSurface.swift
//  DeckHandiOS – Shell
//
//  The three surfaces the canvas shows (Option A, "Dock & Canvas"):
//  Pointer, Screen and Deck. Ask sits in the tab bar's search slot but is an
//  action, not a surface. Spec: `Product/Design/03-Layout-Strategy.md`.
//

import SwiftUI

enum ControlSurface: String, CaseIterable, Identifiable, Sendable {
    case pointer
    case screen
    case deck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pointer: "Pointer"
        case .screen: "Screen"
        case .deck: "Deck"
        }
    }

    var glyph: GlyphBitmap {
        switch self {
        case .pointer: PixelGlyphs.pointer
        case .screen: PixelGlyphs.screen
        case .deck: PixelGlyphs.deck
        }
    }

    /// What the canvas shows in its centre when the wide layout already
    /// shows the deck in its own column. The selection itself is kept.
    func centre(in arrangement: LayoutMetrics.Arrangement) -> ControlSurface {
        arrangement == .columns && self == .deck ? .pointer : self
    }

    /// The tabs the arrangement offers. On wide layouts the deck has its own
    /// column, so its tab goes.
    static func tabs(for arrangement: LayoutMetrics.Arrangement) -> [ControlSurface] {
        arrangement == .columns ? [.pointer, .screen] : allCases
    }
}
