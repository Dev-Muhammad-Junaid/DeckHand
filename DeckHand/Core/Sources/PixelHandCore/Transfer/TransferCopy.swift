//
//  TransferCopy.swift
//  PixelHandCore
//
//  S1/S2: every line the Send sheet, the Inbox, the prompts and the Mac's
//  panel show about a transfer. Device-neutral; names the other device
//  ("Studio is locked"), never an id.
//

import Foundation

public enum TransferCopy {
    /// The sender's line for a refusal. `receiver` is the other device's
    /// name.
    public static func refused(_ reason: TransferRefusal, receiver: String) -> String {
        switch reason {
        case .declined: "\(receiver) declined it."
        case .macLocked: "\(receiver) is locked. Unlock it and send again."
        case .notPaired: "\(receiver) only takes items from paired devices. Pair this device first."
        case .needsPro: "Sending to \(receiver) needs Pixel Hand Pro on it."
        case .tooLarge: "It's too large to send (the limit is \(TransferProgressMeter.size(TransferPolicy.maxFileBytes)))."
        case .noSpace: "\(receiver) doesn't have enough free space."
        case .unsupported: "\(receiver) can't take this item. Update Pixel Hand on both devices."
        }
    }

    /// The sender's line once the receiver stored it.
    public static func saved(_ landing: TransferLanding, receiver: String) -> String {
        switch landing {
        case .downloads: "Saved to Downloads on \(receiver)."
        case .browser: "Opened on \(receiver)."
        case .clipboard: "On \(receiver)'s clipboard."
        case .inbox: "In \(receiver)'s Inbox."
        }
    }

    public static func failed(_ failure: TransferFailure, receiver: String) -> String {
        switch failure {
        case .integrity: "It arrived damaged. Send it again."
        case .writeFailed: "\(receiver) couldn't save it."
        case .interrupted: "The connection to \(receiver) dropped. It continues when you're back."
        case .cancelled: "Cancelled."
        }
    }

    /// The prompt's question. `sender` is the device's name.
    public static func prompt(kind: TransferKind, name: String, byteCount: UInt64, sender: String) -> String {
        let what = switch kind {
        case .photo: "a photo"
        case .file: "“\(name)”"
        case .link: "a link"
        case .text: "some text"
        }
        return "\(sender) wants to send you \(what) (\(TransferProgressMeter.size(byteCount)))."
    }

    public static func waiting(for macName: String?) -> String {
        if let macName { return "Waiting for \(macName)" }
        return "Waiting for your Mac"
    }

    public static func sending(to receiver: String) -> String { "Sending to \(receiver)…" }

    public static let alwaysFromDevice = "Always from this device"
    public static let accept = "Accept"
    public static let decline = "Decline"
    public static let emptyInbox = "Items your Mac sends you land here."
    public static let shareExtensionQueued = "It goes to your Mac the next time Pixel Hand connects."
    public static let shareExtensionNoMac = "Pair a Mac in Pixel Hand first."
}

/// S2: the Send sheet's dot beam. Dots travel from this device's glyph to
/// the receiver's while bytes move, turn mint when the receiver confirms
/// it saved the item, then collapse into a check.
public enum TransferBeamPhase: Equatable, Sendable {
    case idle
    /// Waiting for the receiver's Accept.
    case asking
    /// Moving bytes; `fraction` fills the beam.
    case sending(fraction: Double)
    /// The receiver saved it: mint, then the check.
    case delivered
    /// Refused or failed: the beam drops and shows a cross.
    case stopped

    /// How many of `dotCount` beam dots are lit.
    public func litDots(of dotCount: Int) -> Int {
        switch self {
        case .idle, .stopped: 0
        case .asking: 1
        case let .sending(fraction): max(1, min(dotCount, Int((fraction * Double(dotCount)).rounded(.up))))
        case .delivered: dotCount
        }
    }

    /// The beam phase for a sender's view of one transfer.
    public static func phase(status: TransferStatus?, fraction: Double?) -> TransferBeamPhase {
        switch status {
        case .saved: return .delivered
        case .refused, .failed: return .stopped
        case .awaitingApproval: return fraction.map { $0 > 0 ? .sending(fraction: $0) : .asking } ?? .asking
        case nil: return fraction.map { .sending(fraction: $0) } ?? .idle
        }
    }
}
