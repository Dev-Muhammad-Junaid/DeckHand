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

    /// What the canvas shows in its centre when the deck already has its
    /// own column (iPhone landscape rail, iPad). The selection itself is
    /// kept, so the Deck tab comes back when the column goes.
    func centre(hasDeckColumn: Bool) -> ControlSurface {
        hasDeckColumn && self == .deck ? .pointer : self
    }

    /// The tabs the plan offers: the deck's tab goes when it has a column.
    static func tabs(includeDeck: Bool) -> [ControlSurface] {
        includeDeck ? allCases : [.pointer, .screen]
    }
}
