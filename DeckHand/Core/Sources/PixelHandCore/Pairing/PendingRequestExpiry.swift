//
//  PendingRequestExpiry.swift
//  PixelHandCore
//
//  When the Mac gives up on a request nobody has answered (VQ-037).
//
//  A request waits `ApprovalStatusCopy.pendingRequestTimeout` (45 s) for
//  Allow or Deny. While the Mac shows a pairing code, though, the person on
//  the remote may be typing it: dropping the request then threw away a code
//  that was still good for minutes. So a request lives as long as a code is
//  showing, up to the code's own five minutes, and is checked again when
//  that code ends (expired, used, or closed).
//
//  Pure, so it is tested here; `DeviceAuthorizationManager` asks it on a
//  timer.
//

import Foundation

public enum PendingRequestExpiry {
    public enum Decision: Equatable, Sendable {
        /// Give up now and tell the remote it timed out.
        case expire
        /// Keep waiting; ask again at this time.
        case checkAgain(at: Date)
    }

    /// The longest a request can live: the base wait plus one code's life.
    public static let hardLimit: TimeInterval = ApprovalStatusCopy.pendingRequestTimeout + PairingCodeWindow.lifetime

    /// What to do with a request that arrived at `requestedAt`.
    ///
    /// - Parameters:
    ///   - codeShowingUntil: When the pairing code the Mac shows now
    ///     expires, or `nil` when no code is showing.
    ///   - now: The current time.
    public static func decide(requestedAt: Date, codeShowingUntil: Date?, now: Date) -> Decision {
        let base = requestedAt.addingTimeInterval(ApprovalStatusCopy.pendingRequestTimeout)
        let limit = requestedAt.addingTimeInterval(hardLimit)
        var deadline = base
        if let codeShowingUntil, codeShowingUntil > now {
            deadline = max(base, min(codeShowingUntil, limit))
        }
        // A clock that jumped back must not stretch the wait past the limit.
        if now >= deadline || now >= limit { return .expire }
        return .checkAgain(at: deadline)
    }
}
