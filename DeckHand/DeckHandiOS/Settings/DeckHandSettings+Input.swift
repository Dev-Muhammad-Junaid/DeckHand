//
//  DeckHandSettings+Input.swift
//  DeckHandiOS
//
//  Pointer and haptics choices.
//  Split out of DeckHandSettings.swift (PH-010); the stored properties stay
//  in `DeckHandSettings`.
//

import Foundation
import SwiftUI

/// How often touch deltas are sent. 120 Hz matches ProMotion so no input is
/// discarded; 60 Hz halves packet volume on a congested link.
enum InputSendRate: Int, CaseIterable, Identifiable, Codable {
    case standard = 60
    case proMotion = 120

    var id: Int { rawValue }
    var label: String { "\(rawValue) Hz" }
}

enum HapticStrength: String, CaseIterable, Identifiable, Codable {
    case off
    case light
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .full: return "Full"
        }
    }

    /// Scales a requested haptic to this strength. `nil` means "don't fire".
    /// At `.light` everything collapses to the softest impact, so the app
    /// still confirms actions without thumping.
    func resolve(_ requested: GestureHaptic) -> GestureHaptic? {
        switch self {
        case .off:
            return nil
        case .light:
            return requested == .selection ? .selection : .light
        case .full:
            return requested
        }
    }
}

/// Settings copy for typing, drags, gestures, Pencil hover and the
/// clipboard (iOS interaction lane).
enum TrackpadInputCopy {
    static let gesturesCaption = "Three fingers (four where iPadOS allows): swipe up for Mission Control, down for App Exposé, left or right for Spaces, pinch for Apps, spread for the desktop. The opposite gesture closes what you opened."
    static let clickStripCaption = "Click and Right-click buttons along the bottom of the trackpad. Touch and hold them for Double-click and Find the pointer."
    static let pencilCaption = "Hover the Pencil over the trackpad to aim, then tap to click."
    static let dragFooter = "To drag, rest a finger until it buzzes, then move; put a second finger down to lock the drag, and tap to drop."
    static let clipboardFooter = "With Share clipboard on, text you copy on the Mac is ready to paste here (text only, up to 64 KB; never while the Mac is locked, never passwords a password manager marks private). Paste to Mac in the trackpad's keyboard panel sends this device's clipboard; Pixel Hand never reads it by itself. With Paste on the Mac right away off, it only goes to the Mac's clipboard."
}
