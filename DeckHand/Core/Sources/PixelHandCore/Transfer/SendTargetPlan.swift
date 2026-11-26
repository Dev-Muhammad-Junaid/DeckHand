//
//  SendTargetPlan.swift
//  PixelHandCore – Transfer
//
//  The Send sheet's "Send to" list (owner testing, build 26, OT-9). Each
//  paired Mac is a compact device card with its live state: ready, sending
//  (with progress), busy (locked, or sending to this device), connecting,
//  items waiting for it, in reach, or offline. Offline Macs don't get a
//  full card: they sit small and muted under the others with "seen 2 h
//  ago", most recently seen first. Cards keep the roster order (the ⌘1–4
//  order), so switching Macs never reshuffles the list.
//
//  The views only draw what this returns. Spec: `07-Polish-Spec.md`,
//  "Send sheet".
//

import Foundation

/// Why a Mac can't take a send right now, though it is connected.
public enum SendTargetBusy: Equatable, Sendable {
    /// Locked and away from its console: it refuses incoming transfers
    /// until someone unlocks it (`LockPolicy.allowsIncomingTransfer`).
    case locked
    /// Sending to this device right now.
    case receiving(count: Int)
}

/// A send target's live state.
public enum SendTargetState: Equatable, Sendable {
    /// The focused Mac: a tap sends now.
    case ready
    /// Items are moving to it. `fraction` is by bytes across them; `nil`
    /// while they wait for the Mac's Accept.
    case sending(count: Int, fraction: Double?)
    case busy(SendTargetBusy)
    /// Being dialled by a switch.
    case connecting
    /// Not focused, with items queued for it; they go when you switch.
    case waiting(count: Int)
    /// Not focused but reachable; a send queues until you switch.
    case inReach(nearby: Bool)
    /// Not reachable. `lastSeen` is its last glance or use.
    case offline(lastSeen: Date?)

    /// Offline targets are drawn small and muted.
    public var isCompact: Bool {
        if case .offline = self { return true }
        return false
    }

    /// The status light: lit only while the Mac is talking (`06-Pixel-
    /// Identity.md` §5, "Disconnected").
    public var light: Light {
        switch self {
        case .ready, .sending: .live
        case .busy: .needsYou
        case .connecting, .waiting, .inReach, .offline: .off
        }
    }

    public enum Light: Equatable, Sendable {
        case live, needsYou, off
    }
}

/// One card in the "Send to" list.
public struct SendTarget: Equatable, Sendable, Identifiable {
    public let listing: MacListing
    public let state: SendTargetState

    public init(listing: MacListing, state: SendTargetState) {
        self.listing = listing
        self.state = state
    }

    public var id: UUID { listing.deviceID }

    /// The line under the name.
    public func statusLine(now: Date) -> String {
        SendTargetCopy.statusLine(for: state, now: now)
    }

    /// The dot-matrix readout at the card's trailing edge: `42%` while
    /// sending, the count of waiting items; `nil` otherwise.
    public var readout: String? {
        switch state {
        case let .sending(_, fraction?):
            return "\(TransferPanelPlan.percent(fraction))%"
        case let .waiting(count):
            return "\(count)"
        default:
            return nil
        }
    }

    /// What VoiceOver reads for the card.
    public func spoken(now: Date) -> String {
        "\(listing.name), \(statusLine(now: now))"
    }
}

public enum SendTargetPlan {
    /// One outbox item, as the list cares.
    public struct Outgoing: Equatable, Sendable {
        /// The Mac it's for; `nil` for "the next Mac that connects", which
        /// is the focused Mac while one is connected.
        public var targetDeviceID: UUID?
        /// Offered or moving bytes on the current connection.
        public var isMoving: Bool
        public var bytes: UInt64
        public var totalBytes: UInt64

        public init(targetDeviceID: UUID?, isMoving: Bool, bytes: UInt64 = 0, totalBytes: UInt64 = 0) {
            self.targetDeviceID = targetDeviceID
            self.isMoving = isMoving
            self.bytes = bytes
            self.totalBytes = totalBytes
        }
    }

