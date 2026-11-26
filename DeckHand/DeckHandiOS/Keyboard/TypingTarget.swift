//
//  TypingTarget.swift
//  DeckHandiOS
//
//  The app in front on the Mac, for the keyboard bar's "Typing into …"
//  line and its Return check (VQ-036). The session writes it when the Mac
//  reports the front app; the keyboard bar reads it, wherever it is shown.
//

import Observation
import PixelHandCore

@MainActor
@Observable
final class TypingTarget {
    static let shared = TypingTarget()

    /// The Mac's front app, as it last reported it.
    var frontApp: String?
    /// Its bundle ID, when the Mac reported one.
    var frontBundleID: String?

    /// ↑/↓ mean shell history there (the arrow joystick labels them).
    var isTerminal: Bool { TerminalApps.isTerminal(bundleID: frontBundleID, name: frontApp) }

    /// What the person typed into; Return to another app asks first.
    var guardrail = TypingTargetGuard()
}
