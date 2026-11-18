//
//  PairingMessage.swift
//  PixelHandCore
//
//  Domain: pairing and trust. Today, the Allow / Deny handshake. Persistent
//  pairing (S4: code, QR, "Forget device") adds its messages here. Owned by
//  the pairing lane (`DeviceAuthorizationManager`, `PairingHandler`, the
//  remote's approval UI).
//

import Foundation

public enum PairingMessage: Codable, Sendable, Equatable {
    /// Mac → remote: where this device's request stands. Pushed on connect
    /// ("pending"), on the user's decision, and on expiry ("denied").
    case authorizationStatus(state: AuthState)
    /// Remote → Mac: "what's my state?" A resync for a lost push. The Mac's
    /// `PreApprovalGate` keeps a few of these while the request is pending
    /// and they are answered right after approval.
    case requestAuthorizationStatus
}

/// The Mac's decision about a remote.
public enum AuthState: String, Codable, Sendable, CaseIterable {
    case pending
    case granted
    case denied
}
