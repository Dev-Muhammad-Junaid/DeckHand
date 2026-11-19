//
//  Entitlement.swift
//  PixelHandCore
//
//  Whether this device has Pixel Hand Pro, worked out from what StoreKit 2
//  reports. The iOS app copies the StoreKit values it reads into the plain
//  facts below, so every rule is tested on Linux:
//
//  - `Transaction.currentEntitlements` → `SubscriptionFact` (one per active
//    subscription: this Apple Account's own, or one shared by the family).
//  - `Product.SubscriptionInfo.status` → `SubscriptionStatusFact` (the
//    renewal state, which is the only place the grace and billing-retry
//    periods show up).
//
//  Rules:
//
//  - Only verified transactions for this app's two product IDs count; the
//    app drops the rest before calling `resolve`.
//  - A revoked (refunded) or upgraded transaction never entitles.
//  - An active subscription in its free trial is `.trial`, otherwise
//    `.active`.
//  - The grace period and the billing-retry period both count as Pro
//    (owner decision): Apple is still trying to collect, and locking a
//    paying customer out over a card problem costs more than it saves.
//  - When several apply (your own plan plus one shared by your family), the
//    best one wins: active or trial, then grace, then billing retry.
//  - Nothing active: `.expired` if a subscription existed, else
//    `.notSubscribed`.
//

import Foundation

/// One active subscription transaction, from `Transaction.currentEntitlements`
/// or a status's latest transaction.
public struct SubscriptionFact: Equatable, Sendable {
    public var plan: SubscriptionPlan
    public var purchaseDate: Date
    /// When the current period ends. Every auto-renewable transaction has one.
    public var expirationDate: Date?
    /// Set when Apple refunded or revoked the purchase.
    public var revocationDate: Date?
    /// The person moved to the other plan; the newer transaction counts.
    public var isUpgraded: Bool
    /// The current period is the introductory free trial.
    public var isFreeTrial: Bool
    /// A family member's subscription, shared through Family Sharing.
    public var isFamilyShared: Bool

    public init(
        plan: SubscriptionPlan,
        purchaseDate: Date,
        expirationDate: Date?,
        revocationDate: Date? = nil,
        isUpgraded: Bool = false,
        isFreeTrial: Bool = false,
        isFamilyShared: Bool = false
    ) {
        self.plan = plan
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.isFreeTrial = isFreeTrial
        self.isFamilyShared = isFamilyShared
    }

    /// Whether this transaction entitles at `now` on its own.
    func isLive(at now: Date) -> Bool {
        guard revocationDate == nil, !isUpgraded else { return false }
        guard let expirationDate else { return true }
        return expirationDate > now
    }
}

/// The renewal state StoreKit reports for one subscription in the group.
public enum SubscriptionRenewalState: String, Codable, Sendable {
    case subscribed
    case expired
    case inGracePeriod
    case inBillingRetryPeriod
    case revoked
}

/// One entry of `Product.SubscriptionInfo.status`.
public struct SubscriptionStatusFact: Equatable, Sendable {
    public var state: SubscriptionRenewalState
    /// The subscription's latest transaction.
    public var transaction: SubscriptionFact
    /// From the renewal info: whether the subscription renews at the end of
    /// the period. `nil` when the renewal info couldn't be verified.
    public var willAutoRenew: Bool?
    /// The plan it renews to, when the person switched plans for the next
    /// period.
    public var autoRenewPlan: SubscriptionPlan?
    /// When the grace period ends, while in one.
    public var gracePeriodExpirationDate: Date?

    public init(
        state: SubscriptionRenewalState,
        transaction: SubscriptionFact,
        willAutoRenew: Bool? = nil,
        autoRenewPlan: SubscriptionPlan? = nil,
        gracePeriodExpirationDate: Date? = nil
    ) {
        self.state = state
        self.transaction = transaction
        self.willAutoRenew = willAutoRenew
        self.autoRenewPlan = autoRenewPlan
        self.gracePeriodExpirationDate = gracePeriodExpirationDate
    }
}

