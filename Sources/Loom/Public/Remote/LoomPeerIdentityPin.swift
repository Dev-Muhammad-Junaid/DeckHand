//
//  LoomPeerIdentityPin.swift
//  Loom
//

import Foundation

/// An identity the caller requires a peer to prove during the authenticated handshake.
///
/// By default a connection plan expects the identity key a peer *advertises* (Bonjour TXT,
/// overlay probe answer or signaling presence). That is the right default on a local
/// network, but an advertisement reached through an overlay host name or a relayed
/// presence record is only as trustworthy as the path that delivered it. A pin replaces
/// the advertised expectation with an identity the caller stored earlier, for example
/// when the two devices first trusted each other, so the session fails with
/// ``LoomError/authenticationFailed`` unless the peer proves exactly that key.
///
/// Pass a pin to ``LoomConnectionCoordinator/connect(hello:localPeer:overlayPeer:signalingSessionID:requiredLocalPort:pinnedPeerIdentity:)``
/// or `LoomContext.connect(_:pinnedIdentity:)` in LoomKit.
public struct LoomPeerIdentityPin: Hashable, Sendable {
    /// The identity key ID the peer must prove (`LoomPeerIdentity.identityKeyID`).
    public let identityKeyID: String
    /// The full public key the peer must prove, when the caller stored it.
    public let identityPublicKey: Data?

    /// Creates a pin.
    ///
    /// Returns `nil` when `identityKeyID` is empty or only whitespace, so an unset value
    /// can never silently turn into "no pin".
    public init?(identityKeyID: String, identityPublicKey: Data? = nil) {
        let trimmed = identityKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == identityKeyID else {
            return nil
        }
        if let identityPublicKey, identityPublicKey.isEmpty {
            return nil
        }
        self.identityKeyID = identityKeyID
        self.identityPublicKey = identityPublicKey
    }

    /// Whether an identity proven in a handshake satisfies this pin.
    public func matches(identityKeyID provenKeyID: String?, identityPublicKey provenPublicKey: Data?) -> Bool {
        guard provenKeyID == identityKeyID else {
            return false
        }
        if let identityPublicKey {
            return provenPublicKey == identityPublicKey
        }
        return true
    }
}
