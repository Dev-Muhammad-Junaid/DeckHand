//
//  RemoteConnect.swift
//  DeckHandiOS
//
//  S15: how the picker dials a Mac.
//
//  - Seen by Bonjour: dialled as before.
//  - Not seen by Bonjour (found through a saved VPN host): only a paired
//    Mac, and Loom's handshake is pinned to the identity key stored when it
//    paired, never the key the probe answer advertised. After the
//    handshake the proven key and device ID are checked against the pin
//    once more. A Mac that isn't paired is refused before any connection.
//
//  The rules are PixelHandCore's `RemoteAccessPolicy` (tested on Linux).
//

import Foundation
import Loom
import LoomKit

enum RemoteConnectError: LocalizedError {
    case refused(RemoteAccessPolicy.DialRefusal)
    case identityMismatch

    var errorDescription: String? {
        switch self {
        case let .refused(reason):
            reason.message
        case .identityMismatch:
            "The Mac at that address isn’t the one you paired with, so Pixel Hand didn’t connect. Check the address in Settings, or pair with your Mac again."
        }
    }
}

@MainActor
enum RemoteConnect {

    static func plan(for peer: LoomPeerSnapshot) -> RemoteAccessPolicy.DialPlan {
        RemoteAccessPolicy.dialPlan(
            for: RemoteAccessPolicy.PeerReach(
                deviceID: peer.deviceID,
                isNearby: peer.isNearby,
                advertisedIdentityKeyID: peer.advertisement.identityKeyID
            ),
            pairedMacs: TrustList(devices: PairedMacsStore.shared.macs)
        )
    }

    /// Dials `peer` following the plan above.
    static func connect(_ peer: LoomPeerSnapshot, using context: LoomContext) async throws -> LoomConnectionHandle {
        switch plan(for: peer) {
        case .local:
            return try await context.connect(peer)

        case let .refuse(reason):
            DeckHandLog.connection.error("📡 Not dialling \(peer.name, privacy: .public) off the local network: \(String(describing: reason), privacy: .public)")
            throw RemoteConnectError.refused(reason)

        case let .remote(pinned):
            guard let pin = LoomPeerIdentityPin(identityKeyID: pinned.identityKeyID) else {
                throw RemoteConnectError.refused(.notPaired)
            }
            DeckHandLog.connection.info("📡 Dialling paired \(peer.name, privacy: .public) over a VPN, pinned to its stored key")
            let handle = try await context.connect(peer, pinnedIdentity: pin)
            let proven = await handle.verifiedPeerIdentity()
            guard RemoteAccessPolicy.verify(
                provenIdentityKeyID: proven?.identityKeyID,
                provenDeviceID: proven?.deviceID,
                pinned: pinned
            ) else {
                DeckHandLog.connection.error("📡 \(peer.name, privacy: .public) proved another identity than the pin; disconnecting")
                await handle.disconnect()
                throw RemoteConnectError.identityMismatch
            }
            return handle
        }
    }
}
