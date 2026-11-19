//
//  SystemActionPlan.swift
//  PixelHandCore
//
//  Which ways the Mac tries, in order, to run Mission Control, App Exposé,
//  Show Desktop and Launchpad / Apps. The Mac app runs them
//  (`SystemActionTrigger`); the order lives here so it can be unit-tested.
//  Which symbolic hot key the `symbolicHotKey` mechanism posts is decided
//  by `SymbolicHotKeyResolver` (SymbolicHotKeys.swift).
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
    /// Reads the action's symbolic hot keys with the private CGS calls and
    /// posts the user's own binding; if every one is off, turns one on (or
    /// binds a spare chord) for a moment. With the calls missing, posts
    /// Apple's default chord. See `SymbolicHotKeyResolver`.
    case symbolicHotKey
    /// `CoreDockSendNotification`, the private call the Dock listens on.
    case dockNotification
    /// The keyboard's dedicated keys: ⌘ + Mission Control key for Show
    /// Desktop, the Launchpad key for Launchpad / Apps.
    case dedicatedKey
    /// `Mission Control.app/Contents/MacOS/Mission Control 1` (macOS 26
    /// and earlier).
    case missionControlBinary
    /// `open -a Launchpad`, or `Apps` on macOS 26 (macOS 26 and earlier);
    /// `open -a "Mission Control"` for Mission Control (every macOS).
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
        case .missionControl: "PixelHandMissionControlMechanism"
        case .appExpose: "PixelHandAppExposeMechanism"
        case .locateCursor: nil
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

    public static func defaultMechanisms(for macro: SystemMacro, macOSMajor: Int) -> [SystemActionMechanism] {
        let legacy = macOSMajor <= 26
        switch macro {
        case .showDesktop:
            return [.symbolicHotKey, .dockNotification, .dedicatedKey]
                + (legacy ? [.missionControlBinary] : [])
                + [.systemEventsKey]
        case .launchpad:
            // `open -a` is the known-good path on 14 and 15, and the only
            // one tried on 26 so far, so it stays first there.
            return (legacy ? [.openApp] : [])
                + [.symbolicHotKey, .dedicatedKey, .dockNotification]
        case .missionControl:
            // The user's own shortcut (S7), then Mission Control.app, which
            // still opens on macOS 27 (build 1, checked on the owner's Mac).
            return [.symbolicHotKey, .openApp]
        case .appExpose:
            // No app or Dock notification opens App Exposé. The old System
            // Events path needed the Automation prompt; it is gone (S7).
            return [.symbolicHotKey]
        case .locateCursor:
            return []
        }
    }

    /// Parses an override such as "dockNotification" or
    /// "symbolicHotKey, dedicatedKey". Unknown names are skipped.
    public static func parse(_ override: String?) -> [SystemActionMechanism]? {
        guard let override, !override.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return override
            .split(separator: ",")
            .compactMap { SystemActionMechanism(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }
}
