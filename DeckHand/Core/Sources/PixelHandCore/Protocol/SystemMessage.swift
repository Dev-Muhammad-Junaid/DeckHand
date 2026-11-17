//
//  SystemMessage.swift
//  PixelHandCore
//
//  Domain: system. Mac-wide actions that aren't a key chord: Mission
//  Control, App Exposé, Show Desktop, Launchpad / Apps, Locate, and moving
//  between Spaces. Remote → Mac. Owned by the Mac system control lane
//  (`SystemHandler`): symbolic hot keys, display wake, the locked-Mac gate
//  and the Spaces monitor add their messages here.
//

import Foundation

public enum SystemMessage: Codable, Sendable, Equatable {
    /// Run a system action. Replaces version 1's `macroButton(id:)`, whose
    /// string ids drifted between remote and host.
    case run(action: SystemMacro)
    /// Switch Mission Control Space on a display. The host moves the
    /// pointer onto `displayID` first so the switch lands on that monitor.
    /// `nil` means the display under the pointer.
    case switchSpace(direction: SpaceDirection, displayID: UInt32?)
}
