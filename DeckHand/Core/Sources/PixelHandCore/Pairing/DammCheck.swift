//
//  DammCheck.swift
//  PixelHandCore
//
//  The Damm check digit for decimal strings (H. Michael Damm, 2004). One
//  appended digit catches every single-digit mistake and every swap of two
//  neighbouring digits, the two errors people make copying a code by hand.
//
//  The pairing code carries one, so the remote can say "check the code"
//  before anything is sent and a typo never costs one of the Mac's limited
//  attempts. The check digit is not a secret and adds no strength; the
//  random digits before it do.
//

import Foundation

public enum DammCheck {
    /// A weakly totally anti-symmetric quasigroup of order 10 (zero
    /// diagonal), the table Damm published.
    private static let table: [[UInt8]] = [
        [0, 3, 1, 7, 5, 9, 8, 6, 4, 2],
        [7, 0, 9, 2, 1, 5, 4, 8, 6, 3],
        [4, 2, 0, 6, 8, 7, 1, 3, 5, 9],
        [1, 7, 5, 0, 9, 8, 3, 4, 2, 6],
        [6, 1, 2, 3, 0, 4, 5, 9, 7, 8],
        [3, 6, 7, 4, 2, 0, 9, 5, 8, 1],
        [5, 8, 6, 9, 7, 2, 0, 1, 3, 4],
        [8, 9, 4, 5, 3, 6, 2, 0, 1, 7],
        [9, 4, 3, 8, 6, 1, 7, 2, 0, 5],
        [2, 5, 8, 1, 4, 3, 6, 7, 9, 0],
    ]

    /// The interim digit after running `digits` through the table, or `nil`
    /// when `digits` holds anything but ASCII 0–9.
    private static func interim(_ digits: some StringProtocol) -> UInt8? {
        var state: UInt8 = 0
        for scalar in digits.unicodeScalars {
            guard scalar.isASCII, let value = digitValue(scalar) else { return nil }
            state = table[Int(state)][Int(value)]
        }
        return state
    }

    private static func digitValue(_ scalar: Unicode.Scalar) -> UInt8? {
        guard scalar.value >= 48, scalar.value <= 57 else { return nil }
        return UInt8(scalar.value - 48)
    }

    /// The check digit to append to `digits`, or `nil` if `digits` is empty
    /// or not all ASCII 0–9.
    public static func checkDigit(for digits: some StringProtocol) -> Character? {
        guard !digits.isEmpty, let value = interim(digits) else { return nil }
        return Character(Unicode.Scalar(value + 48))
    }

    /// Whether `digits` (check digit included) is valid: at least two ASCII
    /// digits that run through the table to zero.
    public static func isValid(_ digits: some StringProtocol) -> Bool {
        guard digits.count >= 2, let value = interim(digits) else { return false }
        return value == 0
    }
}
