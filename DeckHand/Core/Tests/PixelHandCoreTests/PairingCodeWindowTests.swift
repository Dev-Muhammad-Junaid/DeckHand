//
//  PairingCodeWindowTests.swift
//  PixelHandCoreTests
//
//  The rules for the Mac's pairing code (S4): five-minute window, one
//  device, lockout after repeated wrong codes, no replay.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct PairingCodeWindowTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let ipad = String(repeating: "a1", count: 32)
    private let attacker = String(repeating: "f0", count: 32)
    private let code = PairingCode("57241250")!
    private let wrong = PairingCode("1111111" + String(DammCheck.checkDigit(for: "1111111")!))!

    private func active(at time: Date? = nil) -> PairingCodeWindow {
        var window = PairingCodeWindow()
        window.issue(code, now: time ?? t0)
        return window
    }

    // MARK: - The happy path

    @Test("The right code from a proven device pairs it")
    func rightCodeIsAccepted() {
        var window = active()
        #expect(window.display(now: t0) == .code(code, expiresAt: t0 + PairingCodeWindow.lifetime, attemptsLeft: 5))
        let r1 = window.verify("5724 1250", identityKeyID: ipad, now: t0 + 10)
        #expect(r1 == .accepted)
        #expect(window.state == .used(identityKeyID: ipad, at: t0 + 10))
        #expect(window.display(now: t0 + 11) == .paired(identityKeyID: ipad))
    }

    @Test("Issuing returns the code and when it expires")
    func issueResult() {
        var window = PairingCodeWindow()
        let r2 = window.issue(code, now: t0)
        #expect(r2 == .issued(code: code, expiresAt: t0 + 300))
        if case let .issued(random, _) = window.issue(now: t0) {
            #expect(DammCheck.isValid(random.digits))
        } else {
            Issue.record("expected a new code")
        }
    }

    // MARK: - One device, no replay

    @Test("A code pairs one device: a second device and a replay find no code")
    func singleUse() {
        var window = active()
        let r3 = window.verify(code.digits, identityKeyID: ipad, now: t0 + 1)
        #expect(r3 == .accepted)
        // The same message replayed by the same device…
        let r4 = window.verify(code.digits, identityKeyID: ipad, now: t0 + 2)
        #expect(r4 == .noActiveCode)
        // …or by anyone else.
        let r5 = window.verify(code.digits, identityKeyID: attacker, now: t0 + 3)
        #expect(r5 == .noActiveCode)
        // Wrong guesses against a used code aren't counted and can't lock.
        for _ in 0..<10 {
            let r6 = window.verify(wrong.digits, identityKeyID: attacker, now: t0 + 4)
            #expect(r6 == .noActiveCode)
        }
        #expect(window.state == .used(identityKeyID: ipad, at: t0 + 1))
    }

    @Test("With no code showing, nothing is accepted or counted")
    func noCodeShowing() {
        var window = PairingCodeWindow()
        let r7 = window.verify(code.digits, identityKeyID: ipad, now: t0)
        #expect(r7 == .noActiveCode)
        #expect(window.state == .idle)
        window.issue(code, now: t0)
        window.cancel()
        let r8 = window.verify(code.digits, identityKeyID: ipad, now: t0)
        #expect(r8 == .noActiveCode)
    }

    @Test("A submission without a proven identity key is refused without counting")
    func unprovenIdentity() {
        var window = active()
        for _ in 0..<10 {
            let r9 = window.verify(code.digits, identityKeyID: "", now: t0 + 1)
            #expect(r9 == .noActiveCode)
        }
        let r10 = window.verify(code.digits, identityKeyID: ipad, now: t0 + 2)
        #expect(r10 == .accepted)
    }

    // MARK: - The five-minute window

    @Test("The code works until just before five minutes and not at five")
    func expiry() {
        var window = active()
        let r11 = window.verify(code.digits, identityKeyID: ipad, now: t0 + 299.9)
        #expect(r11 == .accepted)

        var late = active()
        #expect(late.display(now: t0 + 300) == .none)
        let r12 = late.verify(code.digits, identityKeyID: ipad, now: t0 + 300)
        #expect(r12 == .expired)
        // Once noticed, the code is gone.
        let r13 = late.verify(code.digits, identityKeyID: ipad, now: t0 + 301)
        #expect(r13 == .noActiveCode)
        #expect(late.state == .idle)
    }

    @Test("A clock that jumps backwards ends the code")
    func clockGoesBackwards() {
        var window = active()
        let r14 = window.verify(code.digits, identityKeyID: ipad, now: t0 - 1)
        #expect(r14 == .accepted) // within tolerance

        var jumped = active()
        let r15 = jumped.verify(code.digits, identityKeyID: ipad, now: t0 - 60)
        #expect(r15 == .expired)
    }

    @Test("refresh clears an expired code for the UI")
    func refreshClearsExpired() {
        var window = active()
        window.refresh(now: t0 + 299)
        #expect(window.display(now: t0 + 299) != .none)
        window.refresh(now: t0 + 300)
        #expect(window.state == .idle)
    }

    // MARK: - Wrong codes and lockout

    @Test("Wrong codes count down, then the fifth burns the code and locks")
    func lockout() {
        var window = active()
        for left in stride(from: 4, through: 1, by: -1) {
            let r16 = window.verify(wrong.digits, identityKeyID: attacker, now: t0 + 5)
            #expect(r16 == .wrongCode(attemptsLeft: left))
        }
        #expect(window.display(now: t0 + 5) == .code(code, expiresAt: t0 + 300, attemptsLeft: 1))
        let r17 = window.verify(wrong.digits, identityKeyID: attacker, now: t0 + 5)
        #expect(r17 == .lockedOut(retryAfter: 60))
        // Even the right code is refused now: it was burned.
        let r18 = window.verify(code.digits, identityKeyID: ipad, now: t0 + 10)
        #expect(r18 == .lockedOut(retryAfter: 55))
        #expect(window.display(now: t0 + 10) == .lockedOut(until: t0 + 65))
    }

    @Test("Wrong codes are counted across devices")
    func attemptsAreShared() {
        var window = active()
        let r19 = window.verify(wrong.digits, identityKeyID: attacker, now: t0)
        #expect(r19 == .wrongCode(attemptsLeft: 4))
        let r20 = window.verify(wrong.digits, identityKeyID: ipad, now: t0)
        #expect(r20 == .wrongCode(attemptsLeft: 3))
        let r21 = window.verify(code.digits, identityKeyID: ipad, now: t0)
        #expect(r21 == .accepted)
    }

    @Test("Malformed and mistyped codes on the wire count as wrong")
    func malformedCounts() {
        var window = active()
        let r22 = window.verify("57241251", identityKeyID: attacker, now: t0)
        #expect(r22 == .wrongCode(attemptsLeft: 4)) // bad check digit
        let r23 = window.verify("abc", identityKeyID: attacker, now: t0)
        #expect(r23 == .wrongCode(attemptsLeft: 3))
        let r24 = window.verify("", identityKeyID: attacker, now: t0)
        #expect(r24 == .wrongCode(attemptsLeft: 2))
        let r25 = window.verify(String(repeating: "5", count: 5000), identityKeyID: attacker, now: t0)
        #expect(r25 == .wrongCode(attemptsLeft: 1))
    }

    @Test("No new code can be shown while locked; afterwards one can")
    func lockoutBlocksIssue() {
        var window = active()
        for _ in 0..<PairingCodeWindow.maxWrongAttempts {
            _ = window.verify(wrong.digits, identityKeyID: attacker, now: t0)
        }
        let r26 = window.issue(code, now: t0 + 30)
        #expect(r26 == .lockedOut(until: t0 + 60))
        window.cancel() // closing the sheet doesn't lift a lockout
        let r27 = window.issue(code, now: t0 + 59)
        #expect(r27 == .lockedOut(until: t0 + 60))
        // After the lockout there is no code until the Mac shows a new one.
        let r28 = window.verify(code.digits, identityKeyID: ipad, now: t0 + 61)
        #expect(r28 == .noActiveCode)
        let r29 = window.issue(code, now: t0 + 62)
        #expect(r29 == .issued(code: code, expiresAt: t0 + 362))
        let r30 = window.verify(code.digits, identityKeyID: ipad, now: t0 + 63)
        #expect(r30 == .accepted)
    }

    @Test("Showing a new code resets the count and the window")
    func reissueResets() {
        var window = active()
        _ = window.verify(wrong.digits, identityKeyID: attacker, now: t0)
        _ = window.verify(wrong.digits, identityKeyID: attacker, now: t0)
        let next = PairingCode("1234567" + String(DammCheck.checkDigit(for: "1234567")!))!
        window.issue(next, now: t0 + 200)
        // The old code is gone.
        let r31 = window.verify(code.digits, identityKeyID: attacker, now: t0 + 201)
        #expect(r31 == .wrongCode(attemptsLeft: 4))
        // The new one lives five minutes from when it was shown.
        let r32 = window.verify(next.digits, identityKeyID: ipad, now: t0 + 499)
        #expect(r32 == .accepted)
    }
}
