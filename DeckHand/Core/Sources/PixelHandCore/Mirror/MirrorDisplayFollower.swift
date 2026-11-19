//
//  MirrorDisplayFollower.swift
//  PixelHandCore
//
//  The remote's display picker: which display the mirror shows, "Follow
//  cursor", and the "Cursor is on <display>" badge. The cursor's display
//  arrives with every `MirrorCursorState`.
//

import Foundation

/// What the mirror's display chrome should show right now.
public struct MirrorDisplayChrome: Equatable, Sendable {
    /// Show the picker (more than one display).
    public var showsPicker: Bool
    /// The display the pointer is on, when that isn't the mirrored one and
    /// "Follow cursor" is off. `nil`: no badge.
    public var cursorElsewhere: DisplayInfo?

    public init(showsPicker: Bool, cursorElsewhere: DisplayInfo?) {
        self.showsPicker = showsPicker
        self.cursorElsewhere = cursorElsewhere
    }

    public static func make(
        displays: [DisplayInfo],
        mirroredDisplayID: UInt32?,
        cursorDisplayID: UInt32?,
        followsCursor: Bool,
        mirroringWindow: Bool = false
    ) -> MirrorDisplayChrome {
        var elsewhere: DisplayInfo?
        // S14: a window mirror says whether the pointer is over the
        // window (the cursor layer), not which display it is on.
        if !followsCursor, !mirroringWindow,
           let cursorDisplayID, cursorDisplayID != 0,
           let mirroredDisplayID, cursorDisplayID != mirroredDisplayID {
            elsewhere = displays.first { $0.displayID == cursorDisplayID }
        }
        return MirrorDisplayChrome(showsPicker: displays.count > 1, cursorElsewhere: elsewhere)
    }
}

/// "Follow cursor": switch the mirror to the display the pointer is on once
/// it has stayed there for `dwell` seconds, and not more often than every
/// `cooldown` seconds, so a pointer swept across a display edge doesn't
/// restart the stream twice.
public struct MirrorDisplayFollower: Sendable {
    public static let dwell = 0.35
    public static let cooldown = 1.0

    private var candidate: UInt32?
    private var candidateSince: Double = 0
    private var lastSwitchAt: Double = -.infinity

    public init() {}

    public mutating func reset() {
        candidate = nil
        lastSwitchAt = -.infinity
    }

    /// Feed the pointer's display at time `now` (seconds). Returns the
    /// display to switch the mirror to, or `nil` to stay.
    public mutating func update(
        cursorDisplayID: UInt32,
        mirroredDisplayID: UInt32?,
        knownDisplayIDs: Set<UInt32>,
        now: Double
    ) -> UInt32? {
        guard cursorDisplayID != 0,
              cursorDisplayID != mirroredDisplayID,
              knownDisplayIDs.contains(cursorDisplayID) else {
            candidate = nil
            return nil
        }
        if candidate != cursorDisplayID {
            candidate = cursorDisplayID
            candidateSince = now
        }
        guard now - candidateSince >= Self.dwell,
              now - lastSwitchAt >= Self.cooldown else { return nil }
        lastSwitchAt = now
        candidate = nil
        return cursorDisplayID
    }
}
