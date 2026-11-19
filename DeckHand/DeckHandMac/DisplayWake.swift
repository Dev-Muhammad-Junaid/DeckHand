//
//  DisplayWake.swift
//  DeckHandMac
//
//  Wakes a sleeping display when someone uses the Mac from a remote (S8),
//  so the mirror and screenshots aren't black. It tells macOS a user is
//  active, as a key press at the Mac does
//  (`IOPMAssertionDeclareUserActivity` with `kIOPMUserActiveLocal`, public
//  IOKit, the declaration `caffeinate -u` makes). Nothing is held: the
//  display sleeps again by the Mac's own setting, counted from the last
//  declaration. It wakes a display, never a Mac that is asleep, and can't
//  light a closed laptop's display.
//
//  When to declare (connections, person actions at most every 5 s, the
//  lock rules) is Core's `DisplayWakeThrottle`.
//

import CoreGraphics
import Foundation
import IOKit.pwr_mgt

@MainActor
final class DisplayWake {
    static let shared = DisplayWake()

    private var throttle = DisplayWakeThrottle()
    private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var lastLogged: Date?

    private static let assertionName = "Pixel Hand: a remote is using this Mac" as CFString

    private init() {}

    /// Declares user activity for `trigger` if the policy allows it now.
    func note(_ trigger: DisplayWakeTrigger, lock: MacLockState) {
        let now = Date()
        guard throttle.shouldDeclare(trigger, lock: lock, at: now) else { return }
        let wasAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        // Passing the previous id back extends that declaration instead of
        // creating a new one each time.
        let result = IOPMAssertionDeclareUserActivity(Self.assertionName, kIOPMUserActiveLocal, &assertionID)
        guard result == kIOReturnSuccess else {
            DeckHandLog.input.error("Display wake: IOPMAssertionDeclareUserActivity failed (\(result, privacy: .public))")
            return
        }
        if wasAsleep {
            DeckHandLog.input.info("Display wake: woke the display for a remote, which \(trigger == .connected ? "connected" : "sent input", privacy: .public)")
        } else if lastLogged.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            lastLogged = now
            DeckHandLog.input.debug("Display wake: declared user activity (\(trigger.rawValue, privacy: .public))")
        }
    }
}
