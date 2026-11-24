//
//  PendingRequestExpiryTests.swift
//  PixelHandCoreTests
//

import Foundation
import PixelHandCore
import Testing

@Suite("Pending request expiry (VQ-037)")
struct PendingRequestExpiryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Without a code the request expires after 45 s")
    func baseTimeout() {
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: nil, now: t0 + 10) == .checkAgain(at: t0 + 45))
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: nil, now: t0 + 45) == .expire)
    }

    @Test("While a code is showing the request waits for it")
    func codeKeepsItAlive() {
        let codeEnds = t0 + 200
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: codeEnds, now: t0 + 45) == .checkAgain(at: codeEnds))
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: codeEnds, now: t0 + 199) == .checkAgain(at: codeEnds))
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: codeEnds, now: t0 + 200) == .expire)
    }

    @Test("A code closed after 45 s ends the wait at once")
    func codeClosed() {
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: nil, now: t0 + 90) == .expire)
        // A code that already ran out counts as no code.
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: t0 + 60, now: t0 + 90) == .expire)
    }

    @Test("A short code doesn't cut the base wait")
    func codeShorterThanBase() {
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: t0 + 20, now: t0 + 5) == .checkAgain(at: t0 + 45))
    }

    @Test("Never longer than 45 s plus one code's life")
    func hardLimit() {
        let limit = t0 + PendingRequestExpiry.hardLimit
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: t0 + 10_000, now: t0 + 50) == .checkAgain(at: limit))
        #expect(PendingRequestExpiry.decide(requestedAt: t0, codeShowingUntil: t0 + 10_000, now: limit) == .expire)
        #expect(PendingRequestExpiry.hardLimit == 345)
    }
}
