//
//  FreeMacBadge.swift
//  DeckHandiOS
//
//  The picker's side of the one-Mac rule. A free user sees a lock on every
//  Mac but their free one; tapping it still works the normal way, and the
//  picker's `SubscriptionStore.shared.admitMac(...)` check opens the paywall
//  (with "Use this Mac instead").
//

import SwiftUI

extension View {
    /// Marks a Mac card with the Pro lock when the free plan doesn't cover
    /// that Mac. Display only; the picker's `admitMac` check does the
    /// gating.
    func freeMacBadge(deviceID: UUID) -> some View {
        modifier(FreeMacBadgeModifier(deviceID: deviceID))
    }
}

private struct FreeMacBadgeModifier: ViewModifier {
    let deviceID: UUID
    @Environment(\.entitlements) private var entitlements
    private let store = SubscriptionStore.shared

    func body(content: Content) -> some View {
        // Reading `entitlements` ties the badge to Pro starting or ending.
        let locked = !entitlements.isPro && store.isLockedMac(deviceID: deviceID)
        // The PRO badge, as on the board's My Macs: inside the tile's
        // top-trailing corner, above everything, never clipped (OT-14).
        content
            .controlBadge(locked ? .proLabel : nil, style: .inset(4))
            .accessibilityHint(locked ? "Needs \(SubscriptionCopy.productName): the free plan works with one Mac" : "")
    }
}
