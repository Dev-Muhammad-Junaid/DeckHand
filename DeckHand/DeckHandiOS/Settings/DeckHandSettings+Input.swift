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
