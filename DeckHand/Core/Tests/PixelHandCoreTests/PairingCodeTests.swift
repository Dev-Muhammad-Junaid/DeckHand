//
//  PairingCodeTests.swift
//  PixelHandCoreTests
//
//  The Damm check digit and the pairing code built on it (S4).
//

import Foundation
import PixelHandCore
import Testing

/// A seeded generator so code generation is repeatable in tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct DammCheckTests {

    @Test("The published example: 572 takes check digit 4")
    func publishedExample() {
        #expect(DammCheck.checkDigit(for: "572") == "4")
        #expect(DammCheck.isValid("5724"))
        #expect(!DammCheck.isValid("5723"))
    }

    @Test("Every single-digit mistake is caught")
    func catchesEverySingleDigitError() {
        var generator = SplitMix64(seed: 1)
        for _ in 0..<200 {
            let code = PairingCode.generate(using: &generator).digits
            #expect(DammCheck.isValid(code))
            var digits = Array(code)
            for position in digits.indices {
                let original = digits[position]
                for replacement in "0123456789" where replacement != original {
                    digits[position] = replacement
                    #expect(!DammCheck.isValid(String(digits)), "\(code) → \(String(digits))")
                }
                digits[position] = original
            }
        }
    }

    @Test("Every swap of two different neighbouring digits is caught")
    func catchesEveryAdjacentTransposition() {
        var generator = SplitMix64(seed: 2)
        for _ in 0..<200 {
            let code = PairingCode.generate(using: &generator).digits
            var digits = Array(code)
            for position in 0..<(digits.count - 1) where digits[position] != digits[position + 1] {
                digits.swapAt(position, position + 1)
                #expect(!DammCheck.isValid(String(digits)), "\(code) → \(String(digits))")
                digits.swapAt(position, position + 1)
            }
        }
    }

    @Test("Anything but ASCII digits has no check digit and is never valid")
    func refusesNonDigits() {
        #expect(DammCheck.checkDigit(for: "") == nil)
        #expect(DammCheck.checkDigit(for: "12a") == nil)
        #expect(DammCheck.checkDigit(for: "١٢٣") == nil) // Arabic-Indic digits
        #expect(!DammCheck.isValid(""))
        #expect(!DammCheck.isValid("0")) // too short to carry a check digit
        #expect(!DammCheck.isValid("57 24"))
        #expect(!DammCheck.isValid("５７２４")) // full-width digits
    }
}

@Suite struct PairingCodeTests {

    @Test("Generated codes are eight digits (seven random, one check) with a valid check digit")
    func generatedCodesAreValid() {
        var generator = SplitMix64(seed: 3)
        for _ in 0..<500 {
            let code = PairingCode.generate(using: &generator)
            #expect(code.digits.count == PairingCode.length)
            let allASCII = code.digits.allSatisfy(\.isASCII)
            #expect(allASCII)
            #expect(DammCheck.isValid(code.digits))
            #expect(PairingCode(code.digits) == code)
        }
        let system = PairingCode.generate()
        #expect(DammCheck.isValid(system.digits))
    }

    @Test("Secret digits are spread evenly")
    func secretDigitsAreUniform() {
        var generator = SplitMix64(seed: 4)
        var counts = [Int](repeating: 0, count: 10)
        let samples = 5_000
        for _ in 0..<samples {
            for character in PairingCode.generate(using: &generator).digits.prefix(PairingCode.secretLength) {
                counts[Int(String(character))!] += 1
            }
        }
        let expected = Double(samples * PairingCode.secretLength) / 10
        for count in counts {
            #expect(abs(Double(count) - expected) < expected * 0.05, "\(counts)")
        }
    }

    @Test("Spaces and dashes are ignored as people type them")
    func parseIgnoresSeparators() {
        guard case let .valid(code) = PairingCode.parse("5724 1250") else {
            Issue.record("expected a valid code")
            return
        }
        #expect(code.digits == "57241250")
        #expect(PairingCode(" 5724 1250 ") == code)
        #expect(PairingCode("5724\u{2013}1250") == code)
        #expect(code.formatted == "5724 1250")
        #expect(code.description == "5724 1250")
    }

    @Test("Partial, malformed and mistyped input are told apart")
    func parseResults() {
        #expect(PairingCode.parse("") == .incomplete(digitCount: 0))
        #expect(PairingCode.parse("572-41") == .incomplete(digitCount: 5))
        #expect(PairingCode.parse("572a412") == .malformed)
        #expect(PairingCode.parse("572412504") == .malformed) // nine digits
        #expect(PairingCode.parse("５７２４１２３") == .malformed)
        #expect(PairingCode.parse("57241251") == .checkDigitMismatch)
        #expect(PairingCode.parse(String(repeating: " ", count: 40) + "57241250") == .malformed) // over the input cap
        #expect(PairingCode("57241251") == nil)
    }

