//
//  FreeMacPolicy.swift
//  PixelHandCore
//
//  The free plan's "one Mac" rule.
//
//  Which Mac is the free one:
//
//  - The first Mac this device connects to becomes the free Mac, whatever
//    the plan at the time.
//  - While Pro is on (trial included), the free Mac follows the Mac used
//    most recently, so when Pro ends the free Mac is the one the person was
//    just using. Pro itself never limits Macs.
//  - Without Pro, the free Mac stays put. Any other Mac shows the paywall,
//    which also offers "Use this Mac instead".
//
//  Changing it:
//
//  - The first change after the free Mac was picked for you (the first Mac,
//    or the last one used under Pro) is allowed at once, so a person whose
//    first Mac was the wrong one isn't stuck.
//  - After a change you make yourself, the next one is allowed after
//    `switchInterval` (7 days). That keeps one Mac a real limit while still
//    letting someone move to a new Mac.
//
//  Macs are told apart by their Loom device ID, which is what the picker
//  has before it dials. Pairing's trust anchor (the identity key) only
//  exists after the handshake and isn't needed for a display rule.
//

import Foundation

/// The free plan's Mac, as this device remembers it.
public struct FreeMacChoice: Codable, Equatable, Sendable {
    public var deviceID: UUID
    /// The Mac's name when it was last seen, for "Your free Mac is …".
    public var name: String
    /// When the person last changed it themselves. `nil` while it was
    /// picked automatically, which allows the next change at once.
    public var changedByUserAt: Date?

    public init(deviceID: UUID, name: String, changedByUserAt: Date? = nil) {
        self.deviceID = deviceID
        self.name = name
        self.changedByUserAt = changedByUserAt
    }
}

public enum FreeMacPolicy {
    /// How long after a change of free Mac the next one is allowed.
    public static let switchInterval: TimeInterval = 7 * 24 * 60 * 60

    public enum Admission: Equatable, Sendable {
        /// Connect. `choice` is what to remember from now on (unchanged,
        /// recorded for the first time, renamed, or following the Mac in
        /// use under Pro).
        case allowed(choice: FreeMacChoice)
        /// This isn't the free Mac and Pro is off: show the paywall.
        /// `switchAllowedAt` is when "Use this Mac instead" works (now or
        /// earlier means it works now).
        case needsPro(freeMac: FreeMacChoice, switchAllowedAt: Date)
    }

    /// Whether this device may dial the Mac `deviceID`.
    public static func admit(
        deviceID: UUID,
        name: String,
        isPro: Bool,
        choice: FreeMacChoice?,
        now: Date
    ) -> Admission {
        guard let choice else {
            return .allowed(choice: FreeMacChoice(deviceID: deviceID, name: name))
        }
        if choice.deviceID == deviceID {
            var renamed = choice
            renamed.name = name
            return .allowed(choice: renamed)
        }
        if isPro {
            // Follows the Mac in use; picked for the person, not by them.
            return .allowed(choice: FreeMacChoice(deviceID: deviceID, name: name))
        }
        return .needsPro(freeMac: choice, switchAllowedAt: switchAllowedAt(choice))
    }

    /// When the person may next change their free Mac.
    public static func switchAllowedAt(_ choice: FreeMacChoice) -> Date {
        guard let changed = choice.changedByUserAt else { return .distantPast }
        return changed.addingTimeInterval(switchInterval)
    }

    /// "Use this Mac instead". Returns the new choice, or `nil` when the
    /// last change was too recent. A clock set back before the last change
    /// doesn't unlock a change.
    public static func switchFreeMac(
        to deviceID: UUID,
        name: String,
        from choice: FreeMacChoice?,
        now: Date
    ) -> FreeMacChoice? {
        if let choice, choice.deviceID != deviceID {
            if let changed = choice.changedByUserAt, now < changed {
                return nil
            }
            guard now >= switchAllowedAt(choice) else { return nil }
        }
        return FreeMacChoice(deviceID: deviceID, name: name, changedByUserAt: now)
    }
}
