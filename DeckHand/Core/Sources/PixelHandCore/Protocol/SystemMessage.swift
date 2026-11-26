//
//  SystemMessage.swift
//  PixelHandCore
//
//  Domain: system. Mac-wide actions that aren't a key chord: Mission
//  Control, App Exposé, Show Desktop, Launchpad / Apps, Locate, and moving
//  between Spaces (remote → Mac); and what the Mac reports about its
//  displays, Spaces and lock screen (Mac → remote). Owned by the Mac system
//  control lane (`SystemHandler`, `SpacesMonitor`, `LockState`).
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
    /// Start (`true`) or stop following the Mac's focused text field
    /// (OT-12, the Type panel's loupe). While on, the Mac sends
    /// `focusState` when the focus, the field, the caret or the pointer
    /// changes, at most about eight times a second. Stopped by `false` and
    /// by disconnecting. Protocol 16.
    case watchFocus(on: Bool)

    // MARK: Mac → remote

    /// The displays, their Spaces and the pointer's display. Sent when a
    /// remote connects, when the active Space or the display arrangement
    /// changes, when the pointer crosses to another display, and after a
    /// refused `switchSpace`. See `DisplayLayout`.
    case displayState(layout: DisplayLayout)
    /// Whether the Mac is locked. Sent when a remote connects and on every
    /// change. While locked the Mac refuses most requests
    /// (`LockPolicy.decide`); the remote says why.
    case lockState(state: MacLockState)
    /// The focused text field, its caret and the pointer, to a remote that
    /// asked with `watchFocus(on: true)`. While the Mac is locked it sends
    /// one `.none` snapshot and nothing more until the unlock; text only
    /// ever comes from native, non-secure fields. See
    /// `FocusedFieldSnapshot`. Protocol 16.
    case focusState(focus: FocusedFieldSnapshot)
}
