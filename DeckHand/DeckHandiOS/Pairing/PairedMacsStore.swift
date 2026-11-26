//
//  PairedMacsStore.swift
//  DeckHandiOS
//
//  This device's side of pairing (S4):
//
//  - The Macs it is paired with (PixelHandCore's `RemotePairingBook`, kept
//    in Application Support). The Mac's `pairing.pairedStatus` is the
//    source of truth; this list follows it and powers Settings › Paired
//    Macs and the "Paired" badge in the picker.
//  - The live session's pairing state, for views that don't hold the
//    session model (the approval overlay, the code entry sheet, Settings):
//    which Mac, whether it's paired, the last code result, and how to send
//    to it. `ControlSessionModel+Pairing` writes it.
//  - A QR invite scanned in the picker, waiting for the session with that
//    Mac to start.
//

import Foundation
import Observation

@MainActor
@Observable
final class PairedMacsStore {
    static let shared = PairedMacsStore()

    /// Paired Macs, oldest pairing first.
    private(set) var macs: [PairedDevice] = []
    /// Macs forgotten while out of reach; told on next contact.
    private(set) var pendingForgets: [PairedDeviceRef] = []

    // MARK: Live session

    /// The Mac of the running session, as its handshake proved it. `nil`
    /// when no session runs (or the Mac's identity couldn't be verified).
    private(set) var liveMac: TrustCandidate?
    /// Whether the live session's Mac says this device is paired.
    private(set) var livePaired = false
    /// The Mac's answer to the last code this device sent, and a counter so
    /// the same answer twice still reads as new.
    private(set) var lastCodeResult: PairingCodeResult?
    private(set) var codeResultCount = 0
    /// Whether a code was sent and its answer hasn't arrived.
    private(set) var isAwaitingCodeResult = false
    /// A line for the code sheet that isn't the Mac's answer (for example,
    /// a QR code made by a different Mac).
    var notice: String?
    @ObservationIgnored private var liveSend: (@MainActor (PairingMessage) async -> Bool)?
    @ObservationIgnored private var liveToken: UUID?

    /// A QR invite scanned in the picker; sent when the session with its
    /// Mac reaches the approval step.
    var pendingInvite: PairingInvite?

    /// A code typed while not connected to its Mac (from the picker, or
    /// after the Mac dropped or refused the request): sent once a session
    /// with that Mac reaches the approval step (VQ-003, VQ-037). Unlike a
    /// QR invite it carries no key, so it goes to the Mac with that Loom
    /// device ID; the Mac still checks the code against what it shows.
    struct PendingCode: Equatable {
        var code: PairingCode
        var macDeviceID: UUID
        var macName: String
    }

    var pendingCode: PendingCode?

    /// The Loom device ID of the Mac the last session was with, kept after
    /// it ends so the code sheet can reconnect to it.
    private(set) var lastMacDeviceID: UUID?

    /// The Mac last tapped in the picker, and when: the Mac that asked, for
    /// the code sheet's default (VQ-100). Kept here because the picker is
    /// rebuilt after a refused or cancelled request.
    private(set) var lastConnectAttempt: UUID?
    private(set) var lastConnectAttemptAt: Date?

    func noteConnectAttempt(to deviceID: UUID) {
        lastConnectAttempt = deviceID
        lastConnectAttemptAt = Date()
    }

    /// The Mac that asked, while that is recent.
    var askingMacDeviceID: UUID? {
        PairingTargetChoice.askingDeviceID(lastAttempt: lastConnectAttempt, at: lastConnectAttemptAt, now: Date())
    }

    /// Whether a code can go out right now on a live session with
    /// `deviceID` (or with any Mac when `deviceID` is `nil`).
    func canSendNow(to deviceID: UUID?) -> Bool {
        guard liveSend != nil, let liveMac else { return false }
        return deviceID == nil || liveMac.deviceID == deviceID
    }

