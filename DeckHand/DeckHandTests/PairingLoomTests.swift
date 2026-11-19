//
//  PairingLoomTests.swift
//  DeckHandTests
//
//  The Loom side of pairing (S4): only an identity whose key Loom verified,
//  and whose key ID really is that key's, becomes a pairing candidate. The
//  rules themselves are tested in PixelHandCore (`TrustListTests`,
//  `PairingCodeWindowTests`).
//

import CryptoKit
import Foundation
import Loom
import Testing

@Suite struct PairingLoomTests {

    private func identity(
        publicKey: Data,
        keyID: String? = nil,
        authenticated: Bool = true,
        deviceType: DeviceType = .iPad
    ) -> LoomPeerIdentity {
        LoomPeerIdentity(
            deviceID: UUID(),
            name: "Test iPad",
            deviceType: deviceType,
            iCloudUserID: nil,
            identityKeyID: keyID ?? LoomIdentityManager.keyID(for: publicKey),
            identityPublicKey: publicKey,
            isIdentityAuthenticated: authenticated,
            endpoint: "test"
        )
    }

    @Test("A verified identity becomes a candidate keyed on its identity key")
    func verifiedIdentity() throws {
        let key = P256.Signing.PrivateKey().publicKey.x963Representation
        let peer = identity(publicKey: key)
        let candidate = try #require(TrustCandidate(identity: peer))
        #expect(candidate.identityKeyID == LoomIdentityManager.keyID(for: key))
        #expect(candidate.deviceID == peer.deviceID)
        #expect(candidate.kind == .iPad)
    }

    @Test("An unverified identity, or a key ID that isn't the key's, is not a candidate")
    func unverifiedIdentity() {
        let key = P256.Signing.PrivateKey().publicKey.x963Representation
        let other = P256.Signing.PrivateKey().publicKey.x963Representation
        #expect(TrustCandidate(identity: identity(publicKey: key, authenticated: false)) == nil)
        #expect(TrustCandidate(identity: identity(publicKey: key, keyID: LoomIdentityManager.keyID(for: other))) == nil)
    }

    @Test("Device types map to paired-device kinds")
    func kinds() {
        #expect(PairedDeviceKind(DeviceType.mac) == .mac)
        #expect(PairedDeviceKind(DeviceType.iPhone) == .iPhone)
        #expect(PairedDeviceKind(DeviceType.unknown) == .other)
    }
}
