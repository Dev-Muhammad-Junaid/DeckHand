//
//  MacRoster.swift
//  PixelHandCore – Multi-Mac
//
//  The list of Macs My Macs, the iPad sidebar, the pill swipe and ⌘1–4
//  share (UX-030, backlog M2). One order everywhere, and a stable one:
//
//  1. Macs this device has used, by first use (a new Mac goes to the end;
//     switching never reorders, so ⌘2 keeps meaning the same Mac).
//  2. Paired Macs not used yet, oldest pairing first.
//  3. Other Macs in reach: the person's own iCloud Macs first, then by name.
//
//  The first `shortcutSlots` Macs get ⌘1–⌘4. Swiping and ⌘` step through
//  the Macs that can be reached now, wrapping around.
//

import Foundation

/// A Mac known from discovery, pairing or memory, before ordering.
public struct MacCandidate: Equatable, Sendable {
    public var deviceID: UUID
    public var name: String
    /// Seen by discovery (Bonjour or a saved VPN host) right now.
    public var isReachable: Bool
    public var isNearby: Bool
    /// Provably the person's own Mac (same iCloud account).
    public var isOwnICloud: Bool

    public init(deviceID: UUID, name: String, isReachable: Bool = true, isNearby: Bool = true, isOwnICloud: Bool = false) {
        self.deviceID = deviceID
        self.name = name
        self.isReachable = isReachable
        self.isNearby = isNearby
        self.isOwnICloud = isOwnICloud
    }
}

/// A paired Mac, as far as ordering cares.
public struct MacPairing: Equatable, Sendable {
    public var deviceID: UUID
    public var name: String
    public var pairedAt: Date

    public init(deviceID: UUID, name: String, pairedAt: Date) {
        self.deviceID = deviceID
        self.name = name
        self.pairedAt = pairedAt
    }
}

/// One row of the Mac list.
public struct MacListing: Equatable, Sendable, Identifiable {
    public let deviceID: UUID
    public var name: String
    /// 1–4 for ⌘1–⌘4, `nil` past the fourth Mac.
    public var slot: Int?
    public var isActive: Bool
    /// Being dialled by a switch.
    public var isConnecting: Bool
    public var isReachable: Bool
    public var isNearby: Bool
    public var isPaired: Bool
    public var isOwnICloud: Bool
    public var lastUsedAt: Date?
    public var glance: MacGlance?

    public var id: UUID { deviceID }

    public init(
        deviceID: UUID,
        name: String,
        slot: Int? = nil,
        isActive: Bool = false,
        isConnecting: Bool = false,
        isReachable: Bool = false,
        isNearby: Bool = false,
        isPaired: Bool = false,
        isOwnICloud: Bool = false,
        lastUsedAt: Date? = nil,
        glance: MacGlance? = nil
    ) {
        self.deviceID = deviceID
        self.name = name
        self.slot = slot
        self.isActive = isActive
        self.isConnecting = isConnecting
        self.isReachable = isReachable
        self.isNearby = isNearby
        self.isPaired = isPaired
        self.isOwnICloud = isOwnICloud
        self.lastUsedAt = lastUsedAt
        self.glance = glance
    }

    /// Whether picking this Mac can do anything now.
    public var canSwitch: Bool { !isActive && (isReachable || isConnecting) }
}

/// Which way a switch moves through the list (the canvas slides with it).
public enum MacSwitchDirection: Equatable, Sendable {
    case forward, backward
}

public enum MacRoster {
    /// ⌘1–⌘4.
    public static let shortcutSlots = 4

