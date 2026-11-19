//
//  DeckHandHandshakeTrustProvider.swift
//  DeckHandMac
//

import Foundation
import Loom

/// Pixel Hand's trust hooks into Loom's handshake, backed by the Mac's
/// `PairedDeviceStore` (S4).
///
/// - `evaluateTrustOutcome`: a device finishes the handshake only if it
///   proved ownership of the identity key it presented. Loom 2.x fails
///   closed (`.requiresApproval` is a denial), so every verified device is
///   `.trusted` here; paired or not is decided right after, by
///   `DeviceAuthorizationManager` through `PairedDeviceStore.admission(for:)`
///   (paired: no prompt; unknown: Allow / Deny or a pairing code). Approval
///   still gates every command: `ControlReceiver` only observes handles the
///   manager authorized.
/// - `grantTrust(to:)`: pairs the device (the manager calls it when a
///   pairing code is accepted).
/// - `revokeTrust(for:)`: forgets what was paired with that device ID.
@MainActor
final class DeckHandHandshakeTrustProvider: LoomTrustProvider {
    private let store: PairedDeviceStore

    init(store: PairedDeviceStore = .shared) {
        self.store = store
    }

    nonisolated func evaluateTrust(for peer: LoomPeerIdentity) async -> LoomTrustDecision {
        await evaluateTrustOutcome(for: peer).decision
    }

    nonisolated func evaluateTrustOutcome(for peer: LoomPeerIdentity) async -> LoomTrustEvaluation {
        guard TrustCandidate(identity: peer) != nil else {
            return LoomTrustEvaluation(decision: .denied, shouldShowAutoTrustNotice: false)
        }
        return LoomTrustEvaluation(decision: .trusted, shouldShowAutoTrustNotice: false)
    }

    /// Pairs `peer` by its verified identity key. Throws when the key
    /// wasn't verified.
    func grantTrust(to peer: LoomPeerIdentity) async throws {
        guard let candidate = TrustCandidate(identity: peer) else {
            throw TrustList.TrustError.invalidIdentityKeyID
        }
        try store.pair(candidate, method: .code)
    }

    func revokeTrust(for deviceID: UUID) async throws {
        store.forgetAll(deviceID: deviceID)
    }
}
