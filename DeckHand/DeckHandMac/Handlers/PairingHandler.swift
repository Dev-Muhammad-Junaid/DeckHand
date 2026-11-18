//
//  PairingHandler.swift
//  DeckHandMac
//
//  Domain: pairing. Answers the remote's approval-status resync. Approval
//  itself (Allow / Deny, the 45 s expiry, `PreApprovalGate`) lives in
//  `DeviceAuthorizationManager`. Owned by the pairing lane (S4).
//

import Foundation
import LoomKit

@MainActor
final class PairingHandler: DomainHandler {
    func handle(_ message: PairingMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case .requestAuthorizationStatus:
            // Resync path: messages are only consumed for *authorized*
            // connections (DeviceAuthorizationManager gates the handoff),
            // so reaching this handler means the answer is "granted".
            // The few queries sent while the request was pending are the
            // only messages PreApprovalGate keeps; they're answered here
            // right after approval — healing any lost/failed `granted` push.
            do {
                try await connection.send(.pairing(.authorizationStatus(state: .granted)))
            } catch {
                DeckHandLog.connection.error("Failed to answer auth-status query: \(error.localizedDescription, privacy: .public)")
            }

        case .authorizationStatus:
            break // Mac → remote only
        }
    }
}
