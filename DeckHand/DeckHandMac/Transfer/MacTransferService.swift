//
//  MacTransferService.swift
//  DeckHandMac – Transfer
//
//  S1: files, photos, links and text between the Mac and its paired
//  iPhones and iPads, both ways. Rules in Core (`TransferPolicy`,
//  `TransferManifest`, `LockPolicy.allowsIncomingTransfer`).
//
//  Bytes go through Loom's transfer engine, one per connection
//  (`LoomConnectionHandle.transferEngine`): its own control stream and a
//  data stream per transfer, chunked, windowed, resumable from a
//  contiguous offset and SHA-256 checked. Never the JSON control stream.
//  The receiver's app-level answer (refused why, saved where) goes back as
//  `sharing.transferStatus`.
//
//  Receiving:
//   • Only from a paired device (`DeviceAuthorizationManager.isPaired`),
//     never while the Mac is locked or off console; the lock cancels
//     transfers in flight.
//   • Links and text and files up to 100 MB land without a prompt; bigger
//     ones ask (the menu-bar panel and a floating prompt), "Always from
//     this device" up to 2 GB.
//   • Partial files live in Application Support under the transfer's id,
//     so the same offer after a reconnect resumes where it stopped.
//   • Files land in `~/Downloads/Pixel Hand` and are revealed in Finder;
//     links open in the default browser; text goes on the clipboard and
//     into a `.txt`.
//
//  Sending: the menu-bar panel (Send File…, Send Clipboard, drop) and the
//  Services menu. Each send keeps its offer, so if the device drops and
//  comes back while the Mac app runs, it is offered again with the same id
//  and resumes.
//
//  Registered per approved connection from `MacSystemSession` (one
//  announced line each in `LockGate.swift`).
//

import AppKit
import CryptoKit
import Foundation
import Loom
import LoomKit
import UniformTypeIdentifiers

@MainActor
final class MacTransferService: ObservableObject {
    static let shared = MacTransferService()

    /// One transfer as the panel shows it.
    struct Row: Identifiable, Equatable {
        enum Direction { case incoming, outgoing }
        let id: UUID
        let direction: Direction
        let kind: TransferKind
        let name: String
        let deviceName: String
        /// The other device's Loom device ID.
        let peerID: UUID
        var meter: TransferProgressMeter
        /// The receiver's answer (outgoing) or ours (incoming).
        var status: TransferStatus?
        var isActive: Bool
        /// The landed file, for Show in Finder.
        var savedURL: URL?

        var caption: String {
            switch status {
            case .awaitingApproval?:
                return direction == .outgoing ? "Waiting for \(deviceName) to accept" : "Waiting for you"
            case let .refused(reason)?:
                return direction == .outgoing ? TransferCopy.refused(reason, receiver: deviceName) : "Not taken"
            case let .saved(landing)?:
                return direction == .outgoing ? TransferCopy.saved(landing, receiver: deviceName) : "Saved"
            case let .failed(reason)?:
                return TransferCopy.failed(reason, receiver: deviceName)
            case nil:
                return meter.caption
            }
        }

        var beam: TransferBeamPhase {
            if direction == .incoming {
                if case .saved? = status { return .delivered }
                if status?.isFinal == true { return .stopped }
                return .sending(fraction: meter.fraction)
            }
            return TransferBeamPhase.phase(status: status, fraction: isActive ? meter.fraction : nil)
        }
    }

    /// An incoming item waiting for Accept / Decline.
    struct Prompt: Identifiable, Equatable {
        let id: UUID
        let message: String
        let deviceName: String
        let senderKey: String
        let canAlwaysAccept: Bool
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var prompts: [Prompt] = []
    /// Paired devices that can be sent to now, by connection id.
    @Published private(set) var targets: [UUID: String] = [:]

    private var connections: [UUID: LoomConnectionHandle] = [:]
    private var listenTasks: [UUID: Task<Void, Never>] = [:]
    private var incoming: [UUID: (transfer: LoomIncomingTransfer, connectionID: UUID, manifest: TransferManifest)] = [:]
    private var outgoing: [UUID: (transfer: LoomOutgoingTransfer, connectionID: UUID)] = [:]
    private var promptDecisions: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// Sends to re-offer when their device comes back, by Loom device ID.
    private var resendable: [UUID: [PendingSend]] = [:]

