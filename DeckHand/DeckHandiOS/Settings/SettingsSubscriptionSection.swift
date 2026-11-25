//
//  SettingsSubscriptionSection.swift
//  DeckHandiOS
//
//  Settings › Subscription (Store lane): the plan this device is on, a way
//  to buy, manage or fix it, Restore purchases, and which Mac the free plan
//  covers.
//

import StoreKit
import SwiftUI

struct SettingsSubscriptionSection: View {
    @Environment(\.entitlements) private var entitlements
    @State private var isPaywallPresented = false
    @State private var isManagePresented = false
    private let store = SubscriptionStore.shared

    /// Apple's page for updating the payment method on the account.
    private static let billingURL = URL(string: "https://apps.apple.com/account/billing")!

    private var row: SubscriptionCopy.StatusRow {
        SubscriptionCopy.statusRow(
            entitlements,
            displayPrice: { store.products[$0]?.displayPrice },
            formatDate: { $0.formatted(date: .abbreviated, time: .omitted) }
        )
    }

    var body: some View {
        Section {
            HStack(spacing: PixelHandTheme.Space.md) {
                // One PRO mark per row (VQ-014): the dot-matrix one on the
                // trailing edge. The leading tile is the same glyph tile as
                // every other row, lit while Pro is on.
                SettingsRowIcon(glyph: PixelGlyphs.lock, isLit: entitlements.isPro)
                VStack(alignment: .leading, spacing: 3) {
                    if store.isDeveloperUnlockActive {
                        Text("Pro unlocked for testing")
                            .font(.headline)
                        Text("Every Pro feature is on without a subscription. Turn this off below to see the free plan.")
                            .font(.footnote)
                            .foregroundStyle(PixelHandTheme.ink2)
                    } else {
                        Text(row.title)
                            .font(.headline)
                        Text(row.detail)
                            .font(.footnote)
                            .foregroundStyle(row.needsPaymentAttention ? PixelHandTheme.warning : PixelHandTheme.ink2)
                    }
                }
                Spacer(minLength: 8)
                if entitlements.isPro {
                    // The LED-panel PRO mark, small enough for a row.
                    DotMatrixText("PRO", pitch: 2, label: "Pro", showsUnlit: true, glows: false)
                        .foregroundStyle(PixelHandTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            if row.needsPaymentAttention, !store.isDeveloperUnlockActive {
                Link("Update payment method", destination: Self.billingURL)
            }

            if store.isDeveloperUnlockActive {
                // Nothing to buy or manage while testing.
            } else if entitlements.isPro, entitlements.isSettled {
                Button("Manage subscription") { isManagePresented = true }
                    .accessibilityIdentifier("ph.settings.manageSubscription")
                    .manageSubscriptionsSheet(isPresented: $isManagePresented)
            } else {
                Button(store.isTrialEligible ? "Try Pixel Hand Pro free for 2 weeks" : "See Pixel Hand Pro") {
                    isPaywallPresented = true
                }
                .accessibilityIdentifier("ph.settings.subscribe")
                // On the row itself, not the Section: a Section passes its
                // modifiers to every row, so the sheet was attached several
                // times and Settings closed instead of showing the paywall
                // (VQ-055). The paywall opens at once and loads prices
                // itself.
                .sheet(isPresented: $isPaywallPresented) {
                    PaywallView(reason: .settings)
                }
            }

            Button("Restore purchases") {
                Task { await store.restore() }
            }
            .disabled(store.isWorking)
            .accessibilityIdentifier("ph.settings.restore")

            if let error = store.errorMessage, !isPaywallPresented {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !entitlements.isPro, let freeMac = store.freeMac {
                LabeledContent("Free plan’s Mac", value: freeMac.name)
            }

            if store.isDeveloperUnlockAvailable {
                Toggle(isOn: Binding(
                    get: { store.isDeveloperUnlocked },
                    set: { store.setDeveloperUnlocked($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unlock Pro for testing")
                        Text("Development and TestFlight builds only. App Store builds never show this.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("ph.settings.developerUnlock")
            }
        } header: {
            SettingsSectionHeader("Subscription", glyph: PixelGlyphs.add)
        } footer: {
            Text("The free plan includes the trackpad, keyboard and media keys with one Mac. Pro adds chips and decks, the live mirror, capture and text recognition, clipboard sharing and all your Macs. Family Sharing is supported.")
        }
        .onChange(of: isManagePresented) { _, isPresented in
            if !isPresented { Task { await store.refresh() } }
        }
    }
}
