//
//  StoreEntitlementTests.swift
//  PixelHandCoreTests
//
//  The Pixel Hand Pro entitlement: the free/Pro feature map, resolving
//  StoreKit's facts (trial, paid, grace, billing retry, revoked, Family
//  Sharing, upgrades), and the launch cache.
//

import Foundation
import PixelHandCore
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 24 * 60 * 60

private func fact(
    _ plan: SubscriptionPlan = .monthly,
    bought: TimeInterval = -10 * day,
    expires: TimeInterval? = 20 * day,
    revoked: Bool = false,
    upgraded: Bool = false,
    trial: Bool = false,
    shared: Bool = false
) -> SubscriptionFact {
    SubscriptionFact(
        plan: plan,
        purchaseDate: now.addingTimeInterval(bought),
        expirationDate: expires.map { now.addingTimeInterval($0) },
        revocationDate: revoked ? now.addingTimeInterval(-day) : nil,
        isUpgraded: upgraded,
        isFreeTrial: trial,
        isFamilyShared: shared
    )
}

@Suite("Store feature map")
struct StoreFeatureMapTests {
    @Test("Trackpad, keyboard and media keys are free; everything else is Pro")
    func tiers() {
        #expect(ProFeature.allCases.filter { $0.tier == .free } == [.trackpad, .keyboard, .mediaKeys])
        #expect(ProFeature.proFeatures == [.decks, .mirror, .capture, .multipleMacs, .sharing, .ai])
    }

    @Test("A free entitlement allows only free features; Pro allows all")
    func allows() {
        let free = Entitlement(status: .notSubscribed, evaluatedAt: now)
        let pro = Entitlement(status: .active(plan: .yearly, periodEnds: nil, willRenew: true, renewsTo: nil, familyShared: false), evaluatedAt: now)
        for feature in ProFeature.allCases {
            #expect(free.allows(feature) == (feature.tier == .free))
            #expect(pro.allows(feature))
        }
    }

    @Test("Trial, grace and billing retry unlock everything; unknown, expired and revoked don't")
    func proStatuses() {
        let unlocked: [Entitlement.Status] = [
            .trial(plan: .monthly, endsOn: nil, willRenew: nil),
            .gracePeriod(plan: .monthly, until: nil),
            .billingRetry(plan: .yearly),
            .cached(until: now.addingTimeInterval(60)),
        ]
        let locked: [Entitlement.Status] = [
            .unknown, .notSubscribed, .expired(on: nil), .revoked, .cached(until: now.addingTimeInterval(-1)),
        ]
        for status in unlocked {
            #expect(Entitlement(status: status, evaluatedAt: now).isPro, "\(status)")
        }
        for status in locked {
            #expect(!Entitlement(status: status, evaluatedAt: now).isPro, "\(status)")
        }
    }

    @Test("Product IDs and plans round-trip")
    func productIDs() {
        #expect(SubscriptionPlan.productIDs == ["com.widgetsflow.pixelhand.pro.monthly", "com.widgetsflow.pixelhand.pro.yearly"])
        #expect(SubscriptionPlan(productID: "com.widgetsflow.pixelhand.pro.yearly") == .yearly)
        #expect(SubscriptionPlan(productID: "com.widgetsflow.pixelhand.pro.lifetime") == nil)
        #expect(SubscriptionPlan.groupName == "Pixel Hand Pro")
        #expect(SubscriptionPlan.freeTrialDays == 14)
    }

    @Test("Yearly saves 44% against twelve months, rounded down")
    func savings() {
        #expect(SubscriptionPricing.yearlySavingsPercent(monthly: SubscriptionPlan.monthly.fallbackPrice, yearly: SubscriptionPlan.yearly.fallbackPrice) == 44)
        #expect(SubscriptionPricing.yearlySavingsPercent(monthly: 1, yearly: 12) == nil)
        #expect(SubscriptionPricing.yearlySavingsPercent(monthly: 1, yearly: 13) == nil)
        #expect(SubscriptionPricing.yearlySavingsPercent(monthly: 0, yearly: 1) == nil)
        #expect(SubscriptionPlan.monthly.fallbackDisplayPrice == "$2.99")
        #expect(SubscriptionPlan.yearly.fallbackDisplayPrice == "$19.99")
    }
}

