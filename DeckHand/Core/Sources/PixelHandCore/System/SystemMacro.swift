//
//  SystemMacro.swift
//  PixelHandCore
//
//  System-level actions that can't be done with a posted keyboard shortcut.
//  Mission Control, Show Desktop and Launchpad are symbolic hot keys, and
//  `CGEvent` posts never fire those.
//
//  Protocol 2 sends these typed (`SystemMessage.run(action:)`, encoded by
//  their raw value). Protocol 1 sent string ids through `macroButton(id:)`,
//  and the remote had sent several spellings of the same action over time
//  (`showdesktop`, `shortcut-showdesktop`, `*_trigger`), so Show Desktop and
//  Launchpad once did nothing. `init(macroID:)` still resolves every old
//  spelling, for importing old decks and settings.
//

import Foundation

public enum SystemMacro: String, CaseIterable, Codable, Sendable, Hashable {
    case locateCursor
    case missionControl
    case appExpose
    case showDesktop
    case launchpad

    /// The protocol 1 id for this action.
    public var macroID: String {
        switch self {
        case .locateCursor:   "locate_cursor"
        case .missionControl: "missioncontrol_trigger"
        case .appExpose:      "expose_trigger"
        case .showDesktop:    "showdesktop_trigger"
        case .launchpad:      "launchpad_trigger"
        }
    }

    /// Resolves any protocol 1 id for a system action, or `nil` for ids
    /// that aren't system actions (apps, shortcuts, media).
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
        case "launchpad_trigger", "launchpad", "shortcut-launchpad":
            self = .launchpad
        default:
            return nil
        }
    }
}
