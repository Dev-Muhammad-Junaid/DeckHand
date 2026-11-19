//
//  EntitlementCache.swift
//  PixelHandCore
//
//  The last Pro answer, kept on the device so a subscriber doesn't see
//  locks flash for the second StoreKit takes to answer after launch.
//
//  The cache only ever unlocks, and only until the date StoreKit gave: the
//  end of the paid period or trial, the end of a grace period, or (when
//  StoreKit gave no date, as in billing retry) `undatedValidity` from when
//  it was written. StoreKit's answer always replaces it. It's a display
//  convenience, not a purchase record: deleting it costs a subscriber one
//  second of locks, never their subscription.
//

import Foundation

public struct EntitlementCache: Codable, Equatable, Sendable {
    /// How long a Pro answer without an end date is trusted.
    public static let undatedValidity: TimeInterval = 3 * 24 * 60 * 60

    /// Pro until this date.
    public var proUntil: Date

    public init(proUntil: Date) {
        self.proUntil = proUntil
    }

    /// What to store after StoreKit answered: a cache for a Pro answer,
    /// `nil` (clear it) for anything else. Placeholder statuses change
    /// nothing, so they return the cache they were given.
    public static func updated(_ current: EntitlementCache?, from entitlement: Entitlement) -> EntitlementCache? {
        guard entitlement.isSettled else { return current }
        guard entitlement.isPro else { return nil }
        let now = entitlement.evaluatedAt
        let dated: Date? = switch entitlement.status {
        case let .trial(_, endsOn, _): endsOn
        case let .active(_, periodEnds, _, _, _): periodEnds
        case let .gracePeriod(_, until): until
        default: nil
        }
        if let dated, dated > now {
            return EntitlementCache(proUntil: dated)
        }
        return EntitlementCache(proUntil: now.addingTimeInterval(undatedValidity))
    }

    /// The entitlement to show before StoreKit answers.
    public static func provisional(_ cache: EntitlementCache?, now: Date) -> Entitlement {
        guard let cache, cache.proUntil > now else {
            return Entitlement(status: .unknown, evaluatedAt: now)
        }
        return Entitlement(status: .cached(until: cache.proUntil), evaluatedAt: now)
    }
}
