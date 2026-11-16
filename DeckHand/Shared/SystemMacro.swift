//
//  SystemMacro.swift
//  Pixel Hand – Shared
//
//  System-level actions behind `macroButton(id:)` that can't be done with a
//  posted keyboard shortcut. Mission Control, Show Desktop and Launchpad are
//  symbolic hot keys, and `CGEvent` posts never fire those.
//
//  The remote has sent several spellings of the same action over time
//  (`showdesktop` from the Quick Actions bar, `shortcut-showdesktop` as the
//  `MacroItem` id, `*_trigger` for the newer buttons). The host used to
//  match only some of them, so Show Desktop from the Quick Actions bar did
//  nothing. Every spelling now resolves here, before the default-deck
//  lookup.
//

import Foundation

public enum SystemMacro: String, CaseIterable, Sendable {
    case locateCursor
    case missionControl
    case appExpose
    case showDesktop
    case launchpad

    /// The id the remote should send for this action.
    public var macroID: String {
        switch self {
        case .locateCursor:   "locate_cursor"
        case .missionControl: "missioncontrol_trigger"
        case .appExpose:      "expose_trigger"
        case .showDesktop:    "showdesktop_trigger"
        case .launchpad:      "launchpad_trigger"
        }
    }

    /// Resolves any id a remote may send for a system action, or `nil` for
    /// ids that aren't system actions (apps, shortcuts, media).
    public init?(macroID id: String) {
        switch id {
        case "locate_cursor":
            self = .locateCursor
        case "missioncontrol_trigger", "missioncontrol", "shortcut-missioncontrol":
            self = .missionControl
        case "expose_trigger":
            self = .appExpose
        case "showdesktop_trigger", "showdesktop", "shortcut-showdesktop":
            self = .showDesktop
        case "launchpad_trigger":
            self = .launchpad
        default:
            return nil
        }
    }
}
