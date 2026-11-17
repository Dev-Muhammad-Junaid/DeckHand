//
//  LoomKitTestAlwaysTrustProvider.swift
//  LoomKitTests
//
//  Loopback handshakes need an explicit trust decision: since Loom 2.2.16 a
//  receiver without a trust provider treats every peer as requiring approval.
//

@testable import Loom
import Foundation

@MainActor
final class LoomKitTestAlwaysTrustProvider: LoomTrustProvider {
    func evaluateTrust(for peer: LoomPeerIdentity) async -> LoomTrustDecision {
        .trusted
    }

    func evaluateTrustOutcome(for peer: LoomPeerIdentity) async -> LoomTrustEvaluation {
        LoomTrustEvaluation(decision: .trusted, shouldShowAutoTrustNotice: false)
    }

    func grantTrust(to peer: LoomPeerIdentity) async throws {}

    func revokeTrust(for deviceID: UUID) async throws {}
}
