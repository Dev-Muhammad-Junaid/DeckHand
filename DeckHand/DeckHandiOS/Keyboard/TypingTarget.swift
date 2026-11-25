//
//  TypingTarget.swift
//  DeckHandiOS
//
//  The app in front on the Mac, for the keyboard bar's "Typing into …"
//  line and its Return check (VQ-036). The session writes it when the Mac
//  reports the front app; the keyboard bar reads it, wherever it is shown.
//

import Observation

@MainActor
@Observable
final class TypingTarget {
    static let shared = TypingTarget()

    /// The Mac's front app, as it last reported it.
    var frontApp: String?

    /// What the person typed into; Return to another app asks first.
    var guardrail = TypingTargetGuard()
}
