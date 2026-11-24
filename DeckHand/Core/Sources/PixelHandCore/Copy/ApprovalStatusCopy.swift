//
//  ApprovalStatusCopy.swift
//  PixelHandCore
//
//  What the remote shows for each approval state.
//
//  The wire only carries "pending", "granted" and "denied". When the Mac's
//  45 s approval window runs out it also sends "denied", so the remote used
//  to say the request "was declined" when nobody had answered at all. The
//  remote now tells the two apart by how long it waited, and shows a local
//  "timed_out" state. Since protocol 14 the Mac also says why
//  (`pairing.refused(reason:)`), so a rule is never worded as a person's
//  Deny (VQ-002); the timing guess stays for older Macs.
//

import Foundation

public enum ApprovalStatusCopy {
    /// How long the Mac keeps an approval request open before it gives up
    /// and answers "denied". The Mac's expiry and the remote's wording both
    /// read this.
    public static let pendingRequestTimeout: TimeInterval = 45

    /// A "denied" that arrives this close to the expiry is read as a
    /// timeout. The slack covers the connection and handshake time the
    /// remote counts but the Mac doesn't.
    public static let timeoutSlack: TimeInterval = 5

    /// Remote-only status shown when the approval window ran out.
    public static let timedOutStatus = "timed_out"

    /// Remote-only status shown when the Mac forgot this paired device
    /// (`pairing.pairedStatus(paired: false)` after a paired grant), or the
    /// user forgot the Mac from this device, and the session ended (S4).
    public static let forgottenStatus = "forgotten"

    /// A person clicked Deny on the Mac (`AuthRefusal.declined`).
    public static let declinedStatus = "declined"
    /// Not paired, and the request came from another network.
    public static let pairFirstStatus = "pair_first"
    /// The handshake didn't prove this device's identity.
    public static let unverifiedStatus = "unverified"
    /// A newer request from this device replaced this one.
    public static let replacedStatus = "replaced"

    /// The status the remote shows for a refusal reason from the Mac.
    public static func status(for refusal: AuthRefusal) -> String {
        switch refusal {
        case .declined: declinedStatus
        case .timedOut: timedOutStatus
        case .notPairedRemote: pairFirstStatus
        case .unverified: unverifiedStatus
        case .replaced: replacedStatus
        }
    }

    /// Statuses that come from `pairing.refused` (or the timing guess) and
    /// already say why: the plain `denied` that follows must not replace
    /// them.
    public static func isRefusal(_ status: String) -> Bool {
        [declinedStatus, timedOutStatus, pairFirstStatus, unverifiedStatus, replacedStatus].contains(status)
    }

    /// Whether the refusal card offers "Enter pairing code" (VQ-003): a
    /// paired device connects without asking, so pairing is the way past a
    /// Deny or a timeout. Not for another network (pairing needs the same
    /// one) or an unverified identity (a code can't fix that).
    public static func offersPairing(_ status: String) -> Bool {
        status == "denied" || status == declinedStatus || status == timedOutStatus || status == replacedStatus
    }

    /// The status the remote should show for a status from the wire.
    ///
    /// - Parameters:
    ///   - wireStatus: "pending", "granted", "denied" or a local status.
    ///   - pendingFor: How long the remote has been waiting for an answer.
    public static func displayStatus(forWireStatus wireStatus: String, pendingFor: TimeInterval) -> String {
        guard wireStatus == "denied" else { return wireStatus }
        return pendingFor >= pendingRequestTimeout - timeoutSlack ? timedOutStatus : wireStatus
    }

    /// States the user can only dismiss: the connection is already over.
    public static func isTerminal(_ status: String) -> Bool {
        status == "denied" || status == "host_disconnected" || status == forgottenStatus || isRefusal(status)
    }

    /// States a later "host_disconnected" must not replace, because they
    /// already explain why the connection ended.
    public static func isFinalVerdict(_ status: String) -> Bool {
        status == "denied" || status == forgottenStatus || isRefusal(status)
    }

