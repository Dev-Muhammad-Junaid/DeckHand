//
//  PairingCodeDisplay.swift
//  PixelHandCore – Design
//
//  How the Mac's "Pair a device" window draws a code (`06-Pixel-Identity.md`
//  §4 "Pairing code", board `v2PairMac`): dot-matrix numerals in groups of
//  four with the check digit dimmer, a dot beam counting down the 5-minute
//  window, and a QR code whose modules are dots except the finder squares.
//

import Foundation

public enum PairingCodeDisplay {
    /// One drawn group of digits.
    public struct Group: Sendable, Hashable {
        public let text: String
        /// The check digit's group is drawn dimmer.
        public let isCheck: Bool
    }

    /// `1234567` → `1234`, `56`, `7` (check). Groups of four from the
    /// front; the check digit always stands alone so it can be dimmed.
    public static func groups(_ code: PairingCode) -> [Group] {
        let digits = Array(code.digits)
        guard let check = digits.last else { return [] }
        let secret = digits.dropLast()
        var groups: [Group] = []
        var index = secret.startIndex
        while index < secret.endIndex {
            let end = secret.index(index, offsetBy: 4, limitedBy: secret.endIndex) ?? secret.endIndex
            groups.append(Group(text: String(secret[index..<end]), isCheck: false))
            index = end
        }
        groups.append(Group(text: String(check), isCheck: true))
        return groups
    }

    /// VoiceOver reads the digits one by one: "1 2 3 4 5 6 7".
    public static func spoken(_ code: PairingCode) -> String {
        "Pairing code " + code.digits.map(String.init).joined(separator: " ")
    }

    /// Cells in the countdown beam.
    public static let beamCells = 10

    /// Lit cells of the countdown beam for `remaining` seconds of a
    /// `lifetime`-second window: full at the start, one fewer every tenth,
    /// and the last cell stays lit until the code actually expires.
    public static func beamLitCells(remaining: TimeInterval, lifetime: TimeInterval = PairingCodeWindow.lifetime) -> Int {
        guard lifetime > 0, remaining > 0 else { return 0 }
        let fraction = min(1, remaining / lifetime)
        return max(1, Int((fraction * Double(beamCells)).rounded(.up)))
    }

    /// "3:41": whole seconds, rounded up so it never reads 0:00 early.
    public static func countdown(remaining: TimeInterval) -> String {
        let left = max(0, Int(remaining.rounded(.up)))
        return "\(left / 60):" + (left % 60 < 10 ? "0" : "") + "\(left % 60)"
    }

    /// Spoken form of the countdown: "3 minutes 41 seconds left".
    public static func spokenCountdown(remaining: TimeInterval) -> String {
        let left = max(0, Int(remaining.rounded(.up)))
        let minutes = left / 60, seconds = left % 60
        var parts: [String] = []
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if seconds > 0 || minutes == 0 { parts.append("\(seconds) second\(seconds == 1 ? "" : "s")") }
        return parts.joined(separator: " ") + " left"
    }
}

/// How each module of a QR code is drawn, so the code stays scannable with
/// round dots and a glyph tile in the middle.
public enum QRDotPlan {
    public enum Module: Sendable, Hashable {
        /// Light module: nothing drawn.
        case empty
        /// A dark data module: a round dot.
        case dot
        /// Part of a finder pattern: drawn as a square so scanners lock on.
        case finder
        /// Under the centre tile: left empty (within error correction).
        case cleared
    }

    /// Side, in modules, of the cleared centre for an `n`-module code: the
    /// largest odd number not above n / 4, so it covers at most about 6 %
    /// of the code (well inside level H's 30 % and Q's 25 %).
    public static func clearedSide(modules n: Int) -> Int {
        guard n >= 21 else { return 0 }
        let side = n / 4
        return side % 2 == 1 ? side : side - 1
    }

    /// Whether (x, y) is inside one of the three 7 × 7 finder patterns.
    public static func isFinder(x: Int, y: Int, modules n: Int) -> Bool {
        let near = 0..<7, far = (n - 7)..<n
        return (near.contains(x) && near.contains(y))
            || (far.contains(x) && near.contains(y))
            || (near.contains(x) && far.contains(y))
    }

    /// Whether (x, y) is under the centre tile.
    public static func isCleared(x: Int, y: Int, modules n: Int) -> Bool {
        let side = clearedSide(modules: n)
        guard side > 0 else { return false }
        let start = (n - side) / 2
        let range = start..<(start + side)
        return range.contains(x) && range.contains(y)
    }

    /// The plan for one module; `dark` is the QR's own value there.
    public static func module(x: Int, y: Int, modules n: Int, dark: Bool) -> Module {
        if isFinder(x: x, y: y, modules: n) { return dark ? .finder : .empty }
        if isCleared(x: x, y: y, modules: n) { return .cleared }
        return dark ? .dot : .empty
    }
}
