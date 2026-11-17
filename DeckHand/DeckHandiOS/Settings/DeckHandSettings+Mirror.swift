//
//  DeckHandSettings+Mirror.swift
//  DeckHandiOS
//
//  Mirror choices: frame rate, sharpness, remembered layout.
//  Split out of DeckHandSettings.swift (PH-010); the stored properties stay
//  in `DeckHandSettings`.
//

import Foundation
import SwiftUI

/// Frames per second the iPad asks the Mac to stream. The host clamps to 30,
/// so anything above that is wasted breath.
enum MirrorFrameRate: Int, CaseIterable, Identifiable, Codable {
    case economy = 15
    case standard = 20
    case smooth = 30

    var id: Int { rawValue }
    var label: String { "\(rawValue) fps" }
}

/// How the mirror's stream resolution is chosen.
enum MirrorSharpness: String, CaseIterable, Identifiable, Codable {
    /// Follows the on-screen size — a corner tile streams far fewer pixels
    /// than a pinched-out mirror.
    case auto
    /// Pins the lowest tier no matter how large the mirror is drawn.
    case saver
    /// Pins the host's ceiling, for reading small text over a good link.
    case sharp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .saver: return "Battery saver"
        case .sharp: return "Sharp"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Matches the size you pinch the mirror to."
        case .saver: return "Lowest resolution. Best on a weak network."
        case .sharp: return "Highest resolution the Mac will send."
        }
    }

    /// Applies this preference to the width the mirror's size implies.
    func resolve(naturalWidth: Int) -> Int {
        switch self {
        case .auto: return naturalWidth
        case .saver: return 640
        case .sharp: return 1920
        }
    }
}

/// Where the mirror was last left, so it can come back the same size and in
/// the same corner instead of resetting to a small tile every session.
struct MirrorLayout: Codable, Equatable {
    var width: Double
    var offsetX: Double
    var offsetY: Double
}