    /// The line under the Mac's name in the control screen's header.
    /// "Connected" only once the Mac has allowed this device; before that
    /// the header used to say "Connected" behind the waiting and denied
    /// cards.
    public static func headerSubtitle(status: String, activeAppName: String?) -> String {
        switch status {
        case "granted":
            activeAppName ?? "Connected"
        case "pending":
            "Waiting for approval"
        case "denied", declinedStatus, unverifiedStatus, replacedStatus:
            "Not allowed"
        case pairFirstStatus:
            "Pair first"
        case timedOutStatus:
            "Request timed out"
        case "host_disconnected":
            "Disconnected"
        case forgottenStatus:
            "Forgotten"
        default:
            "Not connected"
        }
    }

    /// Whether the header shows the breathing "live" pixel.
    public static func showsLiveIndicator(status: String) -> Bool {
        status == "granted"
    }

    /// Title and message for the approval card.
    public static func overlay(status: String, peerName: String) -> (title: String, message: String) {
        switch status {
        case "pending":
            ("Waiting for approval", "Click Allow on \(peerName), or pair with the code it shows.")
        case "granted":
            ("Approved", "You’re connected to \(peerName).")
        case "host_disconnected":
            ("Disconnected", "The connection to \(peerName) was closed.")
        case "denied":
            // An older Mac that doesn't say why: don't claim a person did it.
            ("Not allowed", "\(peerName) didn’t allow this connection. Pair with its code so it connects without asking.")
        case declinedStatus:
            ("Declined on \(peerName)", "Someone at \(peerName) clicked Deny. Pair with its code, or ask them to allow it.")
        case pairFirstStatus:
            ("Pair \(peerName) first", "From another network, \(peerName) only lets in devices paired with it. Pair once on the same Wi-Fi or with a cable, then connect from anywhere.")
        case unverifiedStatus:
            ("Not allowed", "\(peerName) couldn’t verify this device. Update Pixel Hand on both, then connect again.")
        case replacedStatus:
            ("Connected again", "A newer request from this device took over. Connect again if this one is still open.")
        case timedOutStatus:
            ("Request timed out", "Nobody answered on \(peerName) within \(Int(pendingRequestTimeout)) seconds. Connect again, or pair with its code.")
        case forgottenStatus:
            ("Device forgotten", "\(peerName) and this device are no longer paired. Connect again to ask for access.")
        default:
            ("Unknown state", "")
        }
    }

    // MARK: - Pairing code (S4)

    /// What the remote says about the Mac's answer to a pairing code.
    /// `nil` for `.accepted`: the approval card's own "Approved" says it.
    public static func codeResult(_ result: PairingCodeResult, peerName: String) -> String? {
        switch result {
        case .accepted:
            nil
        case let .wrongCode(attemptsLeft):
            attemptsLeft == 1
                ? "That code didn’t match. One try left before \(peerName) stops accepting it."
                : "That code didn’t match. \(attemptsLeft) tries left."
        case let .lockedOut(retryAfter):
            "Too many wrong codes. \(peerName) can show a new code in \(durationText(seconds: retryAfter))."
        case .expired:
            "That code has expired. Show a new one on \(peerName)."
        case .noActiveCode:
            "\(peerName) isn’t showing a pairing code. Choose Pair a device in its menu bar, then try again."
        }
    }

    /// Feedback while a code is being typed. `nil` while it is fine so far.
    public static func codeEntryHint(_ parse: PairingCode.ParseResult) -> String? {
        switch parse {
        case .valid, .incomplete:
            nil
        case .malformed:
            "Codes are \(PairingCode.length) digits."
        case .checkDigitMismatch:
            "Check the code: a digit looks mistyped."
        }
    }

    /// "45 seconds", "1 minute", "2 minutes".
    public static func durationText(seconds: Int) -> String {
        if seconds < 60 {
            return seconds == 1 ? "1 second" : "\(max(0, seconds)) seconds"
        }
        let minutes = (seconds + 59) / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
