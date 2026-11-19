//
//  ActionValidation.swift
//  PixelHandCore
//
//  Limits on every string and number inside an `Action`, shared by the
//  Mac's `RemoteInputValidation` (what a remote may send) and
//  `DeckValidation` (what a deck may store). Nothing here can trap.
//

import Foundation

public enum ActionLimits {
    /// Longest bundle ID (reverse-DNS names are far shorter).
    public static let maxBundleIDBytes = 255
    /// Longest key name in a chord ("cmd", "f12", "space").
    public static let maxKeyNameBytes = 32
    /// Deepest menu path: the top menu plus nested submenus.
    public static let maxMenuPathComponents = 6
    /// Longest menu title in a path.
    public static let maxMenuTitleBytes = 256
    /// Longest Shortcuts.app shortcut name.
    public static let maxShortcutNameBytes = 256
    /// Most steps in a sequence (product spec §2: "max 20 steps").
    public static let maxSequenceSteps = 20
    /// Longest single pause in a sequence.
    public static let maxDelayMilliseconds = 10_000
    /// Longest total pause in a sequence.
    public static let maxTotalDelayMilliseconds = 30_000
    /// The Mac's pause between two action steps of a sequence, so an app
    /// sees one step's events before the next one's.
    public static let sequenceStepGapMilliseconds = 40
    /// Longest dialog-button ID (`ContextObserver` builds short ones).
    public static let maxContextIDBytes = 1_024
    /// How long the Mac waits for a Deck 2 run before answering
    /// `delivered` and letting it finish on its own. Kept under the
    /// remote's 1.5 s receipt timeout.
    public static let receiptDeadline: TimeInterval = 1.2
}

public enum ActionValidation {
    public enum Issue: Equatable, Sendable {
        case emptyChord
        case tooManyChordKeys
        case badKeyName
        case badBundleID
        case badContextID
        case emptyMenuPath
        case menuPathTooDeep
        case badMenuTitle
        case badShortcutName
        case emptySequence
        case tooManySteps
        case nestedSequence
        case badDelay
        case totalDelayTooLong
        /// Dialog buttons only exist while their dialog is open, so a
        /// stored key or a sequence step can't press one.
        case contextActionNotStorable
    }

    /// Every problem with `action`; empty when it is valid. With
    /// `storable`, a dialog press is refused too (deck keys and sequence
    /// steps outlive the dialog).
    public static func issues(in action: Action, storable: Bool) -> [Issue] {
        var issues: [Issue] = []
        check(action, storable: storable, inSequence: false, into: &issues)
        return issues
    }

    public static func isValid(_ action: Action, storable: Bool) -> Bool {
        issues(in: action, storable: storable).isEmpty
    }

    private static func check(_ action: Action, storable: Bool, inSequence: Bool, into issues: inout [Issue]) {
        switch action {
        case let .shortcut(keys):
            checkChord(keys, into: &issues)
        case let .appShortcut(bundleID, keys):
            if !isBundleID(bundleID) { issues.append(.badBundleID) }
            checkChord(keys, into: &issues)
        case let .launchApp(bundleID):
            if !isBundleID(bundleID) { issues.append(.badBundleID) }
        case .system, .media:
            break
        case let .contextAction(id):
            if storable || inSequence { issues.append(.contextActionNotStorable) }
            if id.isEmpty || id.utf8.count > ActionLimits.maxContextIDBytes { issues.append(.badContextID) }
        case let .menuCommand(bundleID, path):
            if !isBundleID(bundleID) { issues.append(.badBundleID) }
            if path.isEmpty { issues.append(.emptyMenuPath) }
            if path.count > ActionLimits.maxMenuPathComponents { issues.append(.menuPathTooDeep) }
            if !path.allSatisfy(isMenuTitle) { issues.append(.badMenuTitle) }
        case let .macShortcut(name):
            if !isShortcutName(name) { issues.append(.badShortcutName) }
        case let .sequence(steps):
            if inSequence { issues.append(.nestedSequence); return }
            if steps.isEmpty { issues.append(.emptySequence) }
            if steps.count > ActionLimits.maxSequenceSteps { issues.append(.tooManySteps) }
            var total = 0
            for step in steps.prefix(ActionLimits.maxSequenceSteps) {
                switch step {
                case let .delay(ms):
                    if ms < 0 || ms > ActionLimits.maxDelayMilliseconds {
                        issues.append(.badDelay)
                    } else {
                        total += ms
                    }
                case let .run(inner):
                    check(inner, storable: storable, inSequence: true, into: &issues)
                }
            }
            if total > ActionLimits.maxTotalDelayMilliseconds { issues.append(.totalDelayTooLong) }
        }
    }

    private static func checkChord(_ keys: [String], into issues: inout [Issue]) {
        if keys.isEmpty { issues.append(.emptyChord) }
        if keys.count > ProtocolLimits.maxChordKeys { issues.append(.tooManyChordKeys) }
        if !keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= ActionLimits.maxKeyNameBytes }) {
            issues.append(.badKeyName)
        }
    }

    // MARK: - Strings

    /// A bundle ID: 1…255 bytes of letters, digits, `.`, `-` and `_`.
    public static func isBundleID(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= ActionLimits.maxBundleIDBytes else { return false }
        return s.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_")
        }
    }

    /// A menu title: not blank, no control characters, ≤ 256 bytes.
    public static func isMenuTitle(_ s: String) -> Bool {
        isPlainText(s, maxBytes: ActionLimits.maxMenuTitleBytes)
    }

    /// A Shortcuts.app name: not blank, no control characters, ≤ 256 bytes.
    /// It is passed to `shortcuts run` as one argument, never through a
    /// shell, but a leading `-` would read as an option, so it is refused.
    public static func isShortcutName(_ s: String) -> Bool {
        isPlainText(s, maxBytes: ActionLimits.maxShortcutNameBytes) && !s.hasPrefix("-")
    }

    /// Not blank, no control or line-separator characters, ≤ `maxBytes`.
    public static func isPlainText(_ s: String, maxBytes: Int) -> Bool {
        guard s.utf8.count <= maxBytes else { return false }
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !s.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                || scalar == "\u{2028}" || scalar == "\u{2029}"
        }
    }
}
