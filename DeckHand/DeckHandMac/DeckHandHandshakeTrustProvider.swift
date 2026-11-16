//
//  DeckHandHandshakeTrustProvider.swift
//  DeckHandMac
//

import Foundation
import Loom

/// Lets an identity-verified device finish Loom's handshake so the Mac can ask
/// Allow / Deny at the app level.
///
/// Loom 2.x fails closed: a trust provider that answers `.requiresApproval`
/// denies the handshake before the device can reach `DeviceAuthorizationManager`.
/// Pixel Hand's own approval runs after the session is up and is deliberately
/// not persisted, so the handshake only checks that the peer proved ownership
/// of the identity key it presented. Approval still gates every command:
/// `ControlReceiver` only observes handles that `DeviceAuthorizationManager`
/// authorized.
@MainActor
final class DeckHandHandshakeTrustProvider: LoomTrustProvider {
    nonisolated func evaluateTrust(for peer: LoomPeerIdentity) async -> LoomTrustDecision {
        await evaluateTrustOutcome(for: peer).decision
    }

    nonisolated func evaluateTrustOutcome(for peer: LoomPeerIdentity) async -> LoomTrustEvaluation {
        guard peer.isIdentityAuthenticated,
              let identityKeyID = peer.identityKeyID,
              let identityPublicKey = peer.identityPublicKey,
              LoomIdentityManager.keyID(for: identityPublicKey) == identityKeyID else {
            return LoomTrustEvaluation(decision: .denied, shouldShowAutoTrustNotice: false)
        }
        return LoomTrustEvaluation(decision: .trusted, shouldShowAutoTrustNotice: false)
    }

    /// Nothing is persisted: approval lasts for one host launch, by design.
    nonisolated func grantTrust(to peer: LoomPeerIdentity) async throws {}

    nonisolated func revokeTrust(for deviceID: UUID) async throws {}
}
