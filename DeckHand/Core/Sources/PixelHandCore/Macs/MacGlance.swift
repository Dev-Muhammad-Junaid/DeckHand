//
//  MacGlance.swift
//  PixelHandCore – Multi-Mac
//
//  The glance tier of a Mac card (UX-030, backlog M1): what a person can
//  read about a Mac without switching to it. The focused Mac's glance is
//  live (its session reports the front app, the lock state and the link);
//  the others show the last glance their session left, with its age.
//

import Foundation

/// What a Mac card shows at a glance.
public struct MacGlance: Codable, Equatable, Sendable {
    /// The Mac's frontmost app, as its session last reported it.
    public var frontApp: String?
    /// The Mac's lock state (S8), `nil` before the Mac said.
    public var lockState: MacLockState?
    /// The link the session ran over (S13 / S15).
    public var link: LinkKind?
    /// When this glance was taken.
    public var updatedAt: Date

    public init(frontApp: String? = nil, lockState: MacLockState? = nil, link: LinkKind? = nil, updatedAt: Date) {
        self.frontApp = frontApp
        self.lockState = lockState
        self.link = link
        self.updatedAt = updatedAt
    }

    public var isLocked: Bool { lockState?.isLocked ?? false }

    /// Whether two glances say the same thing (the time aside), so a
    /// session that reports the same state again doesn't rewrite storage.
    public func sameContent(as other: MacGlance?) -> Bool {
        guard let other else { return false }
        return frontApp == other.frontApp && lockState == other.lockState && link == other.link
    }
}

/// The card's second line and badges, from the listing's facts.
public enum MacGlanceCopy {
    /// "Xcode", "Locked", "Connecting…", "Nearby · last used Safari",
    /// "Not found · seen 3 h ago".
    public static func statusLine(for listing: MacListing, now: Date) -> String {
        if listing.isActive {
            if listing.glance?.isLocked == true { return "Locked" }
            return listing.glance?.frontApp ?? "Connected"
        }
        if listing.isConnecting { return "Connecting…" }
        guard listing.isReachable else {
            guard let seen = listing.glance?.updatedAt ?? listing.lastUsedAt else { return "Not found" }
            return "Not found · seen \(age(from: seen, to: now))"
        }
        let place = listing.isNearby ? "Nearby" : "Remote"
        if let glance = listing.glance {
            if glance.isLocked { return "\(place) · was locked" }
            if let app = glance.frontApp { return "\(place) · last in \(app)" }
        }
        return listing.isPaired ? "\(place) · paired" : place
    }

    /// "just now", "5 min ago", "3 h ago", "2 d ago".
    public static func age(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3600)) h ago"
        default: return "\(Int(seconds / 86_400)) d ago"
        }
    }

    /// The ⌘ chord for a shortcut slot, for cards and help: "⌘1".
    public static func chord(slot: Int) -> String { "⌘\(slot)" }
}
