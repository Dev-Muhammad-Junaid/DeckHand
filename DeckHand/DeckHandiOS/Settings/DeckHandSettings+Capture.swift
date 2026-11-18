//
//  DeckHandSettings+Capture.swift
//  DeckHandiOS
//
//  Capture choices: quality labels and the capture button default.
//  Split out of DeckHandSettings.swift (PH-010); the stored properties stay
//  in `DeckHandSettings`.
//

import Foundation
import SwiftUI

/// `CaptureQuality` is the wire type; these are just its labels. Region and
/// window captures already ship near-native, so this only moves full-screen.
extension CaptureQuality: Identifiable {
    public var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High"
        case .native: return "Native"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "Smaller and faster over the network."
        case .high: return "Sharper text, larger transfers."
        case .native: return "Full Retina pixels. Slowest."
        }
    }
}

/// What the capture button does on a plain tap.
enum DefaultCapture: String, CaseIterable, Identifiable, Codable {
    case fullScreen
    case region
    case window

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullScreen: return "Full screen"
        case .region: return "Region"
        case .window: return "Window"
        }
    }

    var icon: String {
        switch self {
        case .fullScreen: return "rectangle.dashed"
        case .region: return "rectangle.dashed.badge.record"
        case .window: return "macwindow"
        }
    }
}
