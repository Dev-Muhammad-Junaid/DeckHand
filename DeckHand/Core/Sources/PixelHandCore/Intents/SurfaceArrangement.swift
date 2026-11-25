//
//  SurfaceArrangement.swift
//  PixelHandCore – Intents
//
//  VQ-079: on a window that arranges by preset (the iPad's side-by-side and
//  columns forms), a surface asked for by an intent, a widget or a Control
//  Center control changes the arrangement too. "Trackpad" opens the Pointer
//  arrangement rather than leaving the full split. Tabbed windows (iPhone,
//  narrow Stage Manager) only switch the tab.
//

import Foundation

extension RemoteSurface {
    /// The arrangement to switch to when this surface is asked for on a
    /// window that uses presets, or `nil` to keep `current`.
    ///
    /// - Trackpad: Pointer, where the pad takes the centre.
    /// - Screen: Split while the screen is only a floating tile (Pointer);
    ///   otherwise it already shows, so nothing changes.
    /// - Deck: the deck column always shows, so nothing changes.
    public func arrangement(from current: LayoutPreset) -> LayoutPreset? {
        let target: LayoutPreset? = switch self {
        case .trackpad: .pointer
        case .screen: current == .pointer ? .split : nil
        case .deck: nil
        }
        return target == current ? nil : target
    }
}
