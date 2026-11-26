//
//  Action.swift
//  PixelHandCore
//
//  One typed thing a remote asks the Mac to do: what a shortcut chip, a
//  dialog chip, a deck key or (later) an App Intent runs. An action is sent
//  in a `DeckMessage.run`, and the Mac answers with a receipt.
//
//  The first six cases each map to exactly one fire-and-forget domain
//  message (`message`), and the Mac runs a tracked one through the same
//  handler as that message, so there is one code path per command. The
//  Deck 2 cases (`menuCommand`, `macShortcut`, `sequence`) exist only as
//  tracked runs: `message` is `nil` for them and `DeckHandler` runs them.
//  `typeText` (protocol 15, OT-8) stands for `input.typeText`, so a key
//  types through the same path as Live typing and Ask.
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
    /// Deck 2: press the menu item at `path` in `bundleID`'s menu bar
    /// through Accessibility, for example `["File", "Export", "PDF…"]`.
    /// Works when the user rebinds the item's shortcut, or it has none.
    /// Titles are matched by `MenuPath.matches`.
    case menuCommand(bundleID: String, path: [String])
    /// Deck 2: run the Shortcuts.app shortcut called `name` on the Mac
    /// (`shortcuts run`), bounded by `MacShortcutRun.timeout`.
    case macShortcut(name: String)
    /// Deck 2: a macro. Runs `steps` in order, at most
    /// `ActionLimits.maxSequenceSteps`. A step can't be another sequence:
    /// `SequenceStep` refuses one while decoding, so hostile JSON can't
    /// nest them.
    case sequence(steps: [SequenceStep])
    /// Protocol 15 (OT-8): type `text` into the app in front, as
    /// `input.typeText` does for Live typing, Compose and Ask. `\n` presses
    /// Return and `\t` Tab; other control characters are refused
    /// (`ActionValidation`). At most `TypingPolicy.maxMessageBytes`. A key
    /// that types always asks first (`DeckKey.asksFirst`).
    case typeText(text: String)

    /// The untracked message that does the same thing, or `nil` for the
    /// Deck 2 actions, which only run tracked (`DeckMessage.run`).
    public var message: ControlMessage? {
        switch self {
        case let .shortcut(keys): .input(.keyboardShortcut(keys: keys))
        case let .appShortcut(bundleID, keys): .apps(.appShortcut(bundleID: bundleID, keys: keys))
        case let .launchApp(bundleID): .apps(.launchApp(bundleID: bundleID))
        case let .system(action): .system(.run(action: action))
        case let .media(key): .input(.media(key: key))
        case let .contextAction(id): .apps(.triggerContextAction(id: id))
        case let .typeText(text): .input(.typeText(text: text))
        case .menuCommand, .macShortcut, .sequence: nil
        }
    }

    /// Whether the Mac needs Accessibility to run this. Everything posts
    /// events or presses AX elements except a Shortcuts run, and a sequence
    /// needs it when any step does.
    public var needsAccessibility: Bool {
        switch self {
        case .macShortcut: false
        case let .sequence(steps): steps.contains { $0.action?.needsAccessibility ?? false }
        default: true
        }
    }

    /// A short, payload-free name for logs and receipts.
    public var kindName: String {
        switch self {
        case .shortcut: "shortcut"
        case .appShortcut: "appShortcut"
        case .launchApp: "launchApp"
        case .system: "system"
        case .media: "media"
        case .contextAction: "contextAction"
        case .menuCommand: "menuCommand"
        case .macShortcut: "macShortcut"
        case .sequence: "sequence"
        case .typeText: "typeText"
        }
    }
}

/// One step of a `sequence`: an action, or a pause.
public enum SequenceStep: Codable, Sendable, Equatable, Hashable {
    /// Run `action`. Never a `sequence` (refused when decoding, and by
    /// `ActionValidation`).
    case run(action: Action)
    /// Wait `milliseconds` before the next step, at most
    /// `ActionLimits.maxDelayMilliseconds`.
    case delay(milliseconds: Int)

    public var action: Action? {
        if case let .run(action) = self { return action }
        return nil
    }

    // Synthesised coding, except that a nested sequence is refused before
    // it is decoded, so the decoder's depth stays bounded.
    private enum CodingKeys: String, CodingKey { case run, delay }
    private enum RunKeys: String, CodingKey { case action }
    private enum DelayKeys: String, CodingKey { case milliseconds }
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "A sequence step has exactly one kind."))
        }
        switch key {
        case .run:
            let run = try container.nestedContainer(keyedBy: RunKeys.self, forKey: .run)
            let probe = try run.nestedContainer(keyedBy: AnyKey.self, forKey: .action)
            if probe.contains(AnyKey(stringValue: "sequence")) {
                throw DecodingError.dataCorrupted(.init(codingPath: probe.codingPath, debugDescription: "A sequence can't contain a sequence."))
            }
            self = .run(action: try run.decode(Action.self, forKey: .action))
        case .delay:
            let delay = try container.nestedContainer(keyedBy: DelayKeys.self, forKey: .delay)
            self = .delay(milliseconds: try delay.decode(Int.self, forKey: .milliseconds))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .run(action):
            var run = container.nestedContainer(keyedBy: RunKeys.self, forKey: .run)
            try run.encode(action, forKey: .action)
        case let .delay(milliseconds):
            var delay = container.nestedContainer(keyedBy: DelayKeys.self, forKey: .delay)
            try delay.encode(milliseconds, forKey: .milliseconds)
        }
    }
}

// MARK: - Typing (OT-8)

extension Action {
    /// Whether running this types text on the Mac (itself, or any step of
    /// a sequence).
    public var typesText: Bool {
        switch self {
        case .typeText: true
        case let .sequence(steps): steps.contains { $0.action?.typesText ?? false }
        default: false
        }
    }

    /// Whether running this presses Return in the app in front: typed text
    /// with a line break, a Return chord, or a sequence with either.
    public var pressesReturn: Bool {
        switch self {
        case let .typeText(text): text.contains("\n")
        case let .shortcut(keys), let .appShortcut(_, keys): keys.last.map { ChordParser.canonical($0) } == "return"
        case let .sequence(steps): steps.contains { $0.action?.pressesReturn ?? false }
        default: false
        }
    }
}

extension DeckKey {
    /// Whether tapping the key asks first. A key that types on the Mac
    /// always does, like Ask's plans and the Type panel's Return guard:
    /// text lands in whatever app is in front, so the person confirms the
    /// app before it goes (OT-8). Otherwise "Ask before running".
    public var asksFirst: Bool { confirm || action.typesText }

    /// Why "Ask before running" can't be turned off, or `nil` when it can.
    public var asksFirstLockReason: String? {
        action.typesText ? "Keys that type text always ask first, so the text goes to the app you expect." : nil
    }

    /// The line under "Ask before running" in the key editor (build 28
    /// bug 8): why it's locked on for a key that types, else what it does.
    public var asksFirstFootnote: String {
        asksFirstLockReason ?? "Shows what the key will do and asks before it runs."
    }
}
