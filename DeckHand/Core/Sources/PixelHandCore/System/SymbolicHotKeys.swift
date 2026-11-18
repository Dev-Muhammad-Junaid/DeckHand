//
//  SymbolicHotKeys.swift
//  PixelHandCore
//
//  The Mac's "symbolic hot keys": the system shortcuts in System Settings ›
//  Keyboard › Keyboard Shortcuts (Mission Control, App Exposé, Show
//  Desktop, Launchpad / Apps, moving between Spaces). The window server
//  matches them on posted key events too, so the Mac app reads the user's
//  real binding with SkyLight's `CGSGetSymbolicHotKeyValue` /
//  `CGSIsSymbolicHotKeyEnabled` and posts that chord (S7), instead of
//  asking System Events through `osascript`.
//
//  This file is the pure part, tested on Linux:
//
//  - the hot key ids and Apple's default bindings;
//  - which hot keys can stand for each action, in order of preference;
//  - `SymbolicHotKeyResolver`, which turns a read of the table (or no read,
//    when the private calls are missing) into what to post.
//
//  The Mac part (reading, temporarily switching on and restoring, posting)
//  is `DeckHandMac/SymbolicHotKeys.swift` and `SystemActionTrigger.swift`.
//
//  Ids and defaults are those of `com.apple.symbolichotkeys`, as macOS 14
//  to 27 ship them. Modifiers are the window server's stored signature:
//  `CGEventFlags` bits, where arrow and F keys always carry fn (0x800000).
//

import Foundation

/// One of the Mac's symbolic hot keys, by its id in `com.apple.symbolichotkeys`.
public enum SymbolicHotKey: Int32, CaseIterable, Sendable {
    /// Mission Control: ⌃↑.
    case missionControl = 32
    /// Application windows (App Exposé): ⌃↓.
    case applicationWindows = 33
    /// Show Desktop: F11.
    case showDesktop = 36
    /// Move left a Space: ⌃←.
    case moveLeftSpace = 79
    /// Move right a Space: ⌃→.
    case moveRightSpace = 81
    /// The Mission Control key (virtual key 160) on Apple keyboards.
    case missionControlKey = 108
    /// ⌘ + the Mission Control key: Show Desktop.
    case showDesktopKey = 110
    /// ⌃ + the Mission Control key: application windows.
    case applicationWindowsKey = 115
    /// Show Launchpad, "Show Apps" on macOS 26 and later. Unbound and off
    /// by default.
    case showLaunchpad = 160
    /// The Launchpad key (virtual key 131) on Apple keyboards.
    case launchpadKey = 173

    /// Virtual key code and `CGEventFlags` raw modifiers.
    public struct Chord: Equatable, Hashable, Sendable, CustomStringConvertible {
        public let keyCode: UInt16
        public let modifiers: UInt32

        public init(keyCode: UInt16, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// For logs, for example "⌃ fn key 126".
        public var description: String {
            var parts: [String] = []
            if modifiers & SymbolicHotKey.control != 0 { parts.append("⌃") }
            if modifiers & SymbolicHotKey.option != 0 { parts.append("⌥") }
            if modifiers & SymbolicHotKey.shift != 0 { parts.append("⇧") }
            if modifiers & SymbolicHotKey.command != 0 { parts.append("⌘") }
            if modifiers & SymbolicHotKey.function != 0 { parts.append("fn") }
            parts.append("key \(keyCode)")
            return parts.joined(separator: " ")
        }
    }

    /// `keyCode` that marks a hot key with no key assigned.
    public static let unboundKeyCode: UInt16 = 0xFFFF

    // CGEventFlags raw values.
    public static let shift: UInt32 = 0x0002_0000
    public static let control: UInt32 = 0x0004_0000
    public static let option: UInt32 = 0x0008_0000
    public static let command: UInt32 = 0x0010_0000
    public static let numericPad: UInt32 = 0x0020_0000
    public static let function: UInt32 = 0x0080_0000

