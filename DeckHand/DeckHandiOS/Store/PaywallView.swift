//
//  PaywallView.swift
//  DeckHandiOS
//
//  Pixel Hand Pro's paywall. Opened by a locked control (`.requiresPro`),
//  by the picker when a free user picks a second Mac, and from Settings ›
//  Subscription.
//
//  App Review guideline 3.1.2 asks the purchase screen to show, before the
//  person buys: the subscription's name, each plan's length and price (the
//  billed amount most prominent), what the free trial is and when payment
//  starts, that it renews automatically and how to cancel, and working
//  links to the Terms of Use (Apple's standard EULA) and the privacy
//  policy. All of it is on this screen, next to the button, along with
//  Restore Purchases. The words are in PixelHandCore (`SubscriptionCopy`).
//
//  Only features that ship are listed; AI isn't until it does.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    enum Reason {
        /// A locked control was tapped.
        case feature(ProFeature)
        /// The picker refused a Mac that isn't the free one.
        case anotherMac(MacPaywallRequest)
        /// Settings › Subscription › See Pixel Hand Pro.
        case settings
    }

    let reason: Reason

    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchaseAction
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var switchFailed = false
    private let store = SubscriptionStore.shared

    /// Features the paywall lists: Pro's, minus the ones not built yet.
    private static let listedFeatures: [ProFeature] = ProFeature.proFeatures.filter { $0 != .ai }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if case let .anotherMac(request) = reason {
                        anotherMacCard(request)
                    }
                    featureList
                    if store.entitlement.isPro {
                        alreadyPro
                    } else {
                        planPicker
                        purchaseButton
                        statusMessages
                        disclosure
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(DeckHandTheme.brandBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: store.entitlement.isPro) { _, isPro in
            // Bought here, restored, or approved by a parent while open.
            if isPro { finish() }
        }
    }

    // MARK: - Sections

    private var focusFeature: ProFeature? {
        switch reason {
        case let .feature(feature): feature
        case .anotherMac: .multipleMacs
        case .settings: nil
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            DeckHandMark(size: 72)
            Text(SubscriptionCopy.headline(for: focusFeature))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(SubscriptionCopy.freePlanSummary)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func anotherMacCard(_ request: MacPaywallRequest) -> some View {
        let canSwitch = request.switchAllowedAt <= Date()
        return VStack(alignment: .leading, spacing: 10) {
            Text(SubscriptionCopy.otherMacMessage(freeMacName: request.freeMacName))
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            if canSwitch, !switchFailed {
                Button(SubscriptionCopy.switchMacButton(newMacName: request.macName)) {
                    if store.makeFreeMac(deviceID: request.deviceID, name: request.macName) {
                        finish()
                    } else {
                        switchFailed = true
                    }
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tint(DeckHandTheme.Brand.mint)
            } else {
                Text(SubscriptionCopy.switchMacWait(until: request.switchAllowedAt.formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(card(highlighted: false))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.listedFeatures, id: \.self) { feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: SubscriptionCopy.symbol(feature))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(feature == focusFeature ? DeckHandTheme.Brand.mint : .white.opacity(0.75))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SubscriptionCopy.title(feature))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(SubscriptionCopy.detail(feature))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savingsPercent: Int? {
        let monthly = store.products[.monthly]?.price ?? SubscriptionPlan.monthly.fallbackPrice
        let yearly = store.products[.yearly]?.price ?? SubscriptionPlan.yearly.fallbackPrice
        return SubscriptionPricing.yearlySavingsPercent(monthly: monthly, yearly: yearly)
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach([SubscriptionPlan.yearly, .monthly], id: \.self) { plan in
                let price = store.products[plan]?.displayPrice
                Button {
                    selectedPlan = plan
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedPlan == plan ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedPlan == plan ? DeckHandTheme.Brand.mint : .white.opacity(0.35))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                            // The billed amount is the most prominent price.
                            Text(SubscriptionCopy.billedPrice(plan, displayPrice: price))
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(SubscriptionCopy.planCaption(plan, displayPrice: price, trialEligible: store.isTrialEligible, savingsPercent: savingsPercent))
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(card(highlighted: selectedPlan == plan))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPlan == plan ? .isSelected : [])
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await store.purchase(selectedPlan, using: purchaseAction) }
        } label: {
            ZStack {
                Text(SubscriptionCopy.purchaseButtonTitle(trialEligible: store.isTrialEligible))
                    .opacity(store.isWorking ? 0 : 1)
                if store.isWorking {
                    ProgressView().tint(.white)
                }
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: DeckHandTheme.Radius.md, style: .continuous)
                    .fill(DeckHandTheme.Brand.cobalt)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(store.isWorking)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if store.isPurchasePending {
            Text("Your purchase is waiting for approval. Pro turns on as soon as it's approved.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(DeckHandTheme.Brand.mint)
                .multilineTextAlignment(.center)
        }
        if let error = store.errorMessage {
            Text(error)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(DeckHandTheme.warning)
                .multilineTextAlignment(.center)
        }
    }

    private var disclosure: some View {
        VStack(spacing: 14) {
            Text(SubscriptionCopy.disclosure(
                monthlyPrice: store.products[.monthly]?.displayPrice,
                yearlyPrice: store.products[.yearly]?.displayPrice,
                trialEligible: store.isTrialEligible
            ))
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .disabled(store.isWorking)
                Link("Terms of Use", destination: SubscriptionCopy.termsOfUseURL)
                Link("Privacy Policy", destination: SubscriptionCopy.privacyPolicyURL)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .tint(.white.opacity(0.8))
        }
    }

    private var alreadyPro: some View {
        VStack(spacing: 12) {
            Text("You have Pixel Hand Pro. Everything is unlocked.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DeckHandTheme.Brand.mint)
                .multilineTextAlignment(.center)
            Button("Done") { finish() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tint(.white)
        }
    }

    // MARK: - Helpers

    private func card(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: DeckHandTheme.Radius.md, style: .continuous)
            .fill(Color.white.opacity(highlighted ? 0.1 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: DeckHandTheme.Radius.md, style: .continuous)
                    .strokeBorder(highlighted ? DeckHandTheme.Brand.mint.opacity(0.7) : Color.white.opacity(0.1), lineWidth: highlighted ? 1.5 : 1)
            )
    }

    /// Closes the paywall; a Mac the picker refused is dialled now.
    private func finish() {
        var retry: (@MainActor () -> Void)?
        if case let .anotherMac(request) = reason { retry = request.retry }
        dismiss()
        if let retry {
            Task { @MainActor in
                // Let the sheet go before the picker starts connecting.
                try? await Task.sleep(for: .milliseconds(400))
                retry()
            }
        }
    }
}
