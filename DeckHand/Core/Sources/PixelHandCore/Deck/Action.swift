//
//  Action.swift
//  PixelHandCore
//
//  One typed thing a remote asks the Mac to do: what a shortcut chip, a
//  dialog chip, a deck key or (later) an App Intent runs. An action is sent
//  in a `DeckMessage.run`, and the Mac answers with a receipt.
//
//  Every action maps to exactly one fire-and-forget domain message
//  (`message`), and the Mac runs a tracked action through the same handler
//  as that message, so there is one code path per command.
//

import Foundation

public enum Action: Codable, Sendable, Equatable, Hashable {
    /// Post a key chord to the frontmost app.
    case shortcut(keys: [String])
    /// Activate `bundleID`, wait for it, then post `keys`.
    case appShortcut(bundleID: String, keys: [String])
    /// Launch or activate an app.
    case launchApp(bundleID: String)
    /// A Mac-wide action (Mission Control, Show Desktop, …).
    case system(action: SystemMacro)
    /// A media key.
    case media(key: MediaKey)
    /// Press a dialog button from the latest `uiContextUpdate`.
    case contextAction(id: String)

    /// The untracked message that does the same thing.
    public var message: ControlMessage {
        switch self {
        case let .shortcut(keys): .input(.keyboardShortcut(keys: keys))
        case let .appShortcut(bundleID, keys): .apps(.appShortcut(bundleID: bundleID, keys: keys))
        case let .launchApp(bundleID): .apps(.launchApp(bundleID: bundleID))
        case let .system(action): .system(.run(action: action))
        case let .media(key): .input(.media(key: key))
        case let .contextAction(id): .apps(.triggerContextAction(id: id))
        }
    }

    /// Whether the Mac needs Accessibility to run this. All of today's
    /// actions post events or press AX elements, so all of them do.
    public var needsAccessibility: Bool { true }
}

/// What became of a tracked `Action`.
public enum ActionOutcome: Codable, Sendable, Equatable, Hashable {
    /// The Mac received it and handed it to input injection. Slow actions
    /// (`appShortcut`, dialog presses) finish afterwards in their own tasks,
    /// so this confirms delivery, not the app's result.
    case delivered
    /// The Mac received it and won't run it.
    case refused(reason: RefusalReason)
    /// The Mac tried and it failed.
    case failed(reason: String)
    /// The Mac ran it to the end (for actions that can report completion,
    /// such as a future Mac Shortcut run).
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
}
