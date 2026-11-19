//
//  RequiresPro.swift
//  DeckHandiOS
//
//  The only gating surface other lanes use. No StoreKit here or in their
//  files:
//
//      @Environment(\.entitlements) private var entitlements
//      if entitlements.allows(.mirror) { … }
//
//      Button("Mirror") { … }
//          .requiresPro(.mirror)
//
//  `.requiresPro` leaves the control as it is when the feature is unlocked
//  (Pro, the free trial, grace and billing retry, or a free feature). When
//  it's locked, the control is dimmed and can't be used, a small lock sits
//  on its corner, and a tap anywhere on it opens the paywall for that
//  feature. VoiceOver reads it as "<label>, Pixel Hand Pro" with the hint
//  "Opens Pixel Hand Pro".
//
//  The paywall is presented by the modifier itself, so it works inside
//  sheets (Settings) and toolbars as well as on the main screen.
//

import SwiftUI

private struct EntitlementsKey: EnvironmentKey {
    static let defaultValue: Entitlement = .unknown
}

extension EnvironmentValues {
    /// What this device may use. Set at the app root by
    /// `.subscriptionStore()`; `.unknown` (nothing unlocked beyond the free
    /// plan) anywhere outside it, such as previews.
    var entitlements: Entitlement {
        get { self[EntitlementsKey.self] }
        set { self[EntitlementsKey.self] = newValue }
    }
}

extension View {
    /// Locks this control behind Pixel Hand Pro when `feature` isn't
    /// unlocked; a tap opens the paywall.
    func requiresPro(_ feature: ProFeature) -> some View {
        modifier(RequiresProModifier(feature: feature))
    }
}

private struct RequiresProModifier: ViewModifier {
    let feature: ProFeature

    @Environment(\.entitlements) private var entitlements
    @State private var isPaywallPresented = false

    func body(content: Content) -> some View {
        if entitlements.allows(feature) {
            content
        } else {
            content
                .disabled(true)
                .opacity(0.45)
                .accessibilityHidden(true)
                .overlay(alignment: .topTrailing) {
                    ProLockBadge()
                        .offset(x: 4, y: -4)
                        .allowsHitTesting(false)
                }
                .overlay {
                    // Outside `.disabled`, so it still takes the tap.
                    Button {
                        isPaywallPresented = true
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(SubscriptionCopy.title(feature)), \(SubscriptionCopy.productName)")
                    .accessibilityHint("Opens \(SubscriptionCopy.productName)")
                }
                .sheet(isPresented: $isPaywallPresented) {
                    PaywallView(reason: .feature(feature))
                }
        }
    }
}

/// The small lock on a locked control.
struct ProLockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(DeckHandTheme.Brand.cobalt))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
