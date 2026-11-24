//
//  ControlSessionModel+MultiMac.swift
//  DeckHandiOS
//
//  The Multi-Mac lane's part of the session model (UX-030): which Mac this
//  session drives and its glance (front app, lock state, link) for the Mac
//  cards. No stored state and no message handling: the glance is read from
//  what the other lanes' cases already keep, and `MacSessionGlance` hands
//  it to `MacSwitcher`. One model per connection, one message loop.
//

import Foundation

extension ControlSessionModel {
    /// The Loom device ID of the Mac this session drives.
    var macDeviceID: UUID { connection.peer.deviceID }

    /// The glance tier of this Mac's card.
    var macGlance: MacGlance {
        MacGlance(
            frontApp: activeAppName,
            lockState: macLockState,
            link: link == .unknown ? nil : link,
            updatedAt: Date()
        )
    }
}
