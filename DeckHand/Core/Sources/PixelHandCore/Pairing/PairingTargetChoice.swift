//
//  PairingTargetChoice.swift
//  PixelHandCore
//
//  Which Mac a typed pairing code goes to (build 24, VQ-100). The code sheet
//  opened from the picker used to default to the first Mac in the list,
//  which could be someone else's Mac, behind a lone unlabelled ⌃⌄.
//
//  The default is, in order:
//  1. the Mac that asked: the one the person tapped (its Allow prompt is
//     what sent them here), or the one the sheet was opened for;
//  2. the only Mac in reach;
//  3. the only Mac in reach that this device is paired with or used
//     recently.
//  Otherwise there is no default and the person must choose, on a labelled
//  "Pair with" row. Nothing is ever picked by list order.
//

import Foundation

/// A Mac in reach that a typed code could be for.
public struct PairingTargetCandidate: Equatable, Hashable, Sendable, Identifiable {
    public var deviceID: UUID
    public var name: String
    /// This device holds a pairing record for the Mac.
    public var isPaired: Bool
    /// When this device last used the Mac (`MacMemory.lastUsedAt`).
    public var lastUsedAt: Date?

    public var id: UUID { deviceID }

    public init(deviceID: UUID, name: String, isPaired: Bool = false, lastUsedAt: Date? = nil) {
        self.deviceID = deviceID
        self.name = name
        self.isPaired = isPaired
        self.lastUsedAt = lastUsedAt
    }
}

public enum PairingTargetChoice {
    /// A Mac used within this long counts as "recently seen".
    public static let recentWindow: TimeInterval = 14 * 24 * 60 * 60

    /// A Mac tapped in the picker within this long still counts as the Mac
    /// that asked (its Allow prompt, or its refusal, is why the person
    /// opened the code sheet).
    public static let askingWindow: TimeInterval = 10 * 60

    /// The Mac that asked, from the last Mac tapped and when; `nil` once
    /// that is stale.
    public static func askingDeviceID(lastAttempt: UUID?, at attemptedAt: Date?, now: Date) -> UUID? {
        guard let lastAttempt, let attemptedAt else { return nil }
        let age = now.timeIntervalSince(attemptedAt)
        return age >= -60 && age <= askingWindow ? lastAttempt : nil
    }

    /// The label of the chooser row.
    public static let rowLabel = "Pair with"
    /// The chooser row's value while nothing is chosen.
    public static let choosePrompt = "Choose a Mac"
    /// Said when the person sends a code before choosing.
    public static let chooseNotice = "Choose the Mac that shows the code."

    /// The Mac a code goes to when the person hasn't chosen one, or `nil`
    /// when they must choose.
    ///
    /// - Parameters:
    ///   - candidates: the Macs in reach, in any order (the order is never
    ///     used to pick).
    ///   - askingDeviceID: the Mac that asked (tapped in the picker, or the
    ///     one whose Allow prompt opened the sheet).
    public static func defaultTarget(
        among candidates: [PairingTargetCandidate],
        askingDeviceID: UUID?,
        now: Date
    ) -> UUID? {
        if let askingDeviceID {
            // Opened for one Mac (the approval overlay): that Mac, even when
            // discovery hasn't listed it.
            if candidates.isEmpty || candidates.contains(where: { $0.deviceID == askingDeviceID }) {
                return askingDeviceID
            }
        }
        let unique = deduplicated(candidates)
        if unique.count == 1 { return unique[0].deviceID }
        let known = unique.filter { isKnown($0, now: now) }
        if known.count == 1 { return known[0].deviceID }
        return nil
    }

    /// Whether the sheet shows the labelled "Pair with" row: whenever more
    /// than one Mac could be meant, so the person sees (and can change)
    /// which one the code goes to.
    public static func showsChooser(among candidates: [PairingTargetCandidate]) -> Bool {
        deduplicated(candidates).count > 1
    }

    /// Whether a code can't be sent until the person picks a Mac.
    public static func requiresChoice(
        among candidates: [PairingTargetCandidate],
        askingDeviceID: UUID?,
        chosenDeviceID: UUID?,
        now: Date
    ) -> Bool {
        if let chosenDeviceID, candidates.contains(where: { $0.deviceID == chosenDeviceID }) {
            return false
        }
        return showsChooser(among: candidates)
            && defaultTarget(among: candidates, askingDeviceID: askingDeviceID, now: now) == nil
    }

    /// The chooser row's value: the Mac's name, or the prompt.
    public static func rowValue(targetName: String?) -> String {
        guard let targetName, !targetName.isEmpty else { return choosePrompt }
        return targetName
    }

    /// The spoken chooser: "Pair with, Studio" or "Pair with, Choose a Mac".
    public static func rowAccessibilityLabel(targetName: String?) -> String {
        "\(rowLabel), \(rowValue(targetName: targetName))"
    }

    /// The heading over the code field.
    public static func heading(targetName: String?) -> String {
        guard let targetName, !targetName.isEmpty else { return "Type the code showing on your Mac" }
        return "Type the code showing on \(targetName)"
    }

    /// Paired, or used by this device within `recentWindow`.
    static func isKnown(_ candidate: PairingTargetCandidate, now: Date) -> Bool {
        if candidate.isPaired { return true }
        guard let used = candidate.lastUsedAt else { return false }
        let age = now.timeIntervalSince(used)
        return age >= -60 && age <= recentWindow
    }

    /// One entry per Mac (a Mac reachable two ways is listed twice).
    static func deduplicated(_ candidates: [PairingTargetCandidate]) -> [PairingTargetCandidate] {
        var seen = Set<UUID>()
        return candidates.filter { seen.insert($0.deviceID).inserted }
    }
}

/// How the code sheet fits above the iPhone number pad (VQ-100: the footer
/// ran under the keypad after its first line).
public enum PairingSheetLayout {
    /// The lock tile at the top is dropped while the number pad is up on a
    /// phone, so the field, the button and the whole footer fit above it.
    public static func showsLockTile(isPhone: Bool, isKeypadUp: Bool) -> Bool {
        !(isPhone && isKeypadUp)
    }

    /// The gap between the sheet's sections: tighter while the pad is up on
    /// a phone. Given as a design-system step (`lg` 16 or `xl` 24).
    public static func sectionSpacing(isPhone: Bool, isKeypadUp: Bool) -> Double {
        isPhone && isKeypadUp ? 16 : 24
    }

    /// Whether the sheet scrolls the footer into view when it changes while
    /// the pad is up. Not at the Huge band: there the field and the footer
    /// don't fit together, and the field matters more.
    public static func keepsFooterVisible(isKeypadUp: Bool, band: TypeBand) -> Bool {
        isKeypadUp && band != .huge
    }

    /// Whether the sheet repeats where the code comes from under the code
    /// field (build 26, VQ-108): on iPad the number pad floats over the
    /// sheet and covered its title ("Type the code showing on …") while
    /// typing. Under the field the line stays readable; on iPhone the pad
    /// docks at the bottom and the heading stays in view.
    public static func showsFieldCaption(isPhone: Bool, isKeypadUp: Bool) -> Bool {
        !isPhone && isKeypadUp
    }

    /// The line under the code field: names the Mac, or asks for one.
    public static func fieldCaption(targetName: String?) -> String {
        guard let targetName, !targetName.isEmpty else { return "Choose the Mac that shows the code." }
        return "The code showing on \(targetName)"
    }
}
