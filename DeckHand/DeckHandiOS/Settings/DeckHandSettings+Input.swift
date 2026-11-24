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
    static let gesturesCaption = "Three fingers: up for Mission Control, down for App Exposé, sideways for Spaces."
    static let clickStripCaption = "Click and Right-click along the bottom of the trackpad."
    static let pencilCaption = "Hover the Pencil over the trackpad to aim, then tap to click."
    static let dragFooter = "To drag, rest a finger until it buzzes, then move; put a second finger down to lock the drag, and tap to drop."
    static let clipboardFooter = "Text you copy on the Mac is ready to paste here, never while it’s locked and never marked passwords. Pixel Hand reads this device’s clipboard only when you tap Paste to Mac."
}
