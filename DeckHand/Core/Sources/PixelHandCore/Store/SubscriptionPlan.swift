//
//  SubscriptionPlan.swift
//  PixelHandCore
//
//  The Pixel Hand Pro subscription as it's set up in App Store Connect
//  (DECISIONS.md, 2026-11-17): one group, two auto-renewable plans, each
//  with a 2-week free trial as its introductory offer, Family Sharing on.
//
//  The prices here are the USD tier and are only a fallback for copy when
//  the App Store hasn't returned products (offline, or a misconfigured
//  `.storekit` file). The paywall shows the App Store's localized
//  `displayPrice` whenever it has one.
//

import Foundation

/// One of the Pixel Hand Pro plans.
public enum SubscriptionPlan: String, CaseIterable, Codable, Sendable {
    case monthly
    case yearly

    /// The subscription group's reference name in App Store Connect.
    public static let groupName = "Pixel Hand Pro"
    /// The introductory offer: a free trial of this many days.
    public static let freeTrialDays = 14

    /// The App Store product identifier.
    public var productID: String {
        switch self {
        case .monthly: "com.widgetsflow.pixelhand.pro.monthly"
        case .yearly: "com.widgetsflow.pixelhand.pro.yearly"
        }
    }

    /// Every product identifier the app sells, for `Product.products(for:)`.
    public static let productIDs: [String] = allCases.map(\.productID)

    public init?(productID: String) {
        guard let plan = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }

    /// The USD price, for copy when the App Store gave none.
    public var fallbackPrice: Decimal {
        switch self {
        case .monthly: Decimal(string: "2.99")!
        case .yearly: Decimal(string: "19.99")!
        }
    }

    /// "$2.99", the fallback price formatted in US dollars.
    public var fallbackDisplayPrice: String {
        "$" + NSDecimalNumber(decimal: fallbackPrice).stringValue
    }

    /// "month" or "year", for "per month" and "/month".
    public var periodNoun: String {
        switch self {
        case .monthly: "month"
        case .yearly: "year"
        }
    }

    /// "Monthly" or "Yearly".
    public var title: String {
        switch self {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }
}

/// Price comparisons for the paywall.
public enum SubscriptionPricing {
    /// How much cheaper a year is than twelve months, as a whole percentage
    /// rounded down (so the claim is never overstated). `nil` when the
    /// yearly plan doesn't save anything or a price is missing.
    public static func yearlySavingsPercent(monthly: Decimal, yearly: Decimal) -> Int? {
        guard monthly > 0, yearly > 0 else { return nil }
        let twelveMonths = monthly * 12
        guard yearly < twelveMonths else { return nil }
        let saving = (twelveMonths - yearly) / twelveMonths * 100
        var rounded = Decimal()
        var value = saving
        NSDecimalRound(&rounded, &value, 0, .down)
        let percent = NSDecimalNumber(decimal: rounded).intValue
        return percent > 0 ? percent : nil
    }
}