    private struct PendingSend {
        let offerID: UUID
        let url: URL
        let manifest: TransferManifest
        let sha256: String?
        let isTemporary: Bool
    }

    private static let alwaysKey = "transfer.alwaysAcceptFrom"

    private init() {
        // Finder › Services › "Send to iPhone or iPad with Pixel Hand".
        NSApp?.servicesProvider = MacTransferServicesProvider.shared
        cleanOldPartials()
    }

    // MARK: - Connections

    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {
        connections[id] = handle
        refreshTargets()
        listenTasks[id]?.cancel()
        listenTasks[id] = Task { [weak self] in
            for await transfer in handle.incomingTransfers {
                await self?.received(transfer, from: handle, connectionID: id)
            }
        }
        // Anything that was moving to this device when it dropped.
        if let pending = resendable[handle.peer.deviceID], !pending.isEmpty {
            Task { [weak self] in
                // Give pairing a moment to confirm before offering.
                try? await Task.sleep(for: .seconds(1))
                for send in pending { await self?.offer(send, to: handle, connectionID: id) }
            }
        }
    }

    func removeConnection(id: UUID) {
        connections.removeValue(forKey: id)
        listenTasks.removeValue(forKey: id)?.cancel()
        refreshTargets()
        for (transferID, entry) in incoming where entry.connectionID == id {
            incoming.removeValue(forKey: transferID)
            finishPrompt(transferID, accepted: false)
            markRow(transferID) { $0.isActive = false; if $0.status == nil || $0.status == .awaitingApproval { $0.status = .failed(reason: .interrupted) } }
        }
        for (transferID, entry) in outgoing where entry.connectionID == id {
            outgoing.removeValue(forKey: transferID)
            markRow(transferID) { $0.isActive = false; if $0.status == nil || $0.status == .awaitingApproval { $0.status = .failed(reason: .interrupted) } }
        }
    }

    /// The Mac locked or another user took the screen: cancel incoming
    /// transfers and tell their senders why.
    func lockStateChanged(_ state: MacLockState) {
        guard !LockPolicy.allowsIncomingTransfer(state: state) else { return }
        for (transferID, entry) in incoming {
            refuse(entry.transfer, transferID: transferID, reason: .macLocked, connectionID: entry.connectionID)
            deletePartial(transferID)
        }
        for prompt in prompts { finishPrompt(prompt.id, accepted: false) }
    }

    /// Paired, connected devices; refreshed when pairing changes too.
    func refreshTargets() {
        var next: [UUID: String] = [:]
        for (id, handle) in connections where DeviceAuthorizationManager.shared.isPaired(connectionID: id) {
            next[id] = handle.peer.name
        }
        if next != targets { targets = next }
    }

    // MARK: - Receiving