    /// The list: full cards for every Mac that can take a send now or
    /// later in roster order, and the offline ones apart, most recently
    /// seen first (never seen last, then by roster order).
    ///
    /// - Parameters:
    ///   - listings: `MacSwitcher.listings` (roster order).
    ///   - outgoing: the outbox.
    ///   - incomingCount: transfers arriving now from the focused Mac.
    public static func targets(
        listings: [MacListing],
        outgoing: [Outgoing],
        incomingCount: Int = 0
    ) -> (cards: [SendTarget], offline: [SendTarget]) {
        let shown = listings.filter { $0.isPaired || $0.isActive }
        let activeID = shown.first(where: \.isActive)?.deviceID
        var cards: [SendTarget] = []
        var offline: [(target: SendTarget, order: Int)] = []
        for (order, listing) in shown.enumerated() {
            let mine = outgoing.filter { ($0.targetDeviceID ?? activeID) == listing.deviceID }
            let state = state(for: listing, outgoing: mine, incomingCount: listing.isActive ? incomingCount : 0)
            let target = SendTarget(listing: listing, state: state)
            if state.isCompact {
                offline.append((target, order))
            } else {
                cards.append(target)
            }
        }
        let sortedOffline = offline.sorted { a, b in
            let seenA = lastSeen(a.target.listing)
            let seenB = lastSeen(b.target.listing)
            switch (seenA, seenB) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.order < b.order
            }
        }
        return (cards, sortedOffline.map(\.target))
    }

    /// One Mac's state.
    public static func state(for listing: MacListing, outgoing: [Outgoing], incomingCount: Int = 0) -> SendTargetState {
        if listing.isActive {
            let moving = outgoing.filter(\.isMoving)
            if !moving.isEmpty {
                return .sending(count: moving.count, fraction: fraction(moving))
            }
            if listing.glance?.isLocked == true { return .busy(.locked) }
            if incomingCount > 0 { return .busy(.receiving(count: incomingCount)) }
            if !outgoing.isEmpty { return .sending(count: outgoing.count, fraction: nil) }
            return .ready
        }
        if listing.isConnecting { return .connecting }
        guard listing.isReachable else { return .offline(lastSeen: lastSeen(listing)) }
        if !outgoing.isEmpty { return .waiting(count: outgoing.count) }
        return .inReach(nearby: listing.isNearby)
    }

    /// Done by bytes across `items`; `nil` while nothing has moved or the
    /// sizes are unknown (still waiting for the Mac's Accept).
    static func fraction(_ items: [Outgoing]) -> Double? {
        let total = items.reduce(UInt64(0)) { $0 + $1.totalBytes }
        let done = items.reduce(UInt64(0)) { $0 + min($1.bytes, $1.totalBytes) }
        guard total > 0, done > 0 else { return nil }
        return min(1, Double(done) / Double(total))
    }

    static func lastSeen(_ listing: MacListing) -> Date? {
        listing.glance?.updatedAt ?? listing.lastUsedAt
    }
}

/// The words on the cards. Relative times come from `MacGlanceCopy.age`,
/// so a Mac reads "seen 2 h ago" the same here as in My Macs.
public enum SendTargetCopy {
    public static func statusLine(for state: SendTargetState, now: Date) -> String {
        switch state {
        case .ready:
            return "Ready"
        case let .sending(count, fraction):
            let what = count == 1 ? "Sending" : "Sending \(count)"
            guard let fraction else { return count == 1 ? "Waiting to accept" : "\(count) waiting to accept" }
            return "\(what) · \(TransferPanelPlan.percent(fraction)) %"
        case .busy(.locked):
            return "Locked · unlock to receive"
        case let .busy(.receiving(count)):
            return count == 1 ? "Busy · sending you 1 item" : "Busy · sending you \(count) items"
        case .connecting:
            return "Connecting…"
        case let .waiting(count):
            return "\(count) waiting · switch to send"
        case let .inReach(nearby):
            return nearby ? "Nearby · switch to send" : "Remote · switch to send"
        case let .offline(lastSeen):
            return offlineLine(lastSeen: lastSeen, now: now)
        }
    }

    /// "Seen 2 h ago", or "Offline" when it was never seen.
    public static func offlineLine(lastSeen: Date?, now: Date) -> String {
        guard let lastSeen else { return "Offline" }
        return "Seen \(MacGlanceCopy.age(from: lastSeen, to: now))"
    }
}
