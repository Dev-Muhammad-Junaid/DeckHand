//
//  RemoteCommand.swift
//  PixelHandCore
//
//  What an App Intent, a widget button or a Control Center control asks
//  the remote to do (D6, roadmap 1.2). The intents themselves live in the
//  iOS app (`DeckHandiOS/Intents`); this is the pure part: which commands
//  exist, which plan each one needs, how each maps onto the existing
//  `Action` / message paths, and the limits on what an intent may carry.
//
//  Nothing new goes on the wire: a command becomes a `deck.run` of an
//  `Action` (keys, system actions, media), `input.typeText`, a capture
//  request or a mirror start/stop the app already sends.
//

import Foundation

/// One thing Siri, Shortcuts, Spotlight, a widget or a control asks the
/// remote to do on the connected Mac.
public enum RemoteCommand: Codable, Sendable, Equatable, Hashable {
    /// Run the deck key with this `DeckKey.id`.
    case runKey(keyID: String)
    /// A Mac-wide action: Mission Control, Show Desktop, Lock Screen, …
    case system(SystemCommand)
    /// Play/pause, next or previous track.
    case media(MediaKey)
    /// Type `text` on the Mac, as the keyboard panel does.
    case typeText(String)
    /// Take a screenshot of the Mac's screen and show it on the remote.
    case screenshot
    /// Start, stop or toggle the live mirror.
    case mirror(MirrorIntentMode)
    /// Bring the remote to the front on one of its surfaces.
    case open(RemoteSurface)

    /// The feature this command is gated on (`ProFeature`). Typing, the
    /// system actions and media keys are free (they are what the keyboard
    /// and trackpad do anyway, as in the Store lane's gating); deck keys,
    /// screenshots and the mirror are Pro.
    public var feature: ProFeature {
        switch self {
        case .runKey: .decks
        case .system: .keyboard
        case .media: .mediaKeys
        case .typeText: .keyboard
        case .screenshot: .capture
        case .mirror: .mirror
        case .open: .trackpad
        }
    }

    /// Whether `entitlement` lets this command run.
    public func isAllowed(by entitlement: Entitlement) -> Bool {
        entitlement.allows(feature)
    }

    /// Whether running it needs a live connection to a Mac. Only opening a
    /// surface doesn't.
    public var needsConnection: Bool {
        if case .open = self { return false }
        return true
    }

    /// A short, payload-free name for logs (never the typed text).
    public var kindName: String {
        switch self {
        case .runKey: "runKey"
        case let .system(command): "system.\(command.rawValue)"
        case let .media(key): "media.\(key.rawValue)"
        case .typeText: "typeText"
        case .screenshot: "screenshot"
        case let .mirror(mode): "mirror.\(mode.rawValue)"
        case let .open(surface): "open.\(surface.rawValue)"
        }
    }

    /// The `Action` a tracked run sends, for the commands that are one.
    /// `runKey` resolves through the deck (`DeckDocument.key(id:)`), so it
    /// is `nil` here, as are typing, capture, the mirror and opening.
    public var action: Action? {
        switch self {
        case let .system(command): command.action
        case let .media(key): .media(key: key)
        case .runKey, .typeText, .screenshot, .mirror, .open: nil
        }
    }

    /// Why a command can't be accepted as given, or `nil` when it can.
    public var validationIssue: RemoteCommandIssue? {
        switch self {
        case let .runKey(keyID):
            if keyID.isEmpty || keyID.utf8.count > RemoteCommandLimits.maxKeyIDBytes { return .badKeyID }
        case let .typeText(text):
            if text.isEmpty { return .emptyText }
            if text.count > RemoteCommandLimits.maxTypedCharacters { return .textTooLong }
        default:
            break
        }
        return nil
    }
}

/// Why `RemoteCommand.validationIssue` refused a command.
public enum RemoteCommandIssue: String, Sendable, Equatable {
    case badKeyID
    case emptyText
    case textTooLong
}

/// Bounds on what an intent can carry.
public enum RemoteCommandLimits {
    /// Same bound as deck IDs (`DeckValidation`).
    public static let maxKeyIDBytes = 512
    /// A Shortcuts "Type text" step can carry a paragraph or two; anything
    /// longer is a paste, not typing. `TextChunker` splits it on the wire.
    public static let maxTypedCharacters = 2_000
}

/// The Mac-wide actions an intent or control can run. Each is one existing
/// `Action`, so it runs through `deck.run` like a deck key would.
public enum SystemCommand: String, Codable, Sendable, CaseIterable, Hashable {
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case locateCursor
    /// Lock the Mac's screen (⌃⌘Q, the system shortcut).
    case lockScreen

    /// The action that runs it.
    public var action: Action {
        switch self {
        case .missionControl: .system(action: .missionControl)
        case .appExpose: .system(action: .appExpose)
        case .showDesktop: .system(action: .showDesktop)
        case .launchpad: .system(action: .launchpad)
        case .locateCursor: .system(action: .locateCursor)
        case .lockScreen: .shortcut(keys: ["ctrl", "cmd", "q"])
        }
    }

    /// The name Shortcuts, Siri and the controls show.
    public var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Launchpad"
        case .locateCursor: "Find the Pointer"
        case .lockScreen: "Lock Screen"
        }
    }

    /// The `PixelGlyphs` name drawn for it.
    public var glyphName: String {
        switch self {
        case .missionControl, .appExpose: "mission"
        case .showDesktop: "desktop"
        case .launchpad: "deck"
        case .locateCursor: "pointer"
        case .lockScreen: "lock"
        }
    }

    /// An SF Symbol for places that only take symbols (Control Center).
    public var symbolName: String {
        switch self {
        case .missionControl: "rectangle.3.group"
        case .appExpose: "rectangle.stack"
        case .showDesktop: "menubar.dock.rectangle"
        case .launchpad: "square.grid.3x3"
        case .locateCursor: "cursorarrow.rays"
        case .lockScreen: "lock"
        }
    }
}

/// What a mirror intent does.
public enum MirrorIntentMode: String, Codable, Sendable, CaseIterable, Hashable {
    case start
    case stop
    case toggle

    /// Whether the mirror should change, given whether it's running.
    public func shouldToggle(isRunning: Bool) -> Bool {
        switch self {
        case .start: !isRunning
        case .stop: isRunning
        case .toggle: true
        }
    }
}

/// A remote surface an intent or control can open.
public enum RemoteSurface: String, Codable, Sendable, CaseIterable, Hashable {
    case trackpad
    case deck
    case screen
}