/// What this device may use, and why.
public struct Entitlement: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// StoreKit hasn't answered yet and nothing was cached.
        case unknown
        /// The last answer was Pro until `until`; shown while StoreKit
        /// answers after launch, so a subscriber never sees locks flash.
        case cached(until: Date)
        /// Never subscribed (or nothing for this app on this account).
        case notSubscribed
        /// In the free trial; it ends (and billing starts, if it renews)
        /// on `endsOn`.
        case trial(plan: SubscriptionPlan, endsOn: Date?, willRenew: Bool?)
        /// Paid and current.
        case active(plan: SubscriptionPlan, periodEnds: Date?, willRenew: Bool?, renewsTo: SubscriptionPlan?, familyShared: Bool)
        /// Renewal failed; Apple keeps retrying and Pro stays on until
        /// `until`.
        case gracePeriod(plan: SubscriptionPlan, until: Date?)
        /// Renewal failed after any grace period; Apple keeps retrying for
        /// up to 60 days. Counts as Pro (owner decision).
        case billingRetry(plan: SubscriptionPlan)
        /// A subscription existed and has ended.
        case expired(on: Date?)
        /// Refunded or revoked by Apple.
        case revoked
    }

    public var status: Status
    /// When this was worked out; a `.cached` status stops counting after
    /// its date, measured against this.
    public var evaluatedAt: Date

    public init(status: Status, evaluatedAt: Date) {
        self.status = status
        self.evaluatedAt = evaluatedAt
    }

    /// Before StoreKit answers and with nothing cached.
    public static let unknown = Entitlement(status: .unknown, evaluatedAt: .distantPast)

    /// Every Pro feature is unlocked.
    public var isPro: Bool {
        switch status {
        case .trial, .active, .gracePeriod, .billingRetry:
            true
        case let .cached(until):
            until > evaluatedAt
        case .unknown, .notSubscribed, .expired, .revoked:
            false
        }
    }

    /// Whether `feature` is unlocked.
    public func allows(_ feature: ProFeature) -> Bool {
        feature.tier == .free || isPro
    }

    /// The plan behind a Pro status, if StoreKit named one.
    public var plan: SubscriptionPlan? {
        switch status {
        case let .trial(plan, _, _), let .active(plan, _, _, _, _),
             let .gracePeriod(plan, _), let .billingRetry(plan):
            plan
        case .unknown, .cached, .notSubscribed, .expired, .revoked:
            nil
        }
    }

    /// Whether StoreKit has answered (the status isn't a placeholder).
    public var isSettled: Bool {
        switch status {
        case .unknown, .cached: false
        default: true
        }
    }

    // MARK: - Resolving

    /// Works out the entitlement from StoreKit's facts.
    ///
    /// - Parameters:
    ///   - entitlements: verified `Transaction.currentEntitlements` for this
    ///     app's products.
    ///   - statuses: verified `Product.SubscriptionInfo.status` entries for
    ///     the group (empty when they couldn't be fetched, for example
    ///     offline).
    ///   - hadSubscription: whether any transaction for these products was
    ///     ever seen (`Transaction.all`), so an ended plan reads "expired"
    ///     rather than "not subscribed".
    public static func resolve(
        entitlements: [SubscriptionFact],
        statuses: [SubscriptionStatusFact],
        hadSubscription: Bool = false,
        now: Date
    ) -> Entitlement {
        var candidates: [Status] = []

        for status in statuses {
            let fact = status.transaction
            switch status.state {
            case .subscribed:
                // A stale "subscribed" whose period has passed doesn't count
                // on its own; a fresh transaction in `entitlements` will.
                if fact.isLive(at: now) {
                    candidates.append(liveStatus(fact, willRenew: status.willAutoRenew, renewsTo: status.autoRenewPlan))
                }
            case .inGracePeriod:
                guard fact.revocationDate == nil else { continue }
                if let end = status.gracePeriodExpirationDate, end <= now { continue }
                candidates.append(.gracePeriod(plan: fact.plan, until: status.gracePeriodExpirationDate))
            case .inBillingRetryPeriod:
                guard fact.revocationDate == nil else { continue }
                candidates.append(.billingRetry(plan: fact.plan))
            case .expired, .revoked:
                continue
            }
        }

        // `currentEntitlements` works offline and right after a purchase,
        // before the status API catches up.
        for fact in entitlements where fact.isLive(at: now) {
            let renewal = statuses.first { $0.transaction.plan == fact.plan && $0.transaction.isFamilyShared == fact.isFamilyShared }
            candidates.append(liveStatus(fact, willRenew: renewal?.willAutoRenew, renewsTo: renewal?.autoRenewPlan))
        }

        if let best = candidates.min(by: { rank($0) < rank($1) }) {
            return Entitlement(status: best, evaluatedAt: now)
        }

        // Nothing entitles. The most recent purchase says whether it ended
        // by refund or by running out.
        let allFacts = entitlements + statuses.map(\.transaction)
        let latest = statuses.max { $0.transaction.purchaseDate < $1.transaction.purchaseDate }
        if latest?.state == .revoked || latest?.transaction.revocationDate != nil {
            return Entitlement(status: .revoked, evaluatedAt: now)
        }
        if latest == nil, let fact = entitlements.max(by: { $0.purchaseDate < $1.purchaseDate }), fact.revocationDate != nil {
            return Entitlement(status: .revoked, evaluatedAt: now)
        }
        if !allFacts.isEmpty || hadSubscription {
            let ended = allFacts.compactMap(\.expirationDate).filter { $0 <= now }.max()
            return Entitlement(status: .expired(on: ended), evaluatedAt: now)
        }
        return Entitlement(status: .notSubscribed, evaluatedAt: now)
    }

    private static func liveStatus(_ fact: SubscriptionFact, willRenew: Bool?, renewsTo: SubscriptionPlan?) -> Status {
        if fact.isFreeTrial {
            return .trial(plan: fact.plan, endsOn: fact.expirationDate, willRenew: willRenew)
        }
        return .active(
            plan: fact.plan,
            periodEnds: fact.expirationDate,
            willRenew: willRenew,
            renewsTo: renewsTo == fact.plan ? nil : renewsTo,
            familyShared: fact.isFamilyShared
        )
    }

    /// Lower is better. Own plans beat shared ones, then paid beats trial
    /// (a person who bought during their trial sees their purchase), then
    /// the later end date.
    private static func rank(_ status: Status) -> (Int, Int, TimeInterval) {
        switch status {
        case let .active(_, ends, _, _, shared):
            (0, shared ? 1 : 0, -(ends?.timeIntervalSince1970 ?? .greatestFiniteMagnitude))
        case let .trial(_, ends, _):
            (1, 0, -(ends?.timeIntervalSince1970 ?? .greatestFiniteMagnitude))
        case let .gracePeriod(_, until):
            (2, 0, -(until?.timeIntervalSince1970 ?? .greatestFiniteMagnitude))
        case .billingRetry:
            (3, 0, 0)
        case .unknown, .cached, .notSubscribed, .expired, .revoked:
            (9, 0, 0)
        }
    }
}
