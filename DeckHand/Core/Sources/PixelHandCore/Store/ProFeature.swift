//
//  ProFeature.swift
//  PixelHandCore
//
//  What the free plan includes and what needs Pixel Hand Pro
//  (DECISIONS.md, 2026-11-17):
//
//  - Free: trackpad, keyboard (typing included) and media keys, with one
//    Mac.
//  - Pro: decks and chips, the mirror (every codec, window mirror), capture
//    and OCR, more than one Mac, sharing (clipboard), and AI.
//
//  Everything is unlocked during the free trial and while a subscription is
//  in its grace or billing-retry period (`Entitlement.isPro`).
//
//  Only the remote is gated. The Mac app stays free and answers every
//  message it's sent.
//

import Foundation

/// Something a person can do from the remote, for gating.
public enum ProFeature: String, CaseIterable, Codable, Sendable {
    // Free
    case trackpad
    case keyboard
    case mediaKeys
    // Pro
    /// Shortcut chips, dialog-button chips, the app launcher and decks.
    case decks
    /// The live mirror, in every codec, and window mirroring.
    case mirror
    /// Screenshots, region and window capture, and text recognition.
    case capture
    /// Controlling a Mac other than the free plan's one Mac.
    case multipleMacs
    /// Clipboard sharing between this device and the Mac.
    case sharing
    /// AI commands (planned).
    case ai

    /// The plan this feature needs.
    public var tier: Tier {
        switch self {
        case .trackpad, .keyboard, .mediaKeys:
            .free
        case .decks, .mirror, .capture, .multipleMacs, .sharing, .ai:
            .pro
        }
    }

    /// The two plans the app knows.
    public enum Tier: String, Codable, Sendable {
        case free
        case pro
    }

    /// The features Pro adds, in the order the paywall lists them.
    public static let proFeatures: [ProFeature] = allCases.filter { $0.tier == .pro }
}
