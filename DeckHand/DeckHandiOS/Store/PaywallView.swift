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
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.xl) {
                    header
                    if case let .anotherMac(request) = reason {
                        anotherMacCard(request)
                    }
                    featureList
                    if store.entitlement.isPro {
                        alreadyPro
                    } else {
                        planPicker
                        productsStatus
                        purchaseButton
                        statusMessages
                        disclosure
                    }
                }
                .padding(.horizontal, PixelHandTheme.Space.xl)
                .padding(.bottom, PixelHandTheme.Space.xl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(PixelHandTheme.brandBackground().ignoresSafeArea())
            .foregroundStyle(.white)
            .pixelOnNavy()
            .task {
                if store.products.isEmpty { await store.reloadProducts() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                // Always visible: the paywall never hides its close button.
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        PHGlyph(glyph: PixelGlyphs.close, pitch: 1.6)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("ph.paywall.close")
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

    /// The PRO mark on a navy plate (LED panel look), the Geist headline and
    /// what stays free.
    private var header: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.lg) {
            DotMatrixText("PRO", pitch: 5, label: SubscriptionCopy.productName, showsUnlit: true, glows: true, stepsWithType: false)
                .foregroundStyle(PixelHandTheme.Brand.phosphor)
                .padding(.horizontal, PixelHandTheme.Space.xl)
                .padding(.vertical, PixelHandTheme.Space.lg)
                .background(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                        .fill(PixelHandTheme.Brand.screenSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                        .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: 1)
                )
                .shadow(color: PixelHandTheme.Brand.cobalt.opacity(0.45), radius: 24)
            Text(SubscriptionCopy.headline(for: focusFeature))
                .font(PixelHandFonts.geist(.medium, size: 30, relativeTo: .largeTitle))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: PixelHandTheme.Space.sm) {
                StatusPixel(state: .live)
                Text(SubscriptionCopy.freePlanSummary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, PixelHandTheme.Space.sm)
    }

    private func anotherMacCard(_ request: MacPaywallRequest) -> some View {
        let canSwitch = request.switchAllowedAt <= Date()
        return VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
            HStack(alignment: .top, spacing: PixelHandTheme.Space.md) {
                GlyphTile(glyph: PixelGlyphs.mac)
                Text(SubscriptionCopy.otherMacMessage(freeMacName: request.freeMacName))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canSwitch, !switchFailed {
                Button(SubscriptionCopy.switchMacButton(newMacName: request.macName)) {
                    if store.makeFreeMac(deviceID: request.deviceID, name: request.macName) {
                        finish()
                    } else {
                        switchFailed = true
                    }
                }
                .buttonStyle(.ph(.secondary, size: .small))
                .accessibilityIdentifier("ph.paywall.switchMac")
            } else {
                Text(SubscriptionCopy.switchMacWait(until: request.switchAllowedAt.formatted(date: .abbreviated, time: .omitted)))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PixelHandTheme.Space.lg)
        .background(card(highlighted: false))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.listedFeatures, id: \.self) { feature in
                HStack(alignment: .top, spacing: PixelHandTheme.Space.md) {
                    GlyphTile(
                        glyph: feature.glyph,
                        pitch: 2.2,
                        tint: feature == focusFeature ? PixelHandTheme.Brand.phosphor : Color(red: 0.81, green: 0.88, blue: 1)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SubscriptionCopy.title(feature))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(SubscriptionCopy.detail(feature))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(spacing: PixelHandTheme.Space.md) {
            ForEach([SubscriptionPlan.yearly, .monthly], id: \.self) { plan in
                let price = store.products[plan]?.displayPrice
                let isSelected = selectedPlan == plan
                Button {
                    selectedPlan = plan
                } label: {
                    HStack(alignment: .center, spacing: PixelHandTheme.Space.md) {
                        PlanRadio(isOn: isSelected)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.title)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                            // The billed amount is the most prominent price.
                            Text(SubscriptionCopy.billedPrice(plan, displayPrice: price))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(SubscriptionCopy.planCaption(plan, displayPrice: price, trialEligible: store.isTrialEligible, savingsPercent: savingsPercent))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.66))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if plan == .yearly, let savingsPercent {
                            DotMatrixText("-\(savingsPercent)%", pitch: CGFloat(PixelPitch.badge), label: "Save \(savingsPercent) percent", glows: false)
                                .foregroundStyle(PixelHandTheme.Brand.mint)
                                .padding(.horizontal, 7)
                                .frame(height: PixelHandTheme.ControlHeight.badge)
                                .background(Capsule().fill(PixelHandTheme.Brand.mint.opacity(0.16)))
                        }
                    }
                    .padding(PixelHandTheme.Space.lg)
                    .background(card(highlighted: isSelected))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("ph.paywall.plan")
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
                    DotWave(pitch: 3, label: "Working")
                }
            }
        }
        .buttonStyle(.ph(.primary, fullWidth: true))
        .shadow(color: PixelHandTheme.Brand.cobalt.opacity(0.45), radius: 16, y: 6)
        .disabled(store.isWorking || store.products[selectedPlan] == nil)
        .accessibilityIdentifier("ph.paywall.subscribe")
    }

    /// Prices still loading, or the App Store out of reach: said here, with
    /// Try again, instead of a purchase button that does nothing (VQ-055).
    @ViewBuilder
    private var productsStatus: some View {
        if store.products[selectedPlan] == nil {
            switch store.productsState {
            case .notLoaded, .loading:
                HStack(spacing: PixelHandTheme.Space.sm) {
                    DotWave(pitch: 2.5, label: "Getting prices")
                    Text("Getting prices from the App Store…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ph.paywall.loading")
            case .failed, .loaded:
                VStack(spacing: PixelHandTheme.Space.sm) {
                    Text("Couldn’t reach the App Store. Check your connection, then try again.")
                        .font(.footnote)
                        .foregroundStyle(PixelHandTheme.warning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") {
                        Task { await store.reloadProducts() }
                    }
                    .buttonStyle(.ph(.secondary, size: .regular))
                    .accessibilityIdentifier("ph.paywall.retry")
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ph.paywall.unavailable")
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if store.isPurchasePending {
            Text("Your purchase is waiting for approval. Pro turns on as soon as it's approved.")
                .font(.footnote)
                .foregroundStyle(PixelHandTheme.Brand.mint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        if let error = store.errorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(PixelHandTheme.warning)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// Apple's required text, unchanged, at a size that stays legible at AX5,
    /// with Restore Purchases, Terms of Use and Privacy Policy. The links
    /// stack when they don't fit on one line.
    private var disclosure: some View {
        VStack(spacing: 14) {
            Text(SubscriptionCopy.disclosure(
                monthlyPrice: store.products[.monthly]?.displayPrice,
                yearlyPrice: store.products[.yearly]?.displayPrice,
                trialEligible: store.isTrialEligible
            ))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.66))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { disclosureLinks }
                VStack(spacing: PixelHandTheme.Space.md) { disclosureLinks }
            }
            .font(.footnote.weight(.medium))
            .tint(.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var disclosureLinks: some View {
        Button("Restore Purchases") {
            Task { await store.restore() }
        }
        .disabled(store.isWorking)
        .accessibilityIdentifier("ph.paywall.restore")
        Link("Terms of Use", destination: SubscriptionCopy.termsOfUseURL)
        Link("Privacy Policy", destination: SubscriptionCopy.privacyPolicyURL)
    }

    private var alreadyPro: some View {
        VStack(spacing: PixelHandTheme.Space.md) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                ProBadge()
                Text("You have Pixel Hand Pro. Everything is unlocked.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PixelHandTheme.Brand.mint)
            }
            .accessibilityElement(children: .combine)
            Button("Done") { finish() }
                .buttonStyle(.ph(.secondary, size: .regular))
                .accessibilityIdentifier("ph.paywall.done")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func card(highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
        return shape
            .fill(highlighted ? PixelHandTheme.Brand.screenRaised : Color.white.opacity(0.05))
            .overlay(
                shape.strokeBorder(
                    highlighted ? PixelHandTheme.Brand.sky : PixelHandTheme.Brand.tileStroke,
                    lineWidth: highlighted ? PixelHandTheme.Stroke.selection : 1
                )
            )
            .shadow(color: highlighted ? PixelHandTheme.Brand.cobalt.opacity(0.4) : .clear, radius: 14)
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

/// A plan card's radio: a ring, filled with a lit 3 × 3 dot block when on.
private struct PlanRadio: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? PixelHandTheme.Brand.sky : Color.white.opacity(0.35), lineWidth: 2)
            if isOn {
                Canvas { context, size in
                    let pitch: CGFloat = 3.2, dot: CGFloat = 2.5
                    let o = (size.width - pitch * 3) / 2
                    for y in 0..<3 {
                        for x in 0..<3 where x == 1 || y == 1 {
                            let rect = CGRect(x: o + CGFloat(x) * pitch + (pitch - dot) / 2, y: o + CGFloat(y) * pitch + (pitch - dot) / 2, width: dot, height: dot)
                            context.fill(Path(roundedRect: rect, cornerRadius: dot * 0.3), with: .color(PixelHandTheme.Brand.phosphor))
                        }
                    }
                }
                .shadow(color: PixelHandTheme.Brand.glow.opacity(0.8), radius: 2)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