    /// The modifier bits a stored hot key may carry. Anything else in a
    /// read value (device-dependent bits) is dropped before posting.
    public static let modifierMask: UInt32 = shift | control | option | command | numericPad | function

    /// Apple's default binding, as macOS ships it, or `nil` for a hot key
    /// with none (Show Launchpad).
    public var defaultChord: Chord? {
        switch self {
        case .missionControl: Chord(keyCode: 126, modifiers: Self.control | Self.function)
        case .applicationWindows: Chord(keyCode: 125, modifiers: Self.control | Self.function)
        case .showDesktop: Chord(keyCode: 103, modifiers: Self.function)
        case .moveLeftSpace: Chord(keyCode: 123, modifiers: Self.control | Self.function)
        case .moveRightSpace: Chord(keyCode: 124, modifiers: Self.control | Self.function)
        case .missionControlKey: Chord(keyCode: 160, modifiers: Self.function)
        case .showDesktopKey: Chord(keyCode: 160, modifiers: Self.command | Self.function)
        case .applicationWindowsKey: Chord(keyCode: 160, modifiers: Self.control | Self.function)
        case .showLaunchpad: nil
        case .launchpadKey: Chord(keyCode: 131, modifiers: Self.function)
        }
    }

    /// Bound for a moment when the hot key has no key: Apple's default, or
    /// for Show Launchpad (which has none) ⌃⌥⇧⌘F19, which nothing else on a
    /// Mac uses. Never ⌘Space, never a bare key.
    public var fallbackChord: Chord {
        defaultChord ?? Chord(keyCode: 80, modifiers: Self.control | Self.option | Self.shift | Self.command)
    }

    /// The chord to post: the user's binding, or the fallback when the hot
    /// key has none.
    public func chord(boundKeyCode: UInt16?, boundModifiers: UInt32) -> (chord: Chord, needsTemporaryBinding: Bool) {
        if let boundKeyCode, HotKeyBinding.isBound(boundKeyCode) {
            return (Chord(keyCode: boundKeyCode, modifiers: boundModifiers & Self.modifierMask), false)
        }
        return (fallbackChord, true)
    }

    /// The hot key a system action switches on when the user has every one
    /// of its shortcuts off. `nil` for Locate.
    public init?(_ macro: SystemMacro) {
        guard let action = HotKeyAction(macro) else { return nil }
        self = action.primary
    }
}

/// One hot key as read from the window server.
public struct HotKeyBinding: Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    /// Raw `CGEventFlags` bits as stored; see `chord` for the cleaned value.
    public var modifiers: UInt32
    public var isEnabled: Bool

    public init(keyCode: UInt16, modifiers: UInt32, isEnabled: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }

    /// A key is assigned. Virtual key codes are below 0x100; 0xFFFF means
    /// none, and anything else out of range is treated as none too.
    public var isBound: Bool { Self.isBound(keyCode) }

    /// The chord to post, with only the modifier bits a hot key can carry.
    public var chord: SymbolicHotKey.Chord {
        SymbolicHotKey.Chord(keyCode: keyCode, modifiers: modifiers & SymbolicHotKey.modifierMask)
    }

    static func isBound(_ keyCode: UInt16) -> Bool {
        keyCode != SymbolicHotKey.unboundKeyCode && keyCode < 0x100
    }
}

/// What a remote asks for, independent of which hot key does it.
public enum HotKeyAction: String, CaseIterable, Sendable {
    case missionControl
    case applicationWindows
    case showDesktop
    case launchpad
    case previousSpace
    case nextSpace

