//
//  SubscriptionCopy.swift
//  PixelHandCore
//
//  Words for the paywall, the lock badges and Settings › Subscription, and
//  the auto-renewal disclosure that App Review guideline 3.1.2 requires
//  next to the purchase buttons.
//
//  Prices come in as the App Store's localized `displayPrice` strings; the
//  fallbacks are the USD tier. Dates are formatted by the caller, so tests
//  don't depend on the machine's locale.
//

import Foundation

public enum SubscriptionCopy {
    /// The Terms of Use: Apple's standard EULA (no custom EULA is set in
    /// App Store Connect).
    public static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// The privacy policy on the website.
    public static let privacyPolicyURL = URL(string: "https://pixelhand.app/privacy")!

    public static let productName = "Pixel Hand Pro"

    // MARK: Features

    /// Short name for a feature, for "Mirror is part of Pixel Hand Pro".
    public static func title(_ feature: ProFeature) -> String {
        switch feature {
        case .trackpad: "Trackpad"
        case .keyboard: "Keyboard"
        case .mediaKeys: "Media keys"
        case .decks: "Shortcut chips and decks"
        case .mirror: "Live mirror"
        case .capture: "Capture and text recognition"
        case .multipleMacs: "All your Macs"
        case .sharing: "Clipboard sharing"
        case .ai: "AI commands"
        }
    }

    /// One line on what the feature does, for the paywall's list.
    public static func detail(_ feature: ProFeature) -> String {
        switch feature {
        case .trackpad: "Multi-touch pointer, clicks, drag and scrolling."
        case .keyboard: "Type on your Mac, with shortcuts and modifiers."
        case .mediaKeys: "Play, pause and skip."
        case .decks: "One-tap shortcuts for the app in front, dialog buttons and the app launcher."
        case .mirror: "See your Mac's screen live, sharp as it grows, a whole display or one window."
        case .capture: "Grab the screen, a region or a window; mark it up and pull out the text."
        case .multipleMacs: "Switch between every Mac you own."
        case .sharing: "Copy on one device, paste on the other."
        case .ai: "Ask for what you want done on your Mac."
        }
    }

    /// SF Symbol for the feature.
    public static func symbol(_ feature: ProFeature) -> String {
        switch feature {
        case .trackpad: "hand.point.up.left"
        case .keyboard: "keyboard"
        case .mediaKeys: "playpause"
        case .decks: "square.grid.3x2"
        case .mirror: "rectangle.on.rectangle"
        case .capture: "camera.viewfinder"
        case .multipleMacs: "desktopcomputer"
        case .sharing: "doc.on.clipboard"
        case .ai: "sparkles"
        }
    }

    /// The paywall's headline when a locked feature opened it.
    public static func headline(for feature: ProFeature?) -> String {
        guard let feature, feature.tier == .pro else { return "Get more from Pixel Hand" }
        if feature == .multipleMacs { return "Control all your Macs" }
        return "\(title(feature)) is part of Pixel Hand Pro"
    }

    /// What the free plan keeps, under the feature list.
    public static let freePlanSummary = "Free forever: trackpad, keyboard and media keys with one Mac."

    // MARK: Purchase buttons

    /// "Try it free for 2 weeks" / "Subscribe".
    public static func purchaseButtonTitle(trialEligible: Bool) -> String {
        trialEligible ? "Start your free 2 weeks" : "Subscribe"
    }

    /// The billed amount, most prominent on each plan: "$19.99 / year".
    public static func billedPrice(_ plan: SubscriptionPlan, displayPrice: String?) -> String {
        "\(displayPrice ?? plan.fallbackDisplayPrice) / \(plan.periodNoun)"
    }

