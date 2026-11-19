//
//  PairingHandler.swift
//  DeckHandMac
//
//  Domain: pairing, for connections already allowed. Answers the remote's
//  approval-status resync, takes a pairing code from a device allowed for
//  this session (S4), and the remote's "Forget this Mac". Approval itself
//  (Allow / Deny, the 45 s expiry, `PreApprovalGate`, codes sent while
//  pending) lives in `DeviceAuthorizationManager`. Owned by the pairing lane.
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
            // right after approval — healing any lost/failed `granted` push
            // (and the paired status sent with it).
            let paired = DeviceAuthorizationManager.shared.isPaired(connectionID: connection.id)
            do {
                try await connection.send(.pairing(.authorizationStatus(state: .granted)))
                try await connection.send(.pairing(.pairedStatus(paired: paired)))
            } catch {
                DeckHandLog.connection.error("Failed to answer auth-status query: \(error.localizedDescription, privacy: .public)")
            }

        case let .submitCode(code):
            await DeviceAuthorizationManager.shared.handleSubmittedCode(code, from: connection)

        case .forget:
            DeviceAuthorizationManager.shared.remoteAskedToForget(connection)

        case .authorizationStatus, .codeResult, .pairedStatus:
            break // Mac → remote only
        }
    }
}