    /// Keeps `code` for `macDeviceID`; the next session with that Mac sends
    /// it. Shows "Pairing…" meanwhile.
    func holdForNextConnection(_ code: PairingCode, macDeviceID: UUID, macName: String) {
        pendingCode = PendingCode(code: code, macDeviceID: macDeviceID, macName: macName)
        lastCodeResult = nil
        notice = nil
        isAwaitingCodeResult = true
    }

    @ObservationIgnored private var book: RemotePairingBook
    private let fileURL: URL?

    init(fileURL: URL? = PairedMacsStore.defaultFileURL) {
        self.fileURL = fileURL
        book = Self.load(from: fileURL)
        publish()
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PairedMacs.json")
    }

    /// Whether any record names this Loom device ID. Display only (the
    /// picker's badge): the Mac decides trust, from the identity key.
    func isPaired(deviceID: UUID) -> Bool {
        macs.contains { $0.deviceID == deviceID }
    }

    // MARK: - Session lifetime (ControlSessionModel+Pairing)

    /// Starts tracking a session. Returns a token for `identified` and
    /// `endSession`, so a session that ends late can't clear a newer one.
    func beginSession(send: @escaping @MainActor (PairingMessage) async -> Bool) -> UUID {
        let token = UUID()
        liveToken = token
        liveMac = nil
        livePaired = false
        lastCodeResult = nil
        // A held code (`pendingCode`) keeps "Pairing…" up until it is sent.
        isAwaitingCodeResult = pendingCode != nil
        notice = nil
        liveSend = send
        return token
    }

    /// The session's Mac, once its verified identity is read.
    func identified(mac: TrustCandidate?, token: UUID) {
        guard token == liveToken else { return }
        liveMac = mac
        if let mac { lastMacDeviceID = mac.deviceID }
    }

    func endSession(token: UUID) {
        guard token == liveToken else { return }
        liveToken = nil
        liveMac = nil
        livePaired = false
        isAwaitingCodeResult = pendingCode != nil
        liveSend = nil
    }

    /// Applies the Mac's `pairedStatus`. Returns the book's action, so the
    /// session can send a held `forget`.
    func macReported(paired: Bool) -> RemotePairingBook.Action {
        livePaired = paired
        guard let mac = liveMac else { return .none }
        let action = book.macReported(paired: paired, mac: mac, at: Date())
        if action != .none { save() }
        return action
    }

    func received(_ result: PairingCodeResult) {
        lastCodeResult = result
        codeResultCount += 1
        isAwaitingCodeResult = false
    }

    // MARK: - User actions

    /// Sends a pairing code to the live session's Mac.
    ///
    /// - Returns: `false` when there is no live session to send it to.
    @discardableResult
    func submit(_ code: PairingCode) async -> Bool {
        guard let liveSend else { return false }
        lastCodeResult = nil
        notice = nil
        isAwaitingCodeResult = true
        let sent = await liveSend(.submitCode(code: code.digits))
        if !sent { isAwaitingCodeResult = false }
        return sent
    }

    /// "Forget" in Settings. A connected Mac is told now and ends the
    /// session; one that's away is told the next time it connects.
    func forget(_ ref: PairedDeviceRef) async {
        let isLive = liveMac?.ref == ref
        book.forget(ref, isConnected: isLive)
        save()
        if isLive, let liveSend {
            _ = await liveSend(.forget)
        }
    }

    // MARK: - Storage

    private func publish() {
        macs = book.macs.devices
        pendingForgets = book.pendingForgets
    }

    private static func load(from url: URL?) -> RemotePairingBook {
        guard let url, let data = try? Data(contentsOf: url) else { return RemotePairingBook() }
        do {
            return try RemotePairingBook(storage: data)
        } catch {
            DeckHandLog.app.error("Paired Macs file unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            return RemotePairingBook()
        }
    }

    private func save() {
        publish()
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try book.encoded().write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            DeckHandLog.app.error("Saving paired Macs failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