    private func received(_ transfer: LoomIncomingTransfer, from handle: LoomConnectionHandle, connectionID: UUID) async {
        let offer = transfer.offer
        let manifest: TransferManifest
        switch TransferManifest.read(logicalName: offer.logicalName, byteLength: offer.byteLength, contentType: offer.contentType, metadata: offer.metadata) {
        case let .success(read):
            manifest = read
        case let .failure(error):
            refuse(transfer, transferID: offer.id, reason: error == .tooLarge ? .tooLarge : .unsupported, connectionID: connectionID)
            return
        }
        let senderKey = handle.peer.deviceID.uuidString
        let context = TransferReceiveContext(
            senderIsPaired: DeviceAuthorizationManager.shared.isPaired(connectionID: connectionID),
            lockState: MacLockMonitor.shared.state,
            hasPro: true, // the Mac app is free; the device checks its own Pro
            alwaysAcceptFromSender: alwaysAccepted.contains(senderKey),
            freeBytes: Self.freeBytes(at: Self.downloadsFolder)
        )
        var decision = TransferPolicy.decide(manifest, context: context)
        // A resume of something already accepted (its partial file is
        // here) doesn't ask again.
        if decision == .ask, (Self.fileSize(Self.partialURL(for: offer.id)) ?? 0) > 0 {
            decision = .accept
        }
        DeckHandLog.connection.info("Transfer: \(manifest.kind.rawValue, privacy: .public) of \(manifest.byteCount, privacy: .public) B offered; \(String(describing: decision), privacy: .public)")
        switch decision {
        case let .refuse(reason):
            refuse(transfer, transferID: offer.id, reason: reason, connectionID: connectionID)
        case .accept:
            await accept(transfer, manifest: manifest, deviceName: handle.peer.name, connectionID: connectionID)
        case .ask:
            incoming[offer.id] = (transfer, connectionID, manifest)
            sendStatus(.awaitingApproval, for: offer.id, connectionID: connectionID)
            let accepted = await ask(
                Prompt(
                    id: offer.id,
                    message: TransferCopy.prompt(kind: manifest.kind, name: manifest.name, byteCount: manifest.byteCount, sender: handle.peer.name),
                    deviceName: handle.peer.name,
                    senderKey: senderKey,
                    canAlwaysAccept: manifest.byteCount < TransferPolicy.alwaysAskBytes
                )
            )
            guard incoming[offer.id] != nil else { return } // dropped or locked meanwhile
            // The lock may have come while the prompt was up.
            if accepted, LockPolicy.allowsIncomingTransfer(state: MacLockMonitor.shared.state) {
                await accept(transfer, manifest: manifest, deviceName: handle.peer.name, connectionID: connectionID)
            } else {
                let reason: TransferRefusal = accepted ? .macLocked : .declined
                refuse(transfer, transferID: offer.id, reason: reason, connectionID: connectionID)
            }
        }
    }

    private func accept(_ transfer: LoomIncomingTransfer, manifest: TransferManifest, deviceName: String, connectionID: UUID) async {
        let peerID = connections[connectionID]?.peer.deviceID ?? UUID()
        let id = transfer.offer.id
        incoming[id] = (transfer, connectionID, manifest)
        let partial = Self.partialURL(for: id)
        let resumeAt = TransferResume.offset(partialBytes: Self.fileSize(partial), totalBytes: manifest.byteCount)
        upsertRow(Row(id: id, direction: .incoming, kind: manifest.kind, name: manifest.name, deviceName: deviceName, peerID: peerID, meter: TransferProgressMeter(totalBytes: manifest.byteCount, startingAt: resumeAt), status: nil, isActive: true))
        do {
            try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
            if resumeAt == 0 { try? FileManager.default.removeItem(at: partial) }
            let sink = try LoomFileTransferSink(url: partial)
            let progress = transfer.makeProgressObserver()
            Task { [weak self] in
                for await event in progress {
                    await self?.incomingProgress(event, id: id)
                }
            }
            try await transfer.accept(using: sink, resumeOffset: resumeAt)
            if resumeAt > 0 {
                DeckHandLog.connection.info("Transfer: resuming at \(resumeAt, privacy: .public) of \(manifest.byteCount, privacy: .public) B")
            }
        } catch {
            DeckHandLog.connection.error("Transfer: couldn't accept: \(error.localizedDescription, privacy: .public)")
            incoming.removeValue(forKey: id)
            sendStatus(.failed(reason: .writeFailed), for: id, connectionID: connectionID)
            markRow(id) { $0.isActive = false; $0.status = .failed(reason: .writeFailed) }
        }
    }

    private func incomingProgress(_ event: LoomTransferProgress, id: UUID) async {
        markRow(id) { $0.meter.update(bytes: event.bytesTransferred, at: ProcessInfo.processInfo.systemUptime) }
        switch event.state {
        case .completed:
            guard let entry = incoming.removeValue(forKey: id) else { return }
            await land(id: id, manifest: entry.manifest, connectionID: entry.connectionID)
        case .failed:
            // Integrity failures leave a useless partial; a drop keeps it.
            guard let entry = incoming.removeValue(forKey: id) else { return }
            let complete = event.bytesTransferred >= entry.manifest.byteCount
            if complete { deletePartial(id) }
            let reason: TransferFailure = complete ? .integrity : .interrupted
            sendStatus(.failed(reason: reason), for: id, connectionID: entry.connectionID)
            markRow(id) { $0.isActive = false; $0.status = .failed(reason: reason) }
        case .cancelled, .declined:
            guard incoming.removeValue(forKey: id) != nil else { return }
            deletePartial(id)
            markRow(id) {
                $0.isActive = false
                if $0.status == nil { $0.status = .failed(reason: .cancelled) }
            }
        default:
            break
        }
    }

