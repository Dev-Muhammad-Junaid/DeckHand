//
//  PairingCode.swift
//  PixelHandCore
//
//  The short code the Mac shows to pair a remote (S4): seven random digits
//  and a Damm check digit, shown as two groups of four, "4821 0934"
//  (VQ-005: one format on the Mac, in onboarding and in the entry field). The remote types it, or scans
//  it inside a QR code (`PairingInvite`), and sends it with
//  `pairing.submitCode`. The Mac checks it with `PairingCodeWindow`.
//
//  Strength: 10^7 codes, at most `PairingCodeWindow.maxWrongAttempts`
//  guesses per code, a code lives `PairingCodeWindow.lifetime`, and only a
//  device that already proved a Loom identity key can submit one.
//

import Foundation

public struct PairingCode: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// Random digits in a code.
    public static let secretLength = 7
    /// Digits in a code, check digit included.
    public static let length = secretLength + 1
    /// The longest text `parse` looks at. Anything longer is refused
    /// without reading it, so a hostile remote can't make the Mac scan a
    /// large string.
    public static let maxInputLength = 32

    /// The code's digits, check digit last. Always `length` ASCII digits
    /// that pass `DammCheck`.
    public let digits: String

    private init(validDigits: String) {
        digits = validDigits
    }

    /// A new code from `generator`. Each secret digit is uniform over 0–9.
    public static func generate<G: RandomNumberGenerator>(using generator: inout G) -> PairingCode {
        var secret = ""
        for _ in 0..<secretLength {
            secret.append(Character(Unicode.Scalar(UInt8.random(in: 0...9, using: &generator) + 48)))
        }
        // ASCII digits always have a check digit.
        return PairingCode(validDigits: secret + String(DammCheck.checkDigit(for: secret)!))
    }

    /// A new code from the system's cryptographic random source.
    public static func generate() -> PairingCode {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// What a typed or scanned string is, for live feedback while typing.
    public enum ParseResult: Equatable, Sendable {
        case valid(PairingCode)
        /// Digits so far, fewer than `length`. Not an error yet.
        case incomplete(digitCount: Int)
        /// Something other than digits, spaces and dashes, or too long.
        case malformed
        /// `length` digits whose check digit doesn't match: a typo.
        case checkDigitMismatch
    }

    /// Reads a code as people type it: spaces and dashes (ASCII, en and em
    /// dash) are ignored, anything else that isn't an ASCII digit is
    /// refused.
    public static func parse(_ input: String) -> ParseResult {
        guard input.utf8.count <= maxInputLength else { return .malformed }
        var digits = ""
        for scalar in input.unicodeScalars {
            switch scalar {
            case "0"..."9":
                digits.unicodeScalars.append(scalar)
            case " ", "-", "\u{2013}", "\u{2014}", "\u{00A0}":
                continue
            default:
                return .malformed
            }
        }
        if digits.count < length { return .incomplete(digitCount: digits.count) }
        if digits.count > length { return .malformed }
        guard DammCheck.isValid(digits) else { return .checkDigitMismatch }
        return .valid(PairingCode(validDigits: digits))
    }

    /// The code in `input`, or `nil` unless `parse` finds a valid one.
    public init?(_ input: String) {
        guard case let .valid(code) = Self.parse(input) else { return nil }
        self = code
    }

    /// Digits per group when a code is shown or typed.
    public static let groupSize = 4

    /// "4821 0934": two groups of four, easier to read aloud and to copy.
    public var formatted: String {
        Self.grouped(digits)
    }

    /// The digits of `input` as people type them, grouped in fours with a
    /// space: "48210" → "4821 0". Anything that isn't an ASCII digit is
    /// dropped, and the result stops at `length` digits, so the entry field
    /// shows exactly what will be sent.
    public static func grouped(_ input: String) -> String {
        var out = ""
        var count = 0
        for scalar in input.unicodeScalars.prefix(maxInputLength * 2) where ("0"..."9").contains(scalar) {
            guard count < length else { break }
            if count > 0, count % groupSize == 0 { out.append(" ") }
            out.unicodeScalars.append(scalar)
            count += 1
        }
        return out
    }

    /// The typed text is complete (all `length` digits are there).
    public static func isComplete(_ input: String) -> Bool {
        if case .incomplete = parse(input) { return false }
        return !input.isEmpty
    }

    public var description: String { formatted }

    /// Compares two codes without stopping at the first difference, so how
    /// long a wrong guess takes says nothing about how close it was.
    public func constantTimeEquals(_ other: PairingCode) -> Bool {
        let a = Array(digits.utf8)
        let b = Array(other.digits.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices {
            difference |= a[index] ^ b[index]
        }
        return difference == 0
    }
}
