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
//  inside its bottom-trailing corner, and a tap anywhere on it opens the paywall for that
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
                // Anchored inside the control's bottom-trailing corner, so
                // it never hangs off a header circle's edge (VQ-026).
                .overlay(alignment: .bottomTrailing) {
                    ProLockBadge()
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

/// The small lock on a locked control: the lock glyph in dots on the
/// icon's sky → cobalt tile.
struct ProLockBadge: View {
    var body: some View {
        PHGlyph(glyph: PixelGlyphs.lock, pitch: 1.4)
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PixelHandTheme.Brand.tileGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: PixelHandTheme.Brand.cobalt.opacity(0.5), radius: 3)
            .accessibilityHidden(true)
    }
}

extension ProFeature {
    /// The pixel glyph for this feature on the paywall and locked cards.
    var glyph: GlyphBitmap {
        switch self {
        case .trackpad: PixelGlyphs.pointer
        case .keyboard: PixelGlyphs.keyboard
        case .mediaKeys: PixelGlyphs.play
        case .decks: PixelGlyphs.deck
        case .mirror: PixelGlyphs.screen
        case .capture: PixelGlyphs.capture
        case .multipleMacs: PixelGlyphs.mac
        case .sharing: PixelGlyphs.share
        case .ai: PixelGlyphs.ask
        }
    }
}
