//
//  PairingMessage.swift
//  PixelHandCore
//
//  Domain: pairing and trust. The Allow / Deny handshake, and persistent
//  pairing (S4): a code typed or scanned on the remote, the Mac's answer,
//  whether the remote is on the Mac's paired list, and "Forget". Owned by
//  the pairing lane (`DeviceAuthorizationManager`, `PairingHandler`, the
//  remote's approval UI).
//
//  Trust itself is keyed on the Loom identity key the remote proved in the
//  handshake (`TrustList`), never on anything carried in these messages.
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
    /// Remote → Mac: a pairing code the user typed or scanned. Accepted
    /// while the request is pending (the gate hands it to the Mac's pairing
    /// logic instead of dropping it) and once allowed. The Mac answers with
    /// `codeResult`.
    case submitCode(code: String)
    /// Mac → remote: the answer to `submitCode`. On `.accepted` the Mac has
    /// added this device to its paired list and also sends
    /// `authorizationStatus(.granted)` and `pairedStatus(paired: true)`.
    case codeResult(result: PairingCodeResult)
    /// Mac → remote: whether this device is on the Mac's paired list. Sent
    /// with every grant and whenever it changes. `false` after a grant that
    /// was `true` means the Mac forgot this device; the Mac then ends the
    /// session.
    case pairedStatus(paired: Bool)
    /// Remote → Mac: the user chose "Forget" for this Mac. The Mac removes
    /// this device from its paired list and ends the session.
    case forget
    /// Mac → remote: why the request was refused (protocol 14, VQ-002).
    /// Sent just before `authorizationStatus(.denied)`, so the remote can
    /// tell a person's Deny from a rule. A remote that doesn't know it
    /// still sees the `denied` after it.
    case refused(reason: AuthRefusal)
}

/// Why the Mac refused a request (`pairing.refused`).
public enum AuthRefusal: String, Codable, Sendable, CaseIterable {
    /// A person clicked Deny on the Mac.
    case declined
    /// Nobody answered before the request expired.
    case timedOut
    /// Not paired, and it reached the Mac from another network (a VPN,
    /// Tailscale, cellular). Pair on the same network first.
    case notPairedRemote
    /// The handshake didn't prove an identity key.
    case unverified
    /// A newer request from the same device replaced this one.
    case replaced
}

/// The Mac's decision about a remote.
public enum AuthState: String, Codable, Sendable, CaseIterable {
    case pending
    case granted
    case denied
}

/// The Mac's answer to a pairing code (`PairingCodeWindow.verify`).
public enum PairingCodeResult: Codable, Sendable, Equatable {
    /// Right code: this device is paired.
    case accepted
    /// Wrong code; `attemptsLeft` more before the code is burned.
    case wrongCode(attemptsLeft: Int)
    /// Too many wrong codes. The Mac shows no code for `retryAfter` seconds.
    case lockedOut(retryAfter: Int)
    /// The code's five minutes ran out. Show a new one on the Mac.
    case expired
    /// The Mac isn't showing a code (none issued, already used, or
    /// cancelled).
    case noActiveCode
}
