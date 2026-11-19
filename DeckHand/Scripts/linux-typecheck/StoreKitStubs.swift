//
//  StoreKitStubs.swift
//  AppTypeCheck
//
//  StoreKit 2 stand-ins for the Store lane's SubscriptionStore. Signatures
//  follow the iOS 17 SDK (names, optionality, async/throws, Sendable), so
//  mapping mistakes and Swift 6 concurrency errors show up on Linux.
//

import Foundation

enum VerificationResult<SignedType: Sendable>: Sendable {
    case unverified(SignedType, VerificationError)
    case verified(SignedType)

    enum VerificationError: Error, Sendable { case invalidSignature }
}

struct StoreTransactionSequence: AsyncSequence, Sendable {
    typealias Element = VerificationResult<Transaction>
    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async -> Element? { nil }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}

struct Transaction: Sendable {
    let productID: String
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
    let ownershipType: OwnershipType
    let offer: Offer?

    struct OwnershipType: Equatable, Hashable, Sendable {
        static let purchased = OwnershipType()
        static let familyShared = OwnershipType()
    }

    struct OfferType: Equatable, Hashable, Sendable {
        static let introductory = OfferType()
        static let promotional = OfferType()
        static let code = OfferType()
    }

    struct Offer: Hashable, Sendable {
        let id: String?
        let type: OfferType
        let paymentMode: PaymentMode?

        struct PaymentMode: Equatable, Hashable, Sendable {
            static let freeTrial = PaymentMode()
            static let payAsYouGo = PaymentMode()
            static let payUpFront = PaymentMode()
        }
    }

    func finish() async {}

    static var updates: StoreTransactionSequence { StoreTransactionSequence() }
    static var currentEntitlements: StoreTransactionSequence { StoreTransactionSequence() }
    static var unfinished: StoreTransactionSequence { StoreTransactionSequence() }
    static var all: StoreTransactionSequence { StoreTransactionSequence() }
}

struct Product: Identifiable, Sendable {
    let id: String
    let displayPrice: String
    let price: Decimal
    let subscription: SubscriptionInfo?

    static func products<Identifiers: Collection>(for identifiers: Identifiers) async throws -> [Product] where Identifiers.Element == String { [] }

    struct PurchaseOption: Hashable, Sendable {}

    enum PurchaseResult: Sendable {
        case success(VerificationResult<Transaction>)
        case userCancelled
        case pending
    }

    struct SubscriptionInfo: Sendable {
        var status: [Status] { get async throws { [] } }
        var isEligibleForIntroOffer: Bool { get async { true } }

        struct RenewalState: Equatable, Hashable, Sendable {
            let rawValue: Int
            static let subscribed = RenewalState(rawValue: 1)
            static let expired = RenewalState(rawValue: 2)
            static let inBillingRetryPeriod = RenewalState(rawValue: 3)
            static let inGracePeriod = RenewalState(rawValue: 4)
            static let revoked = RenewalState(rawValue: 5)
        }

        struct RenewalInfo: Sendable {
            let willAutoRenew: Bool
            let autoRenewPreference: String?
            let gracePeriodExpirationDate: Date?
        }

        struct Status: Sendable {
            let state: RenewalState
            let transaction: VerificationResult<Transaction>
            let renewalInfo: VerificationResult<RenewalInfo>
        }
    }
}

/// SwiftUI's `@Environment(\.purchase)` value.
@MainActor
struct PurchaseAction {
    func callAsFunction(_ product: Product, options: Set<Product.PurchaseOption> = []) async throws -> Product.PurchaseResult { .userCancelled }
}

enum AppStore {
    static func sync() async throws {}
}

enum StoreKitError: Error, Sendable {
    case unknown
    case userCancelled
    case networkError(URLError)
    case notAvailableInStorefront
    case notEntitled
}