    @Test("Codes compare equal only when every digit matches")
    func constantTimeEquality() throws {
        let a = try #require(PairingCode("57241250"))
        let b = try #require(PairingCode("5724 1250"))
        var generator = SplitMix64(seed: 5)
        let c = PairingCode.generate(using: &generator)
        #expect(a.constantTimeEquals(b))
        #expect(a.constantTimeEquals(c) == (a == c))
    }
}

@Suite struct PairingInviteTests {

    private let key = String(repeating: "ab", count: 32)
    private let mac = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test("An invite survives the QR payload round trip")
    func roundTrip() throws {
        let code = try #require(PairingCode("57241250"))
        let invite = try #require(PairingInvite(code: code, macDeviceID: mac, macIdentityKeyID: key))
        #expect(invite.payload.hasPrefix("pixelhand://pair?"))
        #expect(PairingInvite(payload: invite.payload) == invite)
    }

    @Test("Anything that isn't exactly a version-1 invite is refused")
    func refusesBadPayloads() throws {
        let good = "pixelhand://pair?v=1&code=57241250&mac=\(mac.uuidString)&key=\(key)"
        #expect(PairingInvite(payload: good) != nil)
        let bad = [
            "https://pair?v=1&code=57241250&mac=\(mac.uuidString)&key=\(key)",    // wrong scheme
            "pixelhand://other?v=1&code=57241250&mac=\(mac.uuidString)&key=\(key)", // wrong host
            "pixelhand://pair?v=2&code=57241250&mac=\(mac.uuidString)&key=\(key)",  // future version
            "pixelhand://pair?v=1&code=57241251&mac=\(mac.uuidString)&key=\(key)",  // bad check digit
            "pixelhand://pair?v=1&code=57241250&mac=not-a-uuid&key=\(key)",
            "pixelhand://pair?v=1&code=57241250&mac=\(mac.uuidString)&key=short",
            "pixelhand://pair?v=1&code=57241250&mac=\(mac.uuidString)&key=\(key)&code=1111111", // duplicate
            "pixelhand://pair?v=1&code=57241250&mac=\(mac.uuidString)&key=\(key)&extra=1",      // unknown item
            "pixelhand://pair?v=1&code=57241250&mac=\(mac.uuidString)",                         // missing key
            "pixelhand://pair/x?v=1&code=57241250&mac=\(mac.uuidString)&key=\(key)",            // path
            good + String(repeating: "&", count: 600),                                          // oversize
            "",
        ]
        for payload in bad {
            #expect(PairingInvite(payload: payload) == nil, "\(payload)")
        }
    }

    @Test("An invite needs a well-formed key ID")
    func refusesBadKey() throws {
        let code = try #require(PairingCode("57241250"))
        #expect(PairingInvite(code: code, macDeviceID: mac, macIdentityKeyID: "") == nil)
        #expect(PairingInvite(code: code, macDeviceID: mac, macIdentityKeyID: key + " ") == nil)
    }
}

@Suite("Pairing code: one format everywhere (VQ-005, VQ-029)")
struct PairingCodeFormatTests {
    @Test("Codes are two groups of four")
    func twoGroupsOfFour() {
        #expect(PairingCode.length == 8)
        #expect(PairingCode("48210934")?.formatted == "4821 0934")
        var generator = SplitMix64(seed: 9)
        for _ in 0..<50 {
            let text = PairingCode.generate(using: &generator).formatted
            #expect(text.count == 9)
            #expect(text.split(separator: " ").map(\.count) == [4, 4])
        }
    }

    @Test("Typed input is grouped as it is typed and capped at the code's length")
    func groupedAsTyped() {
        #expect(PairingCode.grouped("") == "")
        #expect(PairingCode.grouped("482") == "482")
        #expect(PairingCode.grouped("4821") == "4821")
        #expect(PairingCode.grouped("48210") == "4821 0")
        #expect(PairingCode.grouped("4821-0934") == "4821 0934")
        #expect(PairingCode.grouped("482109341234") == "4821 0934")
        #expect(PairingCode.grouped("48 2a1x09") == "4821 09")
        // Grouped text parses back to the same code.
        #expect(PairingCode(PairingCode.grouped("48210934")) == PairingCode("48210934"))
    }

    @Test("Complete means every digit is there, right or wrong")
    func completeness() {
        #expect(!PairingCode.isComplete(""))
        #expect(!PairingCode.isComplete("4821 093"))
        #expect(PairingCode.isComplete("4821 0934"))
        #expect(PairingCode.isComplete("4821 0935")) // complete, but a typo
    }

    @Test("The display groups match the formatted code; the check digit closes the last group")
    func displayGroups() throws {
        let code = try #require(PairingCode("48210934"))
        let groups = PairingCodeDisplay.groups(code)
        #expect(groups.map(\.text) == ["4821", "0934"])
        #expect(groups.map(\.isCheck) == [false, true])
        #expect(groups.map(\.text).joined(separator: " ") == code.formatted)
    }
}
