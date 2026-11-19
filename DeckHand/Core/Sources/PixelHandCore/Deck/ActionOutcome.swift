//
//  ActionOutcome.swift
//  PixelHandCore
//
//  What the Mac answers a tracked `Action` with (`DeckMessage.receipt`).
//

import Foundation

/// What became of a tracked `Action`.
public enum ActionOutcome: Codable, Sendable, Equatable, Hashable {
    /// The Mac received it and handed it to input injection. Slow actions
    /// (`appShortcut`, dialog presses, and Deck 2 runs that outlast
    /// `ActionLimits.receiptDeadline`) finish afterwards in their own
    /// tasks, so this confirms delivery, not the app's result.
    case delivered
    /// The Mac received it and won't run it.
    case refused(reason: RefusalReason)
    /// The Mac tried and it failed.
    case failed(reason: String)
    /// The Mac ran it to the end (a menu press, a Shortcuts run that exited
    /// 0, or a sequence whose steps all ran).
    case completed

    /// Whether the remote should show the action as having arrived.
    public var isSuccess: Bool {
        switch self {
        case .delivered, .completed: true
        case .refused, .failed: false
        }
    }
}

public enum RefusalReason: String, Codable, Sendable, Equatable, Hashable {
    /// Accessibility isn't granted on the Mac, so input can't be posted.
    case accessibilityMissing
    /// The dialog button belongs to a snapshot that has been replaced.
    case staleContext
    /// The Mac is locked, or another user is on its screen
    /// (`LockPolicy.decide`).
    case macLocked
}
