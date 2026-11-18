//
//  DisplayWakePolicy.swift
//  PixelHandCore
//
//  When the Mac tells macOS that someone is using it (S8 display wake), so
//  a sleeping display turns on and the mirror isn't black. The Mac declares
//  user activity (`IOPMAssertionDeclareUserActivity`, what a key press at
//  the Mac does) when a remote connects and when a person at the remote
//  does something, at most once every `minimumInterval`. Nothing is held:
//  the display sleeps again by the Mac's own setting, counted from the last
//  declaration. Messages a remote sends by itself (pings, list requests,
//  mirror restarts) never count.
//
//  Behaviour re-implemented from Sill's documented display-wake rule.
//

import Foundation

public enum DisplayWakeTrigger: String, Sendable, Equatable {
    /// An approved remote's session started.
    case connected
    /// A person at the remote sent input or ran something.
    case personAction
}

public enum DisplayWakePolicy {
    /// Least time between two declarations for person actions.
    public static let minimumInterval: TimeInterval = 5

    /// Whether `message` is something a person did at the remote, as
    /// opposed to traffic the remote sends by itself.
    public static func isPersonAction(_ message: ControlMessage) -> Bool {
        switch message {
        case .input:
            return true
        case let .system(m):
            switch m {
            case .run, .switchSpace: return true
            case .displayState, .lockState: return false
            }
        case let .apps(m):
            switch m {
            case .launchApp, .appShortcut, .triggerContextAction: return true
            default: return false
            }
        case let .deck(m):
            if case .run = m { return true }
            return false
        case let .capture(m):
            if case .requestScreenshot = m { return true }
            return false
        case .mirror, .pairing, .session, .sharing, .diagnostics:
            return false
        }
    }
}

/// Rate limit and lock rules for declarations. One per Mac.
public struct DisplayWakeThrottle: Sendable, Equatable {
    public private(set) var lastDeclared: Date?

    public init() {}

    /// Whether to declare activity now; records it when `true`.
    ///
    /// - Off console: never (it would light the console for another user).
    /// - Screen locked: only for a person's action the lock gate let
    ///   through (typing the password), never for a connection.
    /// - Connections declare whatever the interval; actions at most once
    ///   every `DisplayWakePolicy.minimumInterval`.
    public mutating func shouldDeclare(
        _ trigger: DisplayWakeTrigger,
        lock: MacLockState,
        at now: Date
    ) -> Bool {
        switch lock {
        case .offConsole:
            return false
        case .screenLocked where trigger == .connected:
            return false
        default:
            break
        }
        if trigger == .personAction, let lastDeclared,
           now.timeIntervalSince(lastDeclared) < DisplayWakePolicy.minimumInterval,
           now >= lastDeclared {
            return false
        }
        lastDeclared = now
        return true
    }
}
