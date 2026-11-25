//
//  SubscriptionStore.swift
//  DeckHandiOS
//
//  Pixel Hand Pro through StoreKit 2. No server: the entitlement comes from
//  `Transaction.currentEntitlements` and the group's renewal status, and
//  changes arrive on `Transaction.updates` (renewals, refunds, Family
//  Sharing, purchases made on another device or approved by a parent).
//
//  The rules live in PixelHandCore (`Entitlement.resolve`,
//  `FreeMacPolicy`); this file only copies StoreKit's values into Core's
//  facts and stores the two small things the device remembers: the last
//  Pro answer (`EntitlementCache`, so locks don't flash at launch) and the
//  free plan's Mac (`FreeMacChoice`).
//
//  Other lanes never use this type or StoreKit. They read
//  `@Environment(\.entitlements)` and put `.requiresPro(_:)` on a control
//  (RequiresPro.swift). The picker's one-Mac check is the one exception:
//  `SubscriptionStore.shared.admitMac(...)`.
//

import Foundation
import Observation
import StoreKit
import SwiftUI

@MainActor
@Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    /// What this device may use. Starts from the cache, then StoreKit;
    /// "Unlock Pro for testing" overrides it where that switch is offered.
    var entitlement: Entitlement {
        isDeveloperUnlockActive ? DeveloperUnlock.entitlement : storeEntitlement
    }
    /// What StoreKit says, before any testing override. The cache stores
    /// this, never the override.
    private(set) var storeEntitlement: Entitlement
    /// Whether this build offers "Unlock Pro for testing" (development and
    /// TestFlight builds; never App Store ones). See DeveloperUnlock.swift.
    private(set) var isDeveloperUnlockAvailable = false
    /// The switch's stored position. Only counts where it's offered.
    private(set) var isDeveloperUnlocked: Bool
    /// The override is on and allowed in this build.
    var isDeveloperUnlockActive: Bool {
        isDeveloperUnlockAvailable && isDeveloperUnlocked
    }
    /// The App Store's products, by plan. Empty until loaded (or offline).
    private(set) var products: [SubscriptionPlan: Product] = [:]

    /// Where loading the products stands, so the paywall can say "Getting
    /// prices…" or "Couldn't reach the App Store" with Try again instead of
    /// failing silently (VQ-055).
    enum ProductsState: Equatable {
        case notLoaded, loading, loaded, failed
    }

    private(set) var productsState: ProductsState = .notLoaded

    /// Loads the products again (the paywall's Try again, and on open when
    /// none loaded yet).
    func reloadProducts() async {
        guard productsState != .loading else { return }
        await loadProducts()
    }
    /// Whether this Apple Account can still take the free trial. Assumed
    /// until StoreKit says otherwise, because the disclosure must not hide
    /// a trial the person would get.
    private(set) var isTrialEligible = true
    /// A purchase or restore is running.
    private(set) var isWorking = false
    /// The last purchase or restore problem, for the paywall.
    var errorMessage: String?
    /// A purchase waits for approval (Ask to Buy, or a bank check).
    private(set) var isPurchasePending = false
    /// The free plan's Mac.
    private(set) var freeMac: FreeMacChoice?
    /// A paywall the root host shows: today only "this isn't your free
    /// Mac", raised from the picker.
    var macPaywall: MacPaywallRequest?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let cache = "store.entitlementCache"
        static let freeMac = "store.freeMac"
        static let developerUnlock = "store.developerUnlock"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let cache = Self.decode(EntitlementCache.self, defaults.data(forKey: Key.cache))
        storeEntitlement = EntitlementCache.provisional(cache, now: Date())
        isDeveloperUnlocked = defaults.bool(forKey: Key.developerUnlock)
        freeMac = Self.decode(FreeMacChoice.self, defaults.data(forKey: Key.freeMac))
    }

    // MARK: - Lifetime

    /// Starts listening for transactions and loads products and the
    /// entitlement. Safe to call more than once.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        // Listen first, so a transaction finished on another device while
        // the app launches isn't missed.
        updatesTask = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            isDeveloperUnlockAvailable = await DeveloperUnlock.isAvailable()
            await finishUnfinished()
            await loadProducts()
            await refresh()
        }
    }

    /// Re-reads the entitlement from StoreKit. Called at launch, after a
    /// purchase or restore, on every transaction update, and when the app
    /// comes back to the front.
    func refresh() async {
        var entitlements: [SubscriptionFact] = []
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result, let fact = Self.fact(transaction) else { continue }
            entitlements.append(fact)
        }

        var statuses: [SubscriptionStatusFact] = []
        if let subscription = products.values.first?.subscription {
            do {
                for status in try await subscription.status {
                    if let fact = Self.statusFact(status) { statuses.append(fact) }
                }
            } catch {
                DeckHandLog.app.error("Subscription status unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        var hadSubscription = !entitlements.isEmpty || !statuses.isEmpty
        if !hadSubscription {
            for await result in Transaction.all {
                if case let .verified(transaction) = result, SubscriptionPlan(productID: transaction.productID) != nil {
                    hadSubscription = true
                    break
                }
            }
        }

        let resolved = Entitlement.resolve(
            entitlements: entitlements,
            statuses: statuses,
            hadSubscription: hadSubscription,
            now: Date()
        )
        apply(resolved)

        if let subscription = products.values.first?.subscription {
            isTrialEligible = await subscription.isEligibleForIntroOffer
        }
    }

    // MARK: - Purchasing

    /// Buys `plan` with SwiftUI's purchase action (`@Environment(\.purchase)`),
    /// which presents the App Store sheet on the right scene. Returns `true`
    /// when Pro is now on.
    @discardableResult
    func purchase(_ plan: SubscriptionPlan, using purchaseAction: PurchaseAction) async -> Bool {
        guard let product = products[plan] else {
            errorMessage = "The App Store isn't available right now. Check your connection and try again."
            await loadProducts()
            return false
        }
        isWorking = true
        errorMessage = nil
        isPurchasePending = false
        defer { isWorking = false }
        do {
            switch try await purchaseAction(product) {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    errorMessage = "The App Store couldn't verify this purchase. Try Restore Purchases."
                    return false
                }
                await transaction.finish()
                await refresh()
                return entitlement.isPro
            case .pending:
                isPurchasePending = true
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "The purchase didn't go through: \(error.localizedDescription)"
            return false
        }
    }

    /// Restore Purchases: syncs this Apple Account's transactions with the
    /// App Store (it may ask the person to sign in), then re-reads them.
    func restore() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            errorMessage = "Couldn't reach the App Store: \(error.localizedDescription)"
        }
        await refresh()
        if !entitlement.isPro, errorMessage == nil {
            errorMessage = "No Pixel Hand Pro subscription was found for this Apple Account."
        }
    }

    // MARK: - Testing

    /// "Unlock Pro for testing". Ignored in builds that don't offer it.
    func setDeveloperUnlocked(_ isOn: Bool) {
        isDeveloperUnlocked = isOn
        defaults.set(isOn, forKey: Key.developerUnlock)
        DeckHandLog.app.info("Unlock Pro for testing: \(isOn ? "on" : "off", privacy: .public)")
    }

    // MARK: - One Mac

    /// The picker's check before it dials a Mac. Returns `false` (and
    /// raises the paywall) when the free plan doesn't cover this Mac.
    /// `retry` runs after the person buys Pro or makes this their free Mac.
    func admitMac(deviceID: UUID, name: String, retry: @escaping @MainActor () -> Void = {}) -> Bool {
        switch FreeMacPolicy.admit(deviceID: deviceID, name: name, isPro: entitlement.isPro, choice: freeMac, now: Date()) {
        case let .allowed(choice):
            if choice != freeMac { saveFreeMac(choice) }
            return true
        case let .needsPro(current, switchAllowedAt):
            macPaywall = MacPaywallRequest(
                deviceID: deviceID,
                macName: name,
                freeMacName: current.name,
                switchAllowedAt: switchAllowedAt,
                retry: retry
            )
            return false
        }
    }

    /// "Use this Mac as my free Mac". Returns `false` when it's too soon.
    @discardableResult
    func makeFreeMac(deviceID: UUID, name: String) -> Bool {
        guard let choice = FreeMacPolicy.switchFreeMac(to: deviceID, name: name, from: freeMac, now: Date()) else {
            return false
        }
        saveFreeMac(choice)
        return true
    }

    /// Whether the picker should mark this Mac as needing Pro.
    func isLockedMac(deviceID: UUID) -> Bool {
        guard !entitlement.isPro, let freeMac else { return false }
        return freeMac.deviceID != deviceID
    }

    // MARK: - Internals

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        if case let .verified(transaction) = result {
            await transaction.finish()
        }
        await refresh()
    }

    private func finishUnfinished() async {
        for await result in Transaction.unfinished {
            if case let .verified(transaction) = result {
                await transaction.finish()
            }
        }
    }

    private func loadProducts() async {
        productsState = .loading
        do {
            let loaded = try await Product.products(for: SubscriptionPlan.productIDs)
            var byPlan: [SubscriptionPlan: Product] = [:]
            for product in loaded {
                if let plan = SubscriptionPlan(productID: product.id) { byPlan[plan] = product }
            }
            products = byPlan
            productsState = byPlan.isEmpty ? .failed : .loaded
            if byPlan.count < SubscriptionPlan.allCases.count {
                DeckHandLog.app.error("App Store returned \(byPlan.count) of \(SubscriptionPlan.allCases.count) Pro products")
            }
        } catch {
            productsState = .failed
            DeckHandLog.app.error("Loading Pro products failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ resolved: Entitlement) {
        storeEntitlement = resolved
        let current = Self.decode(EntitlementCache.self, defaults.data(forKey: Key.cache))
        let updated = EntitlementCache.updated(current, from: resolved)
        if updated != current {
            if let updated, let data = try? JSONEncoder().encode(updated) {
                defaults.set(data, forKey: Key.cache)
            } else {
                defaults.removeObject(forKey: Key.cache)
            }
        }
    }

    private func saveFreeMac(_ choice: FreeMacChoice) {
        freeMac = choice
        if let data = try? JSONEncoder().encode(choice) {
            defaults.set(data, forKey: Key.freeMac)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - StoreKit → Core

    private static func fact(_ transaction: StoreKit.Transaction) -> SubscriptionFact? {
        guard let plan = SubscriptionPlan(productID: transaction.productID) else { return nil }
        return SubscriptionFact(
            plan: plan,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            isFreeTrial: transaction.offer?.type == .introductory
                && transaction.offer?.paymentMode == .freeTrial,
            isFamilyShared: transaction.ownershipType == .familyShared
        )
    }

    private static func statusFact(_ status: Product.SubscriptionInfo.Status) -> SubscriptionStatusFact? {
        guard case let .verified(transaction) = status.transaction, let fact = fact(transaction) else { return nil }
        let state: PixelHandCore.SubscriptionRenewalState
        switch status.state {
        case .subscribed: state = .subscribed
        case .inGracePeriod: state = .inGracePeriod
        case .inBillingRetryPeriod: state = .inBillingRetryPeriod
        case .revoked: state = .revoked
        default: state = .expired
        }
        var renewal: Product.SubscriptionInfo.RenewalInfo?
        if case let .verified(info) = status.renewalInfo { renewal = info }
        return SubscriptionStatusFact(
            state: state,
            transaction: fact,
            willAutoRenew: renewal?.willAutoRenew,
            autoRenewPlan: renewal?.autoRenewPreference.flatMap(SubscriptionPlan.init(productID:)),
            gracePeriodExpirationDate: renewal?.gracePeriodExpirationDate
        )
    }
}

/// "This isn't your free Mac", raised by the picker and shown by the root
/// paywall host.
struct MacPaywallRequest: Identifiable {
    let id = UUID()
    let deviceID: UUID
    let macName: String
    let freeMacName: String
    let switchAllowedAt: Date
    let retry: @MainActor () -> Void
}
