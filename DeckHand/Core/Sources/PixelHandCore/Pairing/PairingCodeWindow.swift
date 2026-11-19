//
//  PairingCodeWindow.swift
//  PixelHandCore
//
//  The Mac's one pairing code at a time, and the rules for using it (S4):
//
//  - A code is valid for `lifetime` (5 minutes) from when it was shown.
//  - It pairs exactly one device. The first right answer uses it up; the
//    same code sent again, by that device or any other, finds no code.
//  - Wrong answers are counted across every device. The
//    `maxWrongAttempts`-th wrong answer burns the code and locks pairing for
//    `lockoutDuration`; the Mac can't show a new code until then.
//  - A clock that jumps backwards ends the code rather than extending it.
//
//  Pure state with the time passed in, so every rule is tested on Linux.
//  The Mac's `DeviceAuthorizationManager` owns one and calls `verify` with
//  the identity key the remote proved in the Loom handshake.
//

import Foundation

public struct PairingCodeWindow: Equatable, Sendable {
    /// How long a code stays valid after the Mac shows it.
    public static let lifetime: TimeInterval = 5 * 60
    /// Wrong answers allowed per code; the last one burns it.
    public static let maxWrongAttempts = 5
    /// How long pairing stays locked after the code is burned.
    public static let lockoutDuration: TimeInterval = 60
    /// How far the clock may step back (NTP adjustments) before an active
    /// code is treated as expired.
    public static let clockSkewTolerance: TimeInterval = 2

    public enum State: Equatable, Sendable {
        /// No code. Pairing by code isn't possible until the Mac shows one.
        case idle
        /// A code is showing on the Mac.
        case active(code: PairingCode, issuedAt: Date, wrongAttempts: Int)
        /// The code paired the device with this identity key.
        case used(identityKeyID: String, at: Date)
        /// Too many wrong answers; no code until `until`.
        case lockedOut(until: Date)
    }

    public private(set) var state: State = .idle

    public init() {}

    // MARK: - The Mac's side

    public enum IssueResult: Equatable, Sendable {
        case issued(code: PairingCode, expiresAt: Date)
        case lockedOut(until: Date)
    }

    /// Shows `code`, replacing any code already showing (with a fresh
    /// attempt count). Refused while locked out.
    @discardableResult
    public mutating func issue(_ code: PairingCode, now: Date) -> IssueResult {
        refresh(now: now)
        if case let .lockedOut(until) = state {
            return .lockedOut(until: until)
        }
        state = .active(code: code, issuedAt: now, wrongAttempts: 0)
        return .issued(code: code, expiresAt: now.addingTimeInterval(Self.lifetime))
    }

    /// Shows a new random code.
    @discardableResult
    public mutating func issue(now: Date) -> IssueResult {
        issue(PairingCode.generate(), now: now)
    }

    /// Stops showing the code (the user closed it). A lockout stays.
    public mutating func cancel() {
        if case .lockedOut = state { return }
        state = .idle
    }

    /// Moves an expired code or a finished lockout to `.idle`. Call it from
    /// a UI timer; `verify` and `issue` call it themselves.
    public mutating func refresh(now: Date) {
        switch state {
        case let .active(_, issuedAt, _) where Self.isExpired(issuedAt: issuedAt, now: now):
            state = .idle
        case let .lockedOut(until) where now >= until:
            state = .idle
        default:
            break
        }
    }

    /// What the Mac should show right now.
    public enum Display: Equatable, Sendable {
        case none
        case code(PairingCode, expiresAt: Date, attemptsLeft: Int)
        case lockedOut(until: Date)
        case paired(identityKeyID: String)
    }

    public func display(now: Date) -> Display {
        switch state {
        case .idle:
            return .none
        case let .active(code, issuedAt, wrongAttempts):
            if Self.isExpired(issuedAt: issuedAt, now: now) { return .none }
            return .code(
                code,
                expiresAt: issuedAt.addingTimeInterval(Self.lifetime),
                attemptsLeft: Self.maxWrongAttempts - wrongAttempts
            )
        case let .used(identityKeyID, _):
            return .paired(identityKeyID: identityKeyID)
        case let .lockedOut(until):
            return now >= until ? .none : .lockedOut(until: until)
        }
    }

    // MARK: - A remote's submission

    /// Checks a code a remote submitted.
    ///
    /// - Parameters:
    ///   - submission: The text from `pairing.submitCode`, as received.
    ///     Anything that isn't a valid code (bad check digit, letters, too
    ///     long) is a wrong answer: the remote checks the digit before
    ///     sending, so a malformed code on the wire isn't a typo.
    ///   - identityKeyID: The Loom identity key the remote proved. Empty
    ///     means unproven: refused without touching the code.
    ///   - now: The current time.
    public mutating func verify(_ submission: String, identityKeyID: String, now: Date) -> PairingCodeResult {
        guard !identityKeyID.isEmpty else { return .noActiveCode }

        if case let .active(_, issuedAt, _) = state, Self.isExpired(issuedAt: issuedAt, now: now) {
            state = .idle
            return .expired
        }
        refresh(now: now)

        switch state {
        case .idle, .used:
            // Nothing to guess, so nothing is counted. A replay of a used
            // code lands here.
            return .noActiveCode

        case let .lockedOut(until):
            return .lockedOut(retryAfter: Self.secondsUntil(until, from: now))

        case let .active(code, issuedAt, wrongAttempts):
            if let submitted = PairingCode(submission), submitted.constantTimeEquals(code) {
                state = .used(identityKeyID: identityKeyID, at: now)
                return .accepted
            }
            let wrong = wrongAttempts + 1
            if wrong >= Self.maxWrongAttempts {
                let until = now.addingTimeInterval(Self.lockoutDuration)
                state = .lockedOut(until: until)
                return .lockedOut(retryAfter: Self.secondsUntil(until, from: now))
            }
            state = .active(code: code, issuedAt: issuedAt, wrongAttempts: wrong)
            return .wrongCode(attemptsLeft: Self.maxWrongAttempts - wrong)
        }
    }

    // MARK: - Helpers

    private static func isExpired(issuedAt: Date, now: Date) -> Bool {
        now >= issuedAt.addingTimeInterval(lifetime)
            || now < issuedAt.addingTimeInterval(-clockSkewTolerance)
    }

    private static func secondsUntil(_ date: Date, from now: Date) -> Int {
        max(1, Int(date.timeIntervalSince(now).rounded(.up)))
    }
}