    /// Moves a finished item to where it belongs and tells the sender.
    private func land(id: UUID, manifest: TransferManifest, connectionID: UUID) async {
        let partial = Self.partialURL(for: id)
        // A lock that came during the last chunk still wins.
        guard LockPolicy.allowsIncomingTransfer(state: MacLockMonitor.shared.state) else {
            deletePartial(id)
            sendStatus(.refused(reason: .macLocked), for: id, connectionID: connectionID)
            markRow(id) { $0.isActive = false; $0.status = .refused(reason: .macLocked) }
            return
        }
        var landing = TransferLanding.downloads
        var savedURL: URL?
        do {
            if manifest.kind.isInline {
                let data = try Data(contentsOf: partial)
                deletePartial(id)
                guard let text = TransferInlineText.text(from: data) else { throw CocoaError(.fileReadCorruptFile) }
                if manifest.kind == .link, let url = TransferInlineText.webLink(text) {
                    NSWorkspace.shared.open(url)
                    landing = .browser
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    savedURL = try Self.store(Data(text.utf8), named: TransferInlineText.fileName(for: text, kind: manifest.kind))
                    landing = .clipboard
                }
            } else {
                savedURL = try Self.move(partial, named: manifest.name)
                if let savedURL { NSWorkspace.shared.activateFileViewerSelecting([savedURL]) }
            }
            MenuBarActivity.shared.noteReceive()
            sendStatus(.saved(landing: landing), for: id, connectionID: connectionID)
            markRow(id) { $0.isActive = false; $0.status = .saved(landing: landing); $0.savedURL = savedURL }
        } catch {
            DeckHandLog.connection.error("Transfer: couldn't save: \(error.localizedDescription, privacy: .public)")
            deletePartial(id)
            sendStatus(.failed(reason: .writeFailed), for: id, connectionID: connectionID)
            markRow(id) { $0.isActive = false; $0.status = .failed(reason: .writeFailed) }
        }
    }

    private func refuse(_ transfer: LoomIncomingTransfer, transferID: UUID, reason: TransferRefusal, connectionID: UUID) {
        incoming.removeValue(forKey: transferID)
        finishPrompt(transferID, accepted: false)
        // Status first, so the sender knows why before Loom's decline lands.
        sendStatus(.refused(reason: reason), for: transferID, connectionID: connectionID)
        Task { try? await transfer.decline() }
        markRow(transferID) { $0.isActive = false; $0.status = .refused(reason: reason) }
    }

    /// The panel's Cancel on an incoming row.
    func cancelIncoming(_ id: UUID) {
        guard let entry = incoming.removeValue(forKey: id) else { return }
        sendStatus(.failed(reason: .cancelled), for: id, connectionID: entry.connectionID)
        Task { try? await entry.transfer.decline() }
        deletePartial(id)
        markRow(id) { $0.isActive = false; $0.status = .failed(reason: .cancelled) }
    }

    // MARK: - Prompts

