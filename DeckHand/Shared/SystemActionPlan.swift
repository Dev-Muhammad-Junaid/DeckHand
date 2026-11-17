//
//  SystemActionPlan.swift
//  Pixel Hand – Shared
//
//  Which ways the Mac tries, in order, to show the desktop or open
//  Launchpad / Apps. The Mac app runs them (`SystemActionTrigger`); the
//  order lives here so it can be unit-tested.
//
//  None of these can tell whether the Dock actually reacted, so the Mac uses
//  the first mechanism that is able to run (its private symbol exists, a
//  hot key could be set up, and so on). The order puts the mechanisms that
//  don't depend on the user's own shortcut settings first.
//
//  macOS 27 broke the old paths: `Mission Control 1` is a silent no-op (run
//  by hand it exits 137), and `open -a Apps` logs "Asking CSUI to launch
//  0 items". Those stay only on the systems where they worked.
//

import Foundation

public enum SystemActionMechanism: String, CaseIterable, Sendable {
    /// Reads the action's symbolic hot key with the private CGS calls, turns
    /// it on (or binds a spare chord) for a moment if the user has it off,
    /// and posts the chord. Works whatever the user's own binding is.
    case symbolicHotKey
    /// `CoreDockSendNotification`, the private call the Dock listens on.
    case dockNotification
    /// The keyboard's dedicated keys: ⌘ + Mission Control key for Show
    /// Desktop, the Launchpad key for Launchpad / Apps.
    case dedicatedKey
    /// `Mission Control.app/Contents/MacOS/Mission Control 1` (macOS 26
    /// and earlier).
    case missionControlBinary
    /// `open -a Launchpad`, or `Apps` on macOS 26 (macOS 26 and earlier).
    case openApp
    /// System Events `key code 103` (F11). Needs the user's Show Desktop
    /// shortcut to be on and set to F11.
    case systemEventsKey
}

public enum SystemActionPlan {
    /// The `UserDefaults` key that forces one mechanism or a comma-separated
    /// list, for testing on a Mac without rebuilding, for example
    /// `defaults write com.widgetsflow.pixelhand.mac PixelHandShowDesktopMechanism dockNotification`.
    public static func overrideKey(for macro: SystemMacro) -> String? {
        switch macro {
        case .showDesktop: "PixelHandShowDesktopMechanism"
        case .launchpad: "PixelHandLaunchpadMechanism"
        default: nil
        }
    }

    /// The mechanisms to try for `macro`, in order. Empty for actions that
    /// don't go through this plan.
    public static func mechanisms(
        for macro: SystemMacro,
        macOSMajor: Int,
        override: String? = nil
    ) -> [SystemActionMechanism] {
        let defaults = defaultMechanisms(for: macro, macOSMajor: macOSMajor)
        guard !defaults.isEmpty else { return [] }
        if let forced = parse(override), !forced.isEmpty {
            return forced
        }
        return defaults
    }

    static func defaultMechanisms(for macro: SystemMacro, macOSMajor: Int) -> [SystemActionMechanism] {
        let legacy = macOSMajor <= 26
        switch macro {
        case .showDesktop:
            return [.symbolicHotKey, .dockNotification, .dedicatedKey]
                + (legacy ? [.missionControlBinary] : [])
                + [.systemEventsKey]
        case .launchpad:
            return [.openApp]
        default:
            return []
        }
    }

    /// Parses an override such as "dockNotification" or
    /// "symbolicHotKey, dedicatedKey". Unknown names are skipped.
    static func parse(_ override: String?) -> [SystemActionMechanism]? {
        guard let override, !override.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return override
            .split(separator: ",")
            .compactMap { SystemActionMechanism(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// Symbolic hot key ids from `com.apple.symbolichotkeys` and the chord the
/// Mac binds for a moment when the user has none.
public enum SymbolicHotKey: Int32, Sendable {
    case showDesktop = 36
    case showLaunchpad = 160

    /// Virtual key code and `CGEventFlags` raw modifiers.
    public struct Chord: Equatable, Sendable {
        public let keyCode: UInt16
        public let modifiers: UInt32
    }

    /// `keyCode` that marks a hot key with no key assigned.
    public static let unboundKeyCode: UInt16 = 0xFFFF

    // CGEventFlags raw values.
    static let shift: UInt32 = 0x0002_0000
    static let control: UInt32 = 0x0004_0000
    static let option: UInt32 = 0x0008_0000
    static let command: UInt32 = 0x0010_0000
    static let function: UInt32 = 0x0080_0000

    /// Used only when the hot key has no key. Show Desktop gets Apple's
    /// default (fn F11). Launchpad has no default, so it gets ⌃⌥⇧⌘F19,
    /// which nothing else on a Mac uses.
    public var fallbackChord: Chord {
        switch self {
        case .showDesktop:
            Chord(keyCode: 103, modifiers: Self.function)
        case .showLaunchpad:
            Chord(keyCode: 80, modifiers: Self.control | Self.option | Self.shift | Self.command)
        }
    }

    /// The chord to post: the user's binding, or the fallback when the hot
    /// key has none.
    public func chord(boundKeyCode: UInt16?, boundModifiers: UInt32) -> (chord: Chord, needsTemporaryBinding: Bool) {
        if let boundKeyCode, boundKeyCode != Self.unboundKeyCode {
            return (Chord(keyCode: boundKeyCode, modifiers: boundModifiers), false)
        }
        return (fallbackChord, true)
    }

    /// The hot key behind a system action, if it has one.
    public init?(_ macro: SystemMacro) {
        switch macro {
        case .showDesktop: self = .showDesktop
        case .launchpad: self = .showLaunchpad
        default: return nil
        }
    }
}