    /// Hot keys that do this action, most preferred first. The keyboard's
    /// dedicated keys (160, 131) come first where they exist: their chords
    /// bind nothing else, while ⌃ fn arrow is also stored for the window
    /// tiling shortcuts macOS 15 added. Moving between Spaces has no
    /// dedicated key.
    public var candidates: [SymbolicHotKey] {
        switch self {
        case .missionControl: [.missionControlKey, .missionControl]
        case .applicationWindows: [.applicationWindowsKey, .applicationWindows]
        case .showDesktop: [.showDesktop, .showDesktopKey]
        case .launchpad: [.launchpadKey, .showLaunchpad]
        case .previousSpace: [.moveLeftSpace]
        case .nextSpace: [.moveRightSpace]
        }
    }

    /// The hot key switched on for a moment when the user has every
    /// candidate off: the one named in Keyboard Shortcuts.
    public var primary: SymbolicHotKey {
        switch self {
        case .missionControl: .missionControl
        case .applicationWindows: .applicationWindows
        case .showDesktop: .showDesktop
        case .launchpad: .showLaunchpad
        case .previousSpace: .moveLeftSpace
        case .nextSpace: .moveRightSpace
        }
    }

    public init?(_ macro: SystemMacro) {
        switch macro {
        case .missionControl: self = .missionControl
        case .appExpose: self = .applicationWindows
        case .showDesktop: self = .showDesktop
        case .launchpad: self = .launchpad
        case .locateCursor: return nil
        }
    }

    public init?(_ direction: SpaceDirection) {
        switch direction {
        case .previous: self = .previousSpace
        case .next: self = .nextSpace
        case .missionControl: self = .missionControl
        }
    }
}

/// What the Mac should post for an action.
public enum HotKeyResolution: Equatable, Sendable {
    /// The user's own binding: on and bound. Post it as is.
    case post(SymbolicHotKey, SymbolicHotKey.Chord)
    /// The private calls are missing on this macOS, so nothing could be
    /// read: post Apple's default chord and hope the user kept it.
    case postDefault(SymbolicHotKey, SymbolicHotKey.Chord)
    /// Every candidate is off or unbound: switch `hotKey` on (binding
    /// `chord` first when `needsBinding`) for a moment, post, then put the
    /// user's setting back.
    case enableTemporarily(SymbolicHotKey, SymbolicHotKey.Chord, needsBinding: Bool)

    public var hotKey: SymbolicHotKey {
        switch self {
        case let .post(key, _), let .postDefault(key, _), let .enableTemporarily(key, _, _): key
        }
    }

    public var chord: SymbolicHotKey.Chord {
        switch self {
        case let .post(_, chord), let .postDefault(_, chord), let .enableTemporarily(_, chord, _): chord
        }
    }
}

public enum SymbolicHotKeyResolver {
    /// Decides what to post for `action`.
    ///
    /// - Parameter table: what the window server returned for each hot key
    ///   that could be read, or `nil` when the private calls are missing.
    ///   A hot key absent from a non-nil table couldn't be read; it counts
    ///   as off and unbound.
    public static func resolve(
        _ action: HotKeyAction,
        table: [SymbolicHotKey: HotKeyBinding]?
    ) -> HotKeyResolution {
        guard let table else {
            // Nothing readable: the first candidate with an Apple default.
            let key = action.candidates.first { $0.defaultChord != nil } ?? action.primary
            return .postDefault(key, key.fallbackChord)
        }
        for key in action.candidates {
            if let binding = table[key], binding.isEnabled, binding.isBound {
                return .post(key, binding.chord)
            }
        }
        let primary = action.primary
        let stored = table[primary]
        let (chord, needsBinding) = primary.chord(
            boundKeyCode: stored?.keyCode,
            boundModifiers: stored?.modifiers ?? 0
        )
        return .enableTemporarily(primary, chord, needsBinding: needsBinding)
    }

    /// Every hot key the Mac needs to read for `action`.
    public static func hotKeysToRead(for action: HotKeyAction) -> [SymbolicHotKey] {
        var keys = action.candidates
        if !keys.contains(action.primary) { keys.append(action.primary) }
        return keys
    }
}