@Suite("Store entitlement resolution")
struct StoreEntitlementResolutionTests {
    @Test("Nothing at all is not subscribed")
    func nothing() {
        #expect(Entitlement.resolve(entitlements: [], statuses: [], now: now).status == .notSubscribed)
    }

    @Test("A live trial transaction is a trial ending at its expiration")
    func trial() {
        let trial = fact(trial: true)
        let status = SubscriptionStatusFact(state: .subscribed, transaction: trial, willAutoRenew: true)
        let result = Entitlement.resolve(entitlements: [trial], statuses: [status], now: now)
        #expect(result.status == .trial(plan: .monthly, endsOn: now.addingTimeInterval(20 * day), willRenew: true))
        #expect(result.isPro)
    }

    @Test("A paid transaction is active, with renewal info from its status")
    func active() {
        let paid = fact(.yearly)
        let status = SubscriptionStatusFact(state: .subscribed, transaction: paid, willAutoRenew: false)
        let result = Entitlement.resolve(entitlements: [paid], statuses: [status], now: now)
        #expect(result.status == .active(plan: .yearly, periodEnds: paid.expirationDate, willRenew: false, renewsTo: nil, familyShared: false))
    }

    @Test("currentEntitlements alone is enough (status API offline)")
    func entitlementsOnly() {
        let result = Entitlement.resolve(entitlements: [fact()], statuses: [], now: now)
        #expect(result.status == .active(plan: .monthly, periodEnds: now.addingTimeInterval(20 * day), willRenew: nil, renewsTo: nil, familyShared: false))
    }

    @Test("A pending plan change shows the plan it renews to")
    func renewsTo() {
        let paid = fact(.monthly)
        let status = SubscriptionStatusFact(state: .subscribed, transaction: paid, willAutoRenew: true, autoRenewPlan: .yearly)
        let result = Entitlement.resolve(entitlements: [paid], statuses: [status], now: now)
        #expect(result.status == .active(plan: .monthly, periodEnds: paid.expirationDate, willRenew: true, renewsTo: .yearly, familyShared: false))
    }

    @Test("Grace period counts as Pro until it ends")
    func grace() {
        let lapsed = fact(expires: -day)
        let until = now.addingTimeInterval(5 * day)
        let status = SubscriptionStatusFact(state: .inGracePeriod, transaction: lapsed, gracePeriodExpirationDate: until)
        let result = Entitlement.resolve(entitlements: [], statuses: [status], now: now)
        #expect(result.status == .gracePeriod(plan: .monthly, until: until))
        #expect(result.isPro)

        let ended = SubscriptionStatusFact(state: .inGracePeriod, transaction: lapsed, gracePeriodExpirationDate: now.addingTimeInterval(-1))
        #expect(!Entitlement.resolve(entitlements: [], statuses: [ended], now: now).isPro)
    }

    @Test("Billing retry counts as Pro")
    func billingRetry() {
        let status = SubscriptionStatusFact(state: .inBillingRetryPeriod, transaction: fact(.yearly, expires: -10 * day))
        let result = Entitlement.resolve(entitlements: [], statuses: [status], now: now)
        #expect(result.status == .billingRetry(plan: .yearly))
        #expect(result.isPro)
    }

    @Test("Revoked and upgraded transactions never entitle")
    func revokedAndUpgraded() {
        let refunded = fact(revoked: true)
        let revoked = Entitlement.resolve(
            entitlements: [refunded],
            statuses: [SubscriptionStatusFact(state: .revoked, transaction: refunded)],
            now: now
        )
        #expect(revoked.status == .revoked)
        #expect(!revoked.isPro)

        // Upgraded monthly alongside the yearly that replaced it.
        let upgraded = fact(.monthly, upgraded: true)
        let yearly = fact(.yearly, bought: -day, expires: 364 * day)
        let result = Entitlement.resolve(entitlements: [upgraded, yearly], statuses: [], now: now)
        #expect(result.plan == .yearly)

        #expect(!Entitlement.resolve(entitlements: [upgraded], statuses: [], now: now).isPro)
    }