    /// The line under a plan: what happens after the trial.
    public static func planCaption(_ plan: SubscriptionPlan, displayPrice: String?, trialEligible: Bool, savingsPercent: Int?) -> String {
        let price = displayPrice ?? plan.fallbackDisplayPrice
        var parts: [String] = []
        if trialEligible {
            parts.append("2 weeks free, then \(price) per \(plan.periodNoun)")
        } else {
            parts.append("\(price) per \(plan.periodNoun)")
        }
        if plan == .yearly, let savingsPercent {
            parts.append("save \(savingsPercent)%")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Disclosure (guideline 3.1.2)

    /// The auto-renewal terms shown under the purchase button. Names the
    /// title, length and price of each plan, the free trial, when payment is
    /// taken, that it renews automatically, and how to cancel. The Terms of
    /// Use and privacy policy links sit right below it.
    public static func disclosure(monthlyPrice: String?, yearlyPrice: String?, trialEligible: Bool) -> String {
        let monthly = monthlyPrice ?? SubscriptionPlan.monthly.fallbackDisplayPrice
        let yearly = yearlyPrice ?? SubscriptionPlan.yearly.fallbackDisplayPrice
        var lines: [String] = []
        lines.append("\(productName) is an auto-renewable subscription: \(monthly) per month, or \(yearly) per year.")
        if trialEligible {
            lines.append("New subscribers get a 2-week free trial. Payment is charged to your Apple Account when the trial ends, unless you cancel at least 24 hours before then.")
        } else {
            lines.append("Payment is charged to your Apple Account when you confirm the purchase.")
        }
        lines.append("The subscription renews automatically at the same price for the same period unless it's cancelled at least 24 hours before the end of the current period; your account is charged for the renewal within the 24 hours before the period ends.")
        lines.append("Manage or cancel it any time in your Apple Account settings. Family Sharing is supported.")
        if trialEligible {
            lines.append("Any unused part of the free trial ends when you buy a subscription.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: Settings › Subscription

    /// The status row: a title and a detail line.
    public struct StatusRow: Equatable, Sendable {
        public var title: String
        public var detail: String
        /// The row should offer to fix a payment problem.
        public var needsPaymentAttention: Bool

        public init(title: String, detail: String, needsPaymentAttention: Bool = false) {
            self.title = title
            self.detail = detail
            self.needsPaymentAttention = needsPaymentAttention
        }
    }

    public static func statusRow(
        _ entitlement: Entitlement,
        displayPrice: (SubscriptionPlan) -> String? = { _ in nil },
        formatDate: (Date) -> String
    ) -> StatusRow {
        func price(_ plan: SubscriptionPlan) -> String {
            "\(displayPrice(plan) ?? plan.fallbackDisplayPrice)/\(plan.periodNoun)"
        }
        switch entitlement.status {
        case .unknown:
            return StatusRow(title: "Checking your subscription…", detail: "Asking the App Store.")
        case .cached:
            return StatusRow(title: productName, detail: "Checking with the App Store…")
        case .notSubscribed:
            return StatusRow(title: "Free plan", detail: "Trackpad, keyboard and media keys with one Mac.")
        case let .trial(plan, endsOn, willRenew):
            let end = endsOn.map(formatDate)
            let detail: String = switch (end, willRenew) {
            case let (end?, false?): "Trial ends \(end). It won't renew."
            case let (end?, _): "Free until \(end), then \(price(plan))."
            case (nil, _): "Free trial, then \(price(plan))."
            }
            return StatusRow(title: "\(productName) free trial", detail: detail)
        case let .active(plan, periodEnds, willRenew, renewsTo, familyShared):
            let end = periodEnds.map(formatDate)
            var detail: String = switch (end, willRenew) {
            case let (end?, false?): "Ends \(end). It won't renew."
            case let (end?, _):
                if let renewsTo { "Switches to \(renewsTo.title.lowercased()) on \(end)." } else { "Renews \(end) at \(price(plan))." }
            case (nil, _): "\(plan.title) plan."
            }
            if familyShared { detail = "Shared by your family. " + detail }
            return StatusRow(title: "\(productName), \(plan.title.lowercased())", detail: detail)
        case let .gracePeriod(_, until):
            let by = until.map { " by \(formatDate($0))" } ?? ""
            return StatusRow(
                title: productName,
                detail: "Apple couldn't renew your subscription. Update your payment method\(by) to keep Pro.",
                needsPaymentAttention: true
            )
        case .billingRetry:
            return StatusRow(
                title: productName,
                detail: "Apple couldn't renew your subscription. Update your payment method to keep Pro.",
                needsPaymentAttention: true
            )
        case let .expired(on):
            let detail = on.map { "Pro ended \(formatDate($0)). You're on the free plan." } ?? "Pro has ended. You're on the free plan."
            return StatusRow(title: "Free plan", detail: detail)
        case .revoked:
            return StatusRow(title: "Free plan", detail: "Your Pro purchase was refunded, so you're on the free plan.")
        }
    }

    // MARK: One Mac

    /// The paywall's line when a free user picks a second Mac.
    public static func otherMacMessage(freeMacName: String) -> String {
        "The free plan works with one Mac, \(freeMacName). Pro controls every Mac you own."
    }

    /// The "Use this Mac instead" button.
    public static func switchMacButton(newMacName: String) -> String {
        "Use \(newMacName) as my free Mac"
    }

    /// Why "Use this Mac instead" is unavailable.
    public static func switchMacWait(until date: String) -> String {
        "You can change your free Mac again on \(date)."
    }
}
