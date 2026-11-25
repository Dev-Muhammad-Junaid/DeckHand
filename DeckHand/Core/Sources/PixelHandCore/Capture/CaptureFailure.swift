//
//  CaptureFailure.swift
//  PixelHandCore
//
//  Why a screenshot or the live screen failed, in words a person can act
//  on. Build 19 showed "Live mirror unavailable: The operation couldn’t be
//  completed. (Pixel_Hand.ScreenCaptureService.CaptureError error 2.)"
//  when the Mac was locked. The Mac now sends one of these sentences
//  (`mirror.error`, `capture.screenshotError`), and the remote's alert
//  passes anything else through `UserFacingError.sentence(from:)`, so a
//  raw system error never reaches an alert, even from an older Mac.
//

import Foundation

public enum CaptureFailure: String, Sendable, CaseIterable {
    /// The Mac is locked (or another user is on its screen).
    case macLocked
    /// Screen Recording is off for Pixel Hand.
    case screenRecordingDenied
    /// ScreenCaptureKit lists no display (asleep, lid closed, or locked).
    case noDisplay
    /// The chosen window closed.
    case windowClosed
    /// ScreenCaptureKit failed for another reason.
    case captureFailed
    /// The picture couldn't be compressed or encoded.
    case encodeFailed
    /// The Mac couldn't open the stream to this remote.
    case streamOpenFailed
    /// A running live screen stopped on the Mac.
    case streamStopped
    /// The window list couldn't be read.
    case windowListFailed

    /// The sentence the Mac sends. Sentence case, no error codes.
    /// `.macLocked` is `LockPolicy.lockedErrorMessage`, which the remote
    /// recognises (`CaptureSheetChrome.isLockedRefusal`).
    public func message(isMirror: Bool) -> String {
        let what = isMirror ? "the live screen" : "the screenshot"
        switch self {
        case .macLocked:
            return LockPolicy.lockedErrorMessage
        case .screenRecordingDenied:
            return "Pixel Hand needs Screen Recording on the Mac. Turn it on in System Settings › Privacy & Security › Screen Recording, then try again."
        case .noDisplay:
            return "The Mac has no screen to \(isMirror ? "show" : "capture") right now. Wake its display, then try again."
        case .windowClosed:
            return "That window has closed. Refresh the window list and try again."
        case .captureFailed:
            return isMirror
                ? "The Mac couldn’t start the live screen. Try again."
                : "The Mac couldn’t take the screenshot. Try again."
        case .encodeFailed:
            return "The Mac couldn’t compress \(what). Try again."
        case .streamOpenFailed:
            return "The Mac couldn’t open the live screen. Try again."
        case .streamStopped:
            return "The live screen stopped on the Mac. Choose Show screen to start it again."
        case .windowListFailed:
            return "The Mac couldn’t list its windows. Check that Screen Recording is on for Pixel Hand, then try again."
        }
    }

    /// The failure to report: a locked Mac explains every other failure
    /// (ScreenCaptureKit lists no display while the screen is locked).
    public static func reported(_ failure: CaptureFailure, macLocked: Bool) -> CaptureFailure {
        macLocked ? .macLocked : failure
    }
}

/// Keeps raw system errors out of alerts.
public enum UserFacingError {
    /// Prefixes older Macs put before a raw description. The alert's title
    /// already says what failed.
    static let rawPrefixes = [
        "Live mirror unavailable:",
        "Live mirror stopped:",
        "Capture failed:",
        "Unexpected capture error:",
        "Couldn't read window list:",
        "Couldn’t read window list:",
    ]

    /// Whether `text` reads like a system error rather than a sentence for
    /// a person: Foundation's "The operation couldn’t be completed", an
    /// `NSError` dump, an "error 2" code, or a module-qualified Swift type
    /// (`Pixel_Hand.ScreenCaptureService.CaptureError`).
    public static func isRaw(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let lower = t.lowercased()
        let markers = [
            "operation couldn’t be completed", "operation couldn't be completed",
            "error domain=", "nsosstatuserrordomain", "nscocoaerrordomain",
            "userinfo=", "(null)",
        ]
        if markers.contains(where: lower.contains) { return true }
        if lower.range(of: #"\berror -?\d+\b"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\b(code|status)\s*[=:]\s*-?\d+\b"#, options: .regularExpression) != nil { return true }
        // Two or more dots between identifiers, or an underscore-joined
        // module name followed by a dot: a qualified type name.
        if t.range(of: #"\b[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"\b[A-Za-z0-9]+_[A-Za-z0-9_]+\.[A-Z]"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// `text` as a sentence for an alert, or `nil` when it is a raw system
    /// error (show your own copy instead). Strips an older Mac's
    /// "Live mirror unavailable:"-style prefix, capitalises the first
    /// letter and ends it with a full stop.
    public static func sentence(from text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in rawPrefixes where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !isRaw(t) else { return nil }
        t = t.prefix(1).uppercased() + t.dropFirst()
        if let last = t.last, !".!?…".contains(last) { t += "." }
        return t
    }

    /// The alert for a failed connection to `macName`: the error's own
    /// sentence when it has one, otherwise what to check.
    public static func connectFailure(macName: String, detail: String) -> String {
        let reason = sentence(from: detail) ?? "Check that Pixel Hand is open on the Mac, then try again."
        return "Couldn’t connect to \(macName). \(reason)"
    }
}