    private func ask(_ prompt: Prompt) async -> Bool {
        prompts.append(prompt)
        MacTransferPromptPanel.shared.show()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: TransferPolicy.promptTimeout)
            self?.finishPrompt(prompt.id, accepted: false)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            promptDecisions[prompt.id] = continuation
        }
    }

    /// The prompt's buttons.
    func answer(_ promptID: UUID, accept: Bool, always: Bool = false) {
        if always, let prompt = prompts.first(where: { $0.id == promptID }) {
            var set = alwaysAccepted
            set.insert(prompt.senderKey)
            UserDefaults.standard.set(Array(set), forKey: Self.alwaysKey)
        }
        finishPrompt(promptID, accepted: accept)
    }

    private func finishPrompt(_ id: UUID, accepted: Bool) {
        prompts.removeAll { $0.id == id }
        if prompts.isEmpty { MacTransferPromptPanel.shared.hide() }
        promptDecisions.removeValue(forKey: id)?.resume(returning: accepted)
    }

    private var alwaysAccepted: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.alwaysKey) ?? [])
    }

    // MARK: - Sending

    /// Sends files (photos and movies go as photos) to a paired device.
    func send(files urls: [URL], to connectionID: UUID) {
        guard let handle = connections[connectionID], targets[connectionID] != nil else { return }
        for url in urls {
            Task { [weak self] in
                guard let size = Self.fileSize(url) else { return }
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard !isDirectory else {
                    DeckHandLog.connection.info("Transfer: folders aren't sent")
                    return
                }
                let kind: TransferKind = type.conforms(to: .image) || type.conforms(to: .movie) ? .photo : .file
                guard TransferPolicy.canSend(kind: kind, byteCount: size) else { return }
                let manifest = TransferManifest(kind: kind, name: url.lastPathComponent, byteCount: size, contentType: type.identifier)
                let hash = await Self.sha256(of: url)
                let send = PendingSend(offerID: UUID(), url: url, manifest: manifest, sha256: hash, isTemporary: false)
                await self?.offer(send, to: handle, connectionID: connectionID)
            }
        }
    }

    /// Sends text (or a link, when the text is one web address).
    func send(text: String, to connectionID: UUID) {
        guard let handle = connections[connectionID], targets[connectionID] != nil else { return }
        let data = Data(text.utf8)
        let kind: TransferKind = TransferInlineText.webLink(text) != nil ? .link : .text
        guard TransferPolicy.canSend(kind: kind, byteCount: UInt64(data.count)) else { return }
        let manifest = TransferManifest(kind: kind, name: TransferInlineText.fileName(for: text, kind: kind), byteCount: UInt64(data.count), contentType: "public.utf8-plain-text")
        let id = UUID()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pixelhand-\(id.uuidString).txt")
        do { try data.write(to: url) } catch { return }
        let send = PendingSend(offerID: id, url: url, manifest: manifest, sha256: SHA256.hash(data: data).hexString, isTemporary: true)
        Task { await offer(send, to: handle, connectionID: connectionID) }
    }

    /// The clipboard's files, or else its text.
    func sendClipboard(to connectionID: UUID) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            send(files: urls, to: connectionID)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            send(text: text, to: connectionID)
        }
    }

    private func offer(_ send: PendingSend, to handle: LoomConnectionHandle, connectionID: UUID) async {
        let manifest = send.manifest
        let offer = LoomTransferOffer(
            id: send.offerID,
            logicalName: manifest.name,
            byteLength: manifest.byteCount,
            contentType: manifest.contentType,
            sha256Hex: send.sha256,
            metadata: manifest.metadata
        )
        upsertRow(Row(id: offer.id, direction: .outgoing, kind: manifest.kind, name: manifest.name, deviceName: handle.peer.name, peerID: handle.peer.deviceID, meter: TransferProgressMeter(totalBytes: manifest.byteCount), status: nil, isActive: true))
        let deviceID = handle.peer.deviceID
        resendable[deviceID, default: []].removeAll { $0.offerID == send.offerID }
        resendable[deviceID, default: []].append(send)
        do {
            let source = try LoomFileTransferSource(url: send.url)
            let transfer = try await handle.transferEngine.offerTransfer(offer, source: source)
            outgoing[offer.id] = (transfer, connectionID)
            for await event in transfer.makeProgressObserver() {
                outgoingProgress(event, id: offer.id, deviceID: deviceID)
            }
        } catch {
            DeckHandLog.connection.error("Transfer: couldn't offer: \(error.localizedDescription, privacy: .public)")
            markRow(offer.id) { $0.isActive = false; $0.status = .failed(reason: .interrupted) }
        }
    }

    private func outgoingProgress(_ event: LoomTransferProgress, id: UUID, deviceID: UUID) {
        markRow(id) { $0.meter.update(bytes: event.bytesTransferred, at: ProcessInfo.processInfo.systemUptime) }
        switch event.state {
        case .completed:
            outgoing.removeValue(forKey: id)
            markRow(id) { $0.isActive = false }
            // Done unless the receiver says otherwise (its status follows).
            forgetResend(id, deviceID: deviceID)
        case .declined, .cancelled:
            outgoing.removeValue(forKey: id)
            markRow(id) {
                $0.isActive = false
                if $0.status == nil || $0.status == .awaitingApproval { $0.status = .refused(reason: .declined) }
            }
            forgetResend(id, deviceID: deviceID)
        case .failed:
            outgoing.removeValue(forKey: id)
            markRow(id) { $0.isActive = false; if $0.status == nil { $0.status = .failed(reason: .interrupted) } }
        default:
            break
        }
    }

    /// The panel's Cancel on an outgoing row.
    func cancelOutgoing(_ id: UUID) {
        if let entry = outgoing.removeValue(forKey: id) {
            Task { await entry.transfer.cancel() }
        }
        for deviceID in resendable.keys { forgetResend(id, deviceID: deviceID) }
        markRow(id) { $0.isActive = false; $0.status = .failed(reason: .cancelled) }
    }

    /// `sharing.transferStatus` from a device about something the Mac sent.
    func receivedStatus(_ status: TransferStatus, for id: UUID, from connectionID: UUID) {
        // Only for transfers this Mac offered on that connection.
        guard let row = rows.first(where: { $0.id == id && $0.direction == .outgoing }),
              connections[connectionID]?.peer.deviceID == row.peerID else { return }
        markRow(id) { $0.status = status }
        // A drop keeps the send for a resume; anything else final ends it.
        if status.isFinal, status != .failed(reason: .interrupted) {
            forgetResend(id, deviceID: row.peerID)
        }
    }

    private func forgetResend(_ id: UUID, deviceID: UUID) {
        guard var list = resendable[deviceID], let index = list.firstIndex(where: { $0.offerID == id }) else { return }
        let send = list.remove(at: index)
        resendable[deviceID] = list
        if send.isTemporary { try? FileManager.default.removeItem(at: send.url) }
    }

    // MARK: - Rows

    func clearFinished() {
        rows.removeAll { !$0.isActive && $0.status?.isFinal != false }
    }

    private func upsertRow(_ row: Row) {
        if let index = rows.firstIndex(where: { $0.id == row.id }) {
            rows[index] = row
        } else {
            rows.insert(row, at: 0)
            if rows.count > 20 { rows.removeLast(rows.count - 20) }
        }
    }

    private func markRow(_ id: UUID, _ body: (inout Row) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        body(&rows[index])
    }

    private func sendStatus(_ status: TransferStatus, for id: UUID, connectionID: UUID) {
        guard let handle = connections[connectionID] else { return }
        Task {
            try? await handle.send(.sharing(.transferStatus(transferID: id, status: status)))
        }
    }

    // MARK: - Files

    static var downloadsFolder: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("Pixel Hand", isDirectory: true)
    }

    private static var partialsFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Pixel Hand/Transfers", isDirectory: true)
    }

    private static func partialURL(for id: UUID) -> URL {
        partialsFolder.appendingPathComponent(TransferResume.partialFileName(for: id))
    }

    private func deletePartial(_ id: UUID) {
        try? FileManager.default.removeItem(at: Self.partialURL(for: id))
    }

    private func cleanOldPartials() {
        let folder = Self.partialsFolder
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names {
            let url = folder.appendingPathComponent(name)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(date) > TransferResume.maxPartialAge {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func existingNames() throws -> Set<String> {
        try FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
        return Set((try? FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path)) ?? [])
    }

    private static func move(_ partial: URL, named name: String) throws -> URL {
        let destination = downloadsFolder.appendingPathComponent(TransferFileName.unique(name, existing: try existingNames()))
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    private static func store(_ data: Data, named name: String) throws -> URL {
        let destination = downloadsFolder.appendingPathComponent(TransferFileName.unique(name, existing: try existingNames()))
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func fileSize(_ url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        return size
    }

    private static func freeBytes(at url: URL) -> UInt64? {
        #if os(macOS)
        let probe = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        guard let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return UInt64(max(0, capacity))
        #else
        return nil // the Linux type check
        #endif
    }

    /// Streams the file through SHA-256 off the main actor.
    nonisolated static func sha256(of url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil
                guard let chunk, !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().hexString
        }.value
    }
}

extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
