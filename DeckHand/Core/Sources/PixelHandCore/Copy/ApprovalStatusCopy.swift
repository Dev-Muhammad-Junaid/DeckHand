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
//  "timed_out" state. Nothing new goes over the wire.
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
        status == "denied" || status == timedOutStatus || status == "host_disconnected"
    }

    /// States a later "host_disconnected" must not replace, because they
    /// already explain why the connection ended.
    public static func isFinalVerdict(_ status: String) -> Bool {
        status == "denied" || status == timedOutStatus
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
        case "denied":
            "Not allowed"
        case timedOutStatus:
            "Request timed out"
        case "host_disconnected":
            "Disconnected"
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
            ("Waiting for Approval", "Please allow the connection request on \(peerName).")
        case "granted":
            ("Approved", "You’re connected to \(peerName).")
        case "host_disconnected":
            ("Disconnected", "The connection to \(peerName) was closed.")
        case "denied":
            ("Access Denied", "Your request to control \(peerName) was declined.")
        case timedOutStatus:
            ("Request Timed Out", "Nobody allowed the request on \(peerName) within \(Int(pendingRequestTimeout)) seconds. Connect again, then click Allow on the Mac.")
        default:
            ("Unknown state", "")
        }
    }
}
