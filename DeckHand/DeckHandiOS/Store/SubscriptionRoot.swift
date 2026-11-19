//
//  SubscriptionRoot.swift
//  DeckHandiOS
//
//  `.subscriptionStore()` at the app root (one line in DeckHandApp.swift,
//  inside `.environmentObject(settings)`):
//
//  - starts StoreKit (transaction listener, products, entitlement) and
//    re-reads the entitlement whenever the app comes back to the front;
//  - publishes `\.entitlements` to every view;
//  - shows the "this isn't your free Mac" paywall the picker raises;
//  - when Pro ends, turns off clipboard sharing, the one Pro feature that
//    is a stored setting rather than a control you press.
//

import SwiftUI

extension View {
    /// Pixel Hand Pro for everything below: `\.entitlements` and the
    /// paywalls. Apply once, at the root, inside `.environmentObject`.
    func subscriptionStore() -> some View {
        modifier(SubscriptionRootModifier())
    }
}

private struct SubscriptionRootModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: DeckHandSettings
    @Bindable private var store = SubscriptionStore.shared

    func body(content: Content) -> some View {
        content
            .environment(\.entitlements, store.entitlement)
            .sheet(item: $store.macPaywall) { request in
                PaywallView(reason: .anotherMac(request))
            }
            .task { store.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await store.refresh() }
                }
            }
            .onChange(of: store.entitlement) { _, entitlement in
                // Only StoreKit's settled answer turns things off, so a slow
                // answer at launch never clears a subscriber's setting. This
                // also catches Pro that ended while the app was closed.
                if entitlement.isSettled, !entitlement.allows(.sharing), settings.clipboardSync {
                    settings.clipboardSync = false
                }
            }
    }
}