    @Test("A stale 'subscribed' status past its expiration doesn't entitle")
    func staleSubscribed() {
        let stale = fact(expires: -60)
        let result = Entitlement.resolve(entitlements: [], statuses: [SubscriptionStatusFact(state: .subscribed, transaction: stale)], now: now)
        #expect(result.status == .expired(on: now.addingTimeInterval(-60)))
    }

    @Test("An ended subscription is expired, with the last end date")
    func expired() {
        let old = fact(bought: -40 * day, expires: -10 * day)
        let result = Entitlement.resolve(entitlements: [], statuses: [SubscriptionStatusFact(state: .expired, transaction: old)], now: now)
        #expect(result.status == .expired(on: now.addingTimeInterval(-10 * day)))
        #expect(Entitlement.resolve(entitlements: [], statuses: [], hadSubscription: true, now: now).status == .expired(on: nil))
    }

    @Test("Family Sharing entitles, and your own plan wins over a shared one")
    func familySharing() {
        let shared = fact(.yearly, expires: 200 * day, shared: true)
        let sharedOnly = Entitlement.resolve(entitlements: [shared], statuses: [], now: now)
        #expect(sharedOnly.status == .active(plan: .yearly, periodEnds: shared.expirationDate, willRenew: nil, renewsTo: nil, familyShared: true))

        let own = fact(.monthly)
        let both = Entitlement.resolve(entitlements: [shared, own], statuses: [], now: now)
        #expect(both.plan == .monthly)
    }

    @Test("Paid beats trial, and active beats grace and billing retry")
    func ranking() {
        let trial = fact(.monthly, trial: true)
        let paid = fact(.yearly)
        #expect(Entitlement.resolve(entitlements: [trial, paid], statuses: [], now: now).plan == .yearly)

        let grace = SubscriptionStatusFact(state: .inGracePeriod, transaction: fact(.yearly, expires: -day))
        let retry = SubscriptionStatusFact(state: .inBillingRetryPeriod, transaction: fact(.yearly, expires: -day))
        #expect(Entitlement.resolve(entitlements: [], statuses: [retry, grace], now: now).status == .gracePeriod(plan: .yearly, until: nil))
        let withActive = Entitlement.resolve(entitlements: [fact(.monthly, shared: true)], statuses: [grace], now: now)
        if case .active = withActive.status {} else { Issue.record("expected active, got \(withActive.status)") }
    }
}

@Suite("Store entitlement cache")
struct StoreEntitlementCacheTests {
    @Test("Pro answers are cached until their end date; others clear the cache")
    func updated() {
        let end = now.addingTimeInterval(30 * day)
        let pro = Entitlement(status: .active(plan: .monthly, periodEnds: end, willRenew: true, renewsTo: nil, familyShared: false), evaluatedAt: now)
        #expect(EntitlementCache.updated(nil, from: pro) == EntitlementCache(proUntil: end))

        let retry = Entitlement(status: .billingRetry(plan: .monthly), evaluatedAt: now)
        #expect(EntitlementCache.updated(nil, from: retry) == EntitlementCache(proUntil: now.addingTimeInterval(EntitlementCache.undatedValidity)))

        let existing = EntitlementCache(proUntil: end)
        #expect(EntitlementCache.updated(existing, from: Entitlement(status: .expired(on: nil), evaluatedAt: now)) == nil)
        #expect(EntitlementCache.updated(existing, from: .unknown) == existing)
    }

    @Test("The provisional entitlement is Pro only while the cache is current")
    func provisional() {
        let cache = EntitlementCache(proUntil: now.addingTimeInterval(60))
        #expect(EntitlementCache.provisional(cache, now: now).isPro)
        #expect(!EntitlementCache.provisional(cache, now: now.addingTimeInterval(61)).isPro)
        #expect(EntitlementCache.provisional(nil, now: now).status == .unknown)
        #expect(!EntitlementCache.provisional(cache, now: now).isSettled)
    }
}
