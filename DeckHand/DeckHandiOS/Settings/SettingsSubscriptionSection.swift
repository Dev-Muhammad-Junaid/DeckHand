//
//  SettingsSubscriptionSection.swift
//  DeckHandiOS
//
//  Settings › Subscription (Store lane): the plan this device is on, a way
//  to buy, manage or fix it, Restore Purchases, and which Mac the free plan
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if entitlements.isPro {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(DeckHandTheme.mint)
                    }
                    Text(row.title)
                }
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(row.needsPaymentAttention ? DeckHandTheme.warning : .secondary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            if row.needsPaymentAttention {
                Link("Update payment method", destination: Self.billingURL)
            }

            if entitlements.isPro, entitlements.isSettled {
                Button("Manage subscription") { isManagePresented = true }
            } else {
                Button(store.isTrialEligible ? "Try Pixel Hand Pro free for 2 weeks" : "See Pixel Hand Pro") {
                    isPaywallPresented = true
                }
            }

            Button("Restore Purchases") {
                Task { await store.restore() }
            }
            .disabled(store.isWorking)

            if let error = store.errorMessage, !isPaywallPresented {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !entitlements.isPro, let freeMac = store.freeMac {
                LabeledContent("Free plan's Mac", value: freeMac.name)
            }
        } header: {
            Text("Subscription")
        } footer: {
            Text("The free plan includes the trackpad, keyboard and media keys with one Mac. Pro adds chips and decks, the live mirror, capture and text recognition, clipboard sharing and all your Macs. Family Sharing is supported.")
        }
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView(reason: .settings)
        }
        .manageSubscriptionsSheet(isPresented: $isManagePresented)
        .onChange(of: isManagePresented) { _, isPresented in
            if !isPresented { Task { await store.refresh() } }
        }
    }
}
