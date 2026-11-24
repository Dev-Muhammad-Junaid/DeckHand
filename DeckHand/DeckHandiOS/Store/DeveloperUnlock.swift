//
//  DeveloperUnlock.swift
//  DeckHandiOS
//
//  "Unlock Pro for testing" (owner request, 2026-11-24): while the
//  subscriptions aren't live in App Store Connect, the owner and testers
//  need every Pro feature without buying. The switch lives in
//  Settings › Subscription and is offered only where it can't leak to
//  customers:
//
//  - Debug builds, always.
//  - Any build that isn't an App Store production install: Xcode and
//    development-signed installs (the owner's Mac build loop) and
//    TestFlight. `AppTransaction.environment` tells them apart; when it
//    can't be read (development installs often have no receipt), the build
//    isn't from the App Store, so the switch is offered.
//
//  An App Store download reports `.production` and never sees the switch;
//  a stored "on" from an earlier test build is ignored there.
//

import Foundation
import StoreKit

enum DeveloperUnlock {
    /// Whether this build may offer "Unlock Pro for testing".
    static func isAvailable() async -> Bool {
        #if DEBUG
        return true
        #else
        do {
            switch try await AppTransaction.shared {
            case let .verified(transaction), let .unverified(transaction, _):
                return transaction.environment != .production
            }
        } catch {
            return true
        }
        #endif
    }

    /// What the app reports while the switch is on: Pro, with no StoreKit
    /// details (no plan dates, nothing to manage or renew).
    static let entitlement = Entitlement(
        status: .active(plan: .yearly, periodEnds: nil, willRenew: nil, renewsTo: nil, familyShared: false),
        evaluatedAt: Date(timeIntervalSince1970: 0)
    )
}