    /// The ordered list. `activeDeviceID` is the focused Mac, which counts
    /// as reachable while its session runs.
    public static func listings(
        discovered: [MacCandidate],
        paired: [MacPairing],
        memory: MacMemoryBook,
        activeDeviceID: UUID?,
        connectingDeviceID: UUID? = nil
    ) -> [MacListing] {
        var byID: [UUID: MacListing] = [:]
        var order: [UUID] = []

        func note(_ id: UUID, name: String) {
            if byID[id] == nil {
                byID[id] = MacListing(deviceID: id, name: name)
                order.append(id)
            }
        }

        // 1. Used, by first use.
        for mac in memory.macs.sorted(by: { $0.firstUsedAt < $1.firstUsedAt }) {
            note(mac.deviceID, name: mac.name)
            byID[mac.deviceID]?.lastUsedAt = mac.lastUsedAt
            byID[mac.deviceID]?.glance = mac.glance
        }
        // 2. Paired, oldest pairing first.
        for mac in paired.sorted(by: { $0.pairedAt < $1.pairedAt }) {
            note(mac.deviceID, name: mac.name)
            byID[mac.deviceID]?.isPaired = true
        }
        // 3. Others in reach: own iCloud Macs first, then by name.
        let reachable = discovered.sorted {
            ($0.isOwnICloud ? 0 : 1, $0.name.lowercased(), $0.deviceID.uuidString)
                < ($1.isOwnICloud ? 0 : 1, $1.name.lowercased(), $1.deviceID.uuidString)
        }
        for mac in reachable {
            note(mac.deviceID, name: mac.name)
            guard var listing = byID[mac.deviceID] else { continue }
            // Discovery has the current name.
            if !mac.name.isEmpty { listing.name = mac.name }
            listing.isReachable = listing.isReachable || mac.isReachable
            listing.isNearby = listing.isNearby || mac.isNearby
            listing.isOwnICloud = listing.isOwnICloud || mac.isOwnICloud
            byID[mac.deviceID] = listing
        }
        if let activeDeviceID, byID[activeDeviceID] != nil {
            byID[activeDeviceID]?.isActive = true
            byID[activeDeviceID]?.isReachable = true
        }
        if let connectingDeviceID, connectingDeviceID != activeDeviceID, byID[connectingDeviceID] != nil {
            byID[connectingDeviceID]?.isConnecting = true
        }

        return order.enumerated().compactMap { index, id in
            guard var listing = byID[id] else { return nil }
            listing.slot = index < shortcutSlots ? index + 1 : nil
            return listing
        }
    }

    /// The Mac on shortcut `slot` (⌘1 is 1).
    public static func mac(inSlot slot: Int, of listings: [MacListing]) -> MacListing? {
        listings.first { $0.slot == slot }
    }

    /// The next (`step` 1) or previous (`step` -1) Mac that can be reached,
    /// wrapping around. `nil` when there is no other Mac to go to.
    public static func neighbor(of activeDeviceID: UUID?, step: Int, in listings: [MacListing]) -> MacListing? {
        let candidates = listings.filter { $0.isReachable || $0.isActive || $0.isConnecting }
        guard !candidates.isEmpty, step != 0 else { return nil }
        guard let activeDeviceID, let index = candidates.firstIndex(where: { $0.deviceID == activeDeviceID }) else {
            return step > 0 ? candidates.first : candidates.last
        }
        guard candidates.count > 1 else { return nil }
        let next = ((index + step) % candidates.count + candidates.count) % candidates.count
        return candidates[next]
    }

    /// Which way the canvas slides going from one Mac to another: forward
    /// when the target is later in the list (or there was no Mac).
    public static func direction(from current: UUID?, to target: UUID, in listings: [MacListing]) -> MacSwitchDirection {
        guard let current,
              let from = listings.firstIndex(where: { $0.deviceID == current }),
              let to = listings.firstIndex(where: { $0.deviceID == target })
        else { return .forward }
        return to >= from ? .forward : .backward
    }

    /// Whether three-finger sideways swipes switch Macs: the person's
    /// setting, and only with another Mac to go to. Otherwise the gesture
    /// stays the Mac's Spaces swipe.
    public static func swipeSwitchesMacs(settingOn: Bool, listings: [MacListing]) -> Bool {
        settingOn && listings.filter { $0.isReachable || $0.isActive }.count >= 2
    }
}
