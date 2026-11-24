//
//  TransferPolicy.swift
//  PixelHandCore
//
//  S1/S2: the rules every received item goes through, on both sides.
//
//  1. Only a paired device can send (`notPaired`). Trust comes from the
//     Loom identity key the pairing lane stores, never from the offer.
//  2. The Mac refuses while it is locked or another user has its screen
//     (`macLocked`; `LockPolicy.allowsIncomingTransfer`).
//  3. On iPhone and iPad sharing is Pixel Hand Pro (`needsPro`). The Mac
//     app is free and doesn't check: the device that pays is the one that
//     asks or answers.
//  4. Size caps per kind (`tooLarge`), and a free-space check
//     (`noSpace`) with headroom.
//  5. Links and text are always taken (they are tiny and land in the
//     Inbox or the browser). Files and photos up to `quietAcceptBytes` are
//     taken without asking from a paired device; bigger ones ask, unless
//     the person chose "Always from this device", and anything from
//     `alwaysAskBytes` up always asks.
//

import Foundation

/// Why a receiver won't take an item. Sent back as
/// `sharing.transferStatus(transferID:status: .refused(reason:))`.
public enum TransferRefusal: String, Codable, Sendable, CaseIterable, Hashable {
    /// The person tapped Decline (or the prompt timed out).
    case declined
    /// The Mac is locked or another user is on its screen.
    case macLocked
    /// The sender isn't on this device's paired list.
    case notPaired
    /// The iPhone or iPad has no Pixel Hand Pro.
    case needsPro
    /// Over the size cap.
    case tooLarge
    /// Not enough free space on the receiver.
    case noSpace
    /// Not a Pixel Hand item, or from a newer build.
    case unsupported
}

/// Where a received item ended up.
public enum TransferLanding: String, Codable, Sendable, CaseIterable, Hashable {
    /// `~/Downloads/Pixel Hand` on the Mac.
    case downloads
    /// Opened in the Mac's default browser.
    case browser
    /// Put on the Mac's clipboard (and saved as a `.txt`).
    case clipboard
    /// The device's Inbox.
    case inbox
}

/// Why a transfer that was accepted didn't finish.
public enum TransferFailure: String, Codable, Sendable, CaseIterable, Hashable {
    /// The bytes didn't match the sender's SHA-256.
    case integrity
    /// The receiver couldn't write or move the file.
    case writeFailed
    /// The connection or the sender ended it.
    case interrupted
    /// The receiver's person cancelled it.
    case cancelled
}

/// The receiver's app-level answer, beyond Loom's accept / decline.
public enum TransferStatus: Codable, Sendable, Equatable, Hashable {
    /// The receiver is asking its person.
    case awaitingApproval
    /// Not taken.
    case refused(reason: TransferRefusal)
    /// Received in full and stored.
    case saved(landing: TransferLanding)
    /// Accepted but not finished.
    case failed(reason: TransferFailure)

    /// Nothing more will happen to the transfer.
    public var isFinal: Bool {
        if case .awaitingApproval = self { return false }
        return true
    }
}

/// What the receiver knows when an offer arrives.
public struct TransferReceiveContext: Equatable, Sendable {
    public var senderIsPaired: Bool
    /// Mac: the lock gate's state. A device passes `.unlocked`.
    public var lockState: MacLockState
    /// Device: Pixel Hand Pro (trial included). The Mac passes `true`.
    public var hasPro: Bool
    /// The person chose "Always from this device".
    public var alwaysAcceptFromSender: Bool
    /// Free bytes where the item will land, or `nil` when unknown.
    public var freeBytes: UInt64?

    public init(
        senderIsPaired: Bool,
        lockState: MacLockState = .unlocked,
        hasPro: Bool = true,
        alwaysAcceptFromSender: Bool = false,
        freeBytes: UInt64? = nil
    ) {
        self.senderIsPaired = senderIsPaired
        self.lockState = lockState
        self.hasPro = hasPro
        self.alwaysAcceptFromSender = alwaysAcceptFromSender
        self.freeBytes = freeBytes
    }
}

public enum TransferDecision: Equatable, Sendable {
    case accept
    /// Show Accept / Decline (and "Always from this device").
    case ask
    case refuse(TransferRefusal)
}

public enum TransferPolicy {
    /// Largest file or photo either side sends or takes (16 GB).
    public static let maxFileBytes: UInt64 = 16 * 1024 * 1024 * 1024
    /// Largest link or text (1 MB).
    public static let maxInlineBytes: UInt64 = 1024 * 1024
    /// Files up to this size from a paired device land without a prompt.
    public static let quietAcceptBytes: UInt64 = 100 * 1024 * 1024
    /// From this size the receiver always asks, "Always" or not.
    public static let alwaysAskBytes: UInt64 = 2 * 1024 * 1024 * 1024
    /// Free space kept on top of the item.
    public static let freeSpaceHeadroom: UInt64 = 512 * 1024 * 1024
    /// How long a prompt waits before it counts as Decline. Shorter than
    /// Loom's offer timeout (120 s), so the sender hears why.
    public static let promptTimeout: Duration = .seconds(100)
    /// Items a device keeps waiting to send.
    public static let maxOutboxItems = 50

    public static func maxBytes(for kind: TransferKind) -> UInt64 {
        kind.isInline ? maxInlineBytes : maxFileBytes
    }

    /// Whether this side may offer `byteCount` bytes of `kind`.
    public static func canSend(kind: TransferKind, byteCount: UInt64) -> Bool {
        byteCount <= maxBytes(for: kind) && (byteCount > 0 || !kind.isInline)
    }

    /// The receiver's decision on one offer. Order matters: who is asking
    /// before what they send.
    public static func decide(_ manifest: TransferManifest, context: TransferReceiveContext) -> TransferDecision {
        guard context.senderIsPaired else { return .refuse(.notPaired) }
        guard LockPolicy.allowsIncomingTransfer(state: context.lockState) else { return .refuse(.macLocked) }
        guard context.hasPro else { return .refuse(.needsPro) }
        guard manifest.byteCount <= maxBytes(for: manifest.kind) else { return .refuse(.tooLarge) }
        if let free = context.freeBytes {
            let (needed, overflow) = manifest.byteCount.addingReportingOverflow(freeSpaceHeadroom)
            if overflow || needed > free { return .refuse(.noSpace) }
        }
        if manifest.kind.isInline { return .accept }
        if manifest.byteCount >= alwaysAskBytes { return .ask }
        if manifest.byteCount <= quietAcceptBytes || context.alwaysAcceptFromSender { return .accept }
        return .ask
    }
}
