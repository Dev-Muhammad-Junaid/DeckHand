//
//  TransferCenter.swift
//  DeckHandiOS – Transfer
//
//  S1/S2: the device's half of transfers. Rules in Core (`TransferPolicy`,
//  `TransferManifest`, `TransferOutbox`, `TransferInbox`).
//
//  - Bytes go through Loom's transfer engine on the focused Mac's
//    connection (its own control stream and a data stream per transfer;
//    chunked, resumable, SHA-256 checked). Never the JSON control stream.
//  - Sending: items wait in the outbox (App Group, so the Share extension
//    can add to it) until their Mac connects; then they are offered with
//    their outbox id as the Loom id, so after a drop the Mac resumes from
//    its partial file. The Mac's `sharing.transferStatus` says where it
//    landed or why it was refused.
//  - Receiving: only from a paired Mac, only with Pixel Hand Pro (the free
//    tier answers `needsPro`). Small items land in the Inbox at once;
//    large ones ask first (`prompt`).
//  - The session model attaches the focused Mac once access is granted
//    and detaches it when the session ends (`ControlSessionModel+Transfer`).
//
//  No SwiftUI or UIKit here: Linux type-checks it.
//

import CryptoKit
import Foundation
import Loom
import LoomKit
import Observation

@MainActor
@Observable
final class TransferCenter {
    static let shared = TransferCenter()

    /// One transfer as the Send sheet and the Inbox show it.
    struct Activity: Identifiable, Equatable {
        enum Direction: Equatable { case incoming, outgoing }
        let id: UUID
        let direction: Direction
        let kind: TransferKind
        let name: String
        let macName: String
        var meter: TransferProgressMeter
        var status: TransferStatus?
        var isActive: Bool

        var beam: TransferBeamPhase {
            TransferBeamPhase.phase(status: status, fraction: isActive || meter.bytes > 0 ? meter.fraction : nil)
        }

        var caption: String {
            switch status {
            case .awaitingApproval?:
                return direction == .outgoing ? "Waiting for \(macName) to accept" : "Waiting for you"
            case let .refused(reason)?:
                return direction == .outgoing ? TransferCopy.refused(reason, receiver: macName) : "Not taken"
            case let .saved(landing)?:
                return direction == .outgoing ? TransferCopy.saved(landing, receiver: macName) : "In your Inbox"
            case let .failed(reason)?:
                return TransferCopy.failed(reason, receiver: macName)
            case nil:
                return isActive ? meter.caption : TransferCopy.waiting(for: macName)
            }
        }
    }

    /// An incoming item waiting for Accept / Decline.
    struct Prompt: Identifiable, Equatable {
        let id: UUID
        let message: String
        let macDeviceID: UUID
        let canAlwaysAccept: Bool
    }

    private(set) var outbox: TransferOutbox
    private(set) var inbox: TransferInbox
    private(set) var activities: [UUID: Activity] = [:]
    private(set) var prompts: [Prompt] = []
    /// The focused Mac, while its session has access.
    private(set) var connectedMac: (deviceID: UUID, name: String)?
    /// A line for a passing notice ("Studio is locked…").
    var notice: String?

    @ObservationIgnored private var link: Link?
    @ObservationIgnored private var outgoing: [UUID: LoomOutgoingTransfer] = [:]
    @ObservationIgnored private var incoming: [UUID: (transfer: LoomIncomingTransfer, manifest: TransferManifest)] = [:]
    @ObservationIgnored private var promptDecisions: [UUID: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    private struct Link {
        let handle: LoomConnectionHandle
        let deviceID: UUID
        let name: String
        let isPaired: @MainActor () -> Bool
    }

    private static let alwaysKey = "transfer.alwaysAcceptFrom"
    private static let inboxFolderName = "Pixel Hand Inbox"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        outbox = TransferOutbox(storage: try? Data(contentsOf: TransferSharedContainer.outboxFile))
        inbox = TransferInbox(storage: try? Data(contentsOf: Self.inboxFile))
        // Anything that was moving when the app last stopped waits again.
        outbox.connectionEnded()
        for id in outbox.prune(now: Date()) { deleteOutboxFiles(id) }
        saveOutbox()
    }

    // MARK: - Session

    /// The session model hands over the focused Mac once access is
    /// granted. Runs until the task is cancelled (the session ended).
    func run(connection: LoomConnectionHandle, macName: String, isPaired: @escaping @MainActor () -> Bool) async {
        let link = Link(handle: connection, deviceID: connection.peer.deviceID, name: macName, isPaired: isPaired)
        self.link = link
        connectedMac = (link.deviceID, macName)
        publishPairedMacs()
        drain()
        // The Mac confirms pairing just after access; drain once it has.
        if !isPaired() {
            Task { [weak self] in
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.link?.handle.id == connection.id else { return }
                    if isPaired() {
                        self.drain()
                        return
                    }
                }
            }
        }
        for await transfer in connection.incomingTransfers {
            if Task.isCancelled { break }
            await received(transfer, link: link)
        }
        detach(connectionID: connection.id)
    }

    /// The session ended: interrupted sends wait for the next connection.
    func detach(connectionID: UUID) {
        guard link?.handle.id == connectionID else { return }
        link = nil
        connectedMac = nil
        outgoing.removeAll()
        outbox.connectionEnded()
        saveOutbox()
        for (id, _) in incoming {
            finishPrompt(id, accepted: false)
            update(id) { $0.isActive = false; $0.status = .failed(reason: .interrupted) }
        }
        incoming.removeAll()
        for id in activities.keys where activities[id]?.isActive == true {
            update(id) { $0.isActive = false }
        }
    }

    /// The app became active or the Send sheet opened: take in what the
    /// Share extension dropped and send what can go now.
    func refresh() {
        let dropped = TransferSharedContainer.collectDrops()
        for item in dropped where !outbox.add(item) {
            deleteOutboxFiles(item.id)
        }
        if !dropped.isEmpty { saveOutbox() }
        publishPairedMacs()
        drain()
    }

    // MARK: - Sending

    /// Queues a file (copied into the outbox) for `deviceID` and sends it
    /// at once if that Mac is connected. Returns the item's id.
    @discardableResult
    func send(fileAt source: URL, kind: TransferKind, contentType: String?, to deviceID: UUID?, macName: String?, moveFile: Bool = false) -> UUID? {
        guard !outbox.isFull, let size = Self.fileSize(source), TransferPolicy.canSend(kind: kind, byteCount: size) else {
            notice = outbox.isFull ? "Too many items are waiting. Send them first." : TransferCopy.refused(.tooLarge, receiver: macName ?? "your Mac")
            return nil
        }
        let item = TransferOutboxItem(kind: kind, fileName: source.lastPathComponent, byteCount: size, contentType: contentType, targetDeviceID: deviceID, targetName: macName, createdAt: Date())
        let destination = TransferSharedContainer.outboxFile(for: item)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if moveFile {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            DeckHandLog.connection.error("Transfer: couldn't queue a file: \(error.localizedDescription, privacy: .public)")
            deleteOutboxFiles(item.id)
            return nil
        }
        return enqueue(item)
    }

    /// Queues text or a link (a link when the whole text is one web address).
    @discardableResult
    func send(text: String, to deviceID: UUID?, macName: String?) -> UUID? {
        let data = Data(text.utf8)
        let kind: TransferKind = TransferInlineText.webLink(text) != nil ? .link : .text
        guard !outbox.isFull, TransferPolicy.canSend(kind: kind, byteCount: UInt64(data.count)) else { return nil }
        let item = TransferOutboxItem(kind: kind, fileName: TransferInlineText.fileName(for: text, kind: kind), byteCount: UInt64(data.count), contentType: "public.utf8-plain-text", targetDeviceID: deviceID, targetName: macName, createdAt: Date())
        let destination = TransferSharedContainer.outboxFile(for: item)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch {
            return nil
        }
        return enqueue(item)
    }

    private func enqueue(_ item: TransferOutboxItem) -> UUID? {
        guard outbox.add(item) else {
            deleteOutboxFiles(item.id)
            return nil
        }
        saveOutbox()
        activities[item.id] = Activity(id: item.id, direction: .outgoing, kind: item.kind, name: item.fileName, macName: item.targetName ?? "your Mac", meter: TransferProgressMeter(totalBytes: item.byteCount), status: nil, isActive: false)
        drain()
        return item.id
    }

    /// Offers everything waiting for the connected Mac.
    private func drain() {
        guard let link, link.isPaired() else { return }
        // Sharing is Pro: without it, items wait (the Send button is locked).
        guard SubscriptionStore.shared.entitlement.allows(.sharing) else { return }
        for item in outbox.ready(for: link.deviceID) {
            outbox.markSending(item.id, to: link.deviceID, name: link.name)
            Task { await offer(item.id, link: link) }
        }
        saveOutbox()
    }

    private func offer(_ id: UUID, link: Link) async {
        guard var item = outbox.items.first(where: { $0.id == id }) else { return }
        let file = TransferSharedContainer.outboxFile(for: item)
        if item.sha256 == nil, let hash = await Self.sha256(of: file) {
            outbox.setHash(hash, for: id)
            item.sha256 = hash
            saveOutbox()
        }
        let manifest = item.manifest
        let offer = LoomTransferOffer(id: id, logicalName: manifest.name, byteLength: manifest.byteCount, contentType: manifest.contentType, sha256Hex: item.sha256, metadata: manifest.metadata)
        let previous = activities[id]
        activities[id] = Activity(id: id, direction: .outgoing, kind: item.kind, name: item.fileName, macName: link.name, meter: previous?.meter ?? TransferProgressMeter(totalBytes: item.byteCount), status: nil, isActive: true)
        do {
            let source = try LoomFileTransferSource(url: file)
            let transfer = try await link.handle.transferEngine.offerTransfer(offer, source: source)
            outgoing[id] = transfer
            for await event in transfer.makeProgressObserver() {
                outgoingProgress(event, id: id)
            }
        } catch {
            DeckHandLog.connection.error("Transfer: offer failed: \(error.localizedDescription, privacy: .public)")
            outbox.markInterrupted(id)
            saveOutbox()
            update(id) { $0.isActive = false }
        }
    }

    private func outgoingProgress(_ event: LoomTransferProgress, id: UUID) {
        update(id) { $0.meter.update(bytes: event.bytesTransferred, at: ProcessInfo.processInfo.systemUptime) }
        switch event.state {
        case .completed:
            // Loom checked the hash; the Mac's status says where it went.
            outgoing.removeValue(forKey: id)
            finishOutboxItem(id)
            update(id) { $0.isActive = false }
        case .declined, .cancelled:
            outgoing.removeValue(forKey: id)
            finishOutboxItem(id)
            update(id) {
                $0.isActive = false
                if $0.status == nil || $0.status == .awaitingApproval { $0.status = .refused(reason: .declined) }
            }
        case .failed:
            outgoing.removeValue(forKey: id)
            let kept = outbox.markInterrupted(id)
            saveOutbox()
            if !kept { deleteOutboxFiles(id) }
            update(id) {
                $0.isActive = false
                if $0.status == nil { $0.status = kept ? nil : .failed(reason: .interrupted) }
            }
        default:
            break
        }
    }

    /// Cancel on an outgoing or waiting item: stops it on both ends and
    /// forgets it (the Mac deletes its partial file).
    func cancel(_ id: UUID) {
        if let transfer = outgoing.removeValue(forKey: id) {
            Task { await transfer.cancel() }
        }
        if let entry = incoming.removeValue(forKey: id) {
            sendStatus(.failed(reason: .cancelled), for: id)
            Task { try? await entry.transfer.decline() }
            deletePartial(id)
        }
        finishPrompt(id, accepted: false)
        finishOutboxItem(id)
        update(id) { $0.isActive = false; $0.status = .failed(reason: .cancelled) }
    }

    /// `sharing.transferStatus` from the Mac about something this device sent.
    func receivedStatus(_ status: TransferStatus, for id: UUID) {
        guard let activity = activities[id], activity.direction == .outgoing else { return }
        update(id) { $0.status = status }
        switch status {
        case let .refused(reason):
            finishOutboxItem(id)
            notice = TransferCopy.refused(reason, receiver: activity.macName)
        case .failed(reason: .integrity), .failed(reason: .writeFailed), .failed(reason: .cancelled):
            finishOutboxItem(id)
        case .saved, .failed(reason: .interrupted), .awaitingApproval:
            break
        }
    }

    private func finishOutboxItem(_ id: UUID) {
        guard outbox.items.contains(where: { $0.id == id }) else { return }
        outbox.remove(id)
        saveOutbox()
        deleteOutboxFiles(id)
    }

    // MARK: - Receiving

    private func received(_ transfer: LoomIncomingTransfer, link: Link) async {
        let offer = transfer.offer
        let manifest: TransferManifest
        switch TransferManifest.read(logicalName: offer.logicalName, byteLength: offer.byteLength, contentType: offer.contentType, metadata: offer.metadata) {
        case let .success(read):
            manifest = read
        case let .failure(error):
            refuse(transfer, reason: error == .tooLarge ? .tooLarge : .unsupported)
            return
        }
        let context = TransferReceiveContext(
            senderIsPaired: link.isPaired(),
            lockState: .unlocked,
            hasPro: SubscriptionStore.shared.entitlement.allows(.sharing),
            alwaysAcceptFromSender: alwaysAccepted.contains(link.deviceID.uuidString),
            freeBytes: Self.freeBytes()
        )
        var decision = TransferPolicy.decide(manifest, context: context)
        // A resume of something already accepted doesn't ask again.
        if decision == .ask, (Self.fileSize(Self.partialURL(for: offer.id)) ?? 0) > 0 {
            decision = .accept
        }
        switch decision {
        case let .refuse(reason):
            refuse(transfer, reason: reason)
            if reason == .needsPro {
                notice = "\(link.name) tried to send you something. Receiving needs Pixel Hand Pro."
            }
        case .accept:
            await accept(transfer, manifest: manifest, link: link)
        case .ask:
            incoming[offer.id] = (transfer, manifest)
            sendStatus(.awaitingApproval, for: offer.id)
            let accepted = await ask(Prompt(
                id: offer.id,
                message: TransferCopy.prompt(kind: manifest.kind, name: manifest.name, byteCount: manifest.byteCount, sender: link.name),
                macDeviceID: link.deviceID,
                canAlwaysAccept: manifest.byteCount < TransferPolicy.alwaysAskBytes
            ))
            guard incoming[offer.id] != nil else { return }
            if accepted {
                await accept(transfer, manifest: manifest, link: link)
            } else {
                refuse(transfer, reason: .declined)
            }
        }
    }

    private func accept(_ transfer: LoomIncomingTransfer, manifest: TransferManifest, link: Link) async {
        let id = transfer.offer.id
        incoming[id] = (transfer, manifest)
        let partial = Self.partialURL(for: id)
        let resumeAt = TransferResume.offset(partialBytes: Self.fileSize(partial), totalBytes: manifest.byteCount)
        activities[id] = Activity(id: id, direction: .incoming, kind: manifest.kind, name: manifest.name, macName: link.name, meter: TransferProgressMeter(totalBytes: manifest.byteCount, startingAt: resumeAt), status: nil, isActive: true)
        do {
            try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
            if resumeAt == 0 { try? FileManager.default.removeItem(at: partial) }
            let sink = try LoomFileTransferSink(url: partial)
            let progress = transfer.makeProgressObserver()
            let macName = link.name
            Task { [weak self] in
                for await event in progress {
                    self?.incomingProgress(event, id: id, macName: macName)
                }
            }
            try await transfer.accept(using: sink, resumeOffset: resumeAt)
        } catch {
            incoming.removeValue(forKey: id)
            sendStatus(.failed(reason: .writeFailed), for: id)
            update(id) { $0.isActive = false; $0.status = .failed(reason: .writeFailed) }
        }
    }

    private func incomingProgress(_ event: LoomTransferProgress, id: UUID, macName: String) {
        update(id) { $0.meter.update(bytes: event.bytesTransferred, at: ProcessInfo.processInfo.systemUptime) }
        switch event.state {
        case .completed:
            guard let entry = incoming.removeValue(forKey: id) else { return }
            land(id: id, manifest: entry.manifest, macName: macName)
        case .failed:
            guard let entry = incoming.removeValue(forKey: id) else { return }
            let complete = event.bytesTransferred >= entry.manifest.byteCount
            if complete { deletePartial(id) }
            let reason: TransferFailure = complete ? .integrity : .interrupted
            sendStatus(.failed(reason: reason), for: id)
            update(id) { $0.isActive = false; $0.status = .failed(reason: reason) }
        case .cancelled, .declined:
            guard incoming.removeValue(forKey: id) != nil else { return }
            deletePartial(id)
            update(id) { $0.isActive = false; if $0.status == nil { $0.status = .failed(reason: .cancelled) } }
        default:
            break
        }
    }

    /// Moves a finished item into the Inbox and tells the Mac.
    private func land(id: UUID, manifest: TransferManifest, macName: String) {
        let partial = Self.partialURL(for: id)
        do {
            try FileManager.default.createDirectory(at: Self.inboxFolder, withIntermediateDirectories: true)
            var text: String?
            var name = manifest.name
            if manifest.kind.isInline {
                guard let clean = TransferInlineText.text(from: try Data(contentsOf: partial)) else { throw CocoaError(.fileReadCorruptFile) }
                text = clean
                name = TransferInlineText.fileName(for: clean, kind: manifest.kind)
            }
            let existing = inbox.fileNames.union(Set((try? FileManager.default.contentsOfDirectory(atPath: Self.inboxFolder.path)) ?? []))
            let fileName = TransferFileName.unique(name, existing: existing)
            try FileManager.default.moveItem(at: partial, to: Self.inboxFolder.appendingPathComponent(fileName))
            let item = TransferInboxItem(id: id, kind: manifest.kind, fileName: fileName, byteCount: manifest.byteCount, contentType: manifest.contentType, senderName: macName, receivedAt: Date(), text: text)
            for dropped in inbox.add(item) {
                try? FileManager.default.removeItem(at: Self.inboxFolder.appendingPathComponent(dropped.fileName))
            }
            saveInbox()
            sendStatus(.saved(landing: .inbox), for: id)
            update(id) { $0.isActive = false; $0.status = .saved(landing: .inbox) }
        } catch {
            deletePartial(id)
            sendStatus(.failed(reason: .writeFailed), for: id)
            update(id) { $0.isActive = false; $0.status = .failed(reason: .writeFailed) }
        }
    }

    private func refuse(_ transfer: LoomIncomingTransfer, reason: TransferRefusal) {
        let id = transfer.offer.id
        incoming.removeValue(forKey: id)
        finishPrompt(id, accepted: false)
        sendStatus(.refused(reason: reason), for: id)
        Task { try? await transfer.decline() }
        update(id) { $0.isActive = false; $0.status = .refused(reason: reason) }
    }

    // MARK: - Prompts

    private func ask(_ prompt: Prompt) async -> Bool {
        prompts.append(prompt)
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: TransferPolicy.promptTimeout)
            self?.finishPrompt(prompt.id, accepted: false)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            promptDecisions[prompt.id] = continuation
        }
    }

    func answer(_ id: UUID, accept: Bool, always: Bool = false) {
        if always, let prompt = prompts.first(where: { $0.id == id }) {
            var set = alwaysAccepted
            set.insert(prompt.macDeviceID.uuidString)
            defaults.set(Array(set), forKey: Self.alwaysKey)
        }
        finishPrompt(id, accepted: accept)
    }

    private func finishPrompt(_ id: UUID, accepted: Bool) {
        prompts.removeAll { $0.id == id }
        promptDecisions.removeValue(forKey: id)?.resume(returning: accepted)
    }

    private var alwaysAccepted: Set<String> {
        Set(defaults.stringArray(forKey: Self.alwaysKey) ?? [])
    }

    // MARK: - Inbox

    func inboxURL(for item: TransferInboxItem) -> URL {
        Self.inboxFolder.appendingPathComponent(item.fileName)
    }

    func markSeen(_ id: UUID) {
        inbox.markSeen(id)
        saveInbox()
    }

    func markAllSeen() {
        guard inbox.unseenCount > 0 else { return }
        inbox.markAllSeen()
        saveInbox()
    }

    func deleteInboxItem(_ id: UUID) {
        guard let item = inbox.remove(id) else { return }
        try? FileManager.default.removeItem(at: inboxURL(for: item))
        saveInbox()
    }

    /// Finished rows go; waiting and moving ones stay.
    func clearFinished() {
        let waiting = Set(outbox.items.map(\.id))
        activities = activities.filter { $0.value.isActive || waiting.contains($0.key) }
    }

    // MARK: - Storage

    private func saveOutbox() {
        try? FileManager.default.createDirectory(at: TransferSharedContainer.root, withIntermediateDirectories: true)
        try? outbox.encoded().write(to: TransferSharedContainer.outboxFile, options: .atomic)
    }

    private func saveInbox() {
        try? FileManager.default.createDirectory(at: Self.inboxFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? inbox.encoded().write(to: Self.inboxFile, options: .atomic)
    }

    private func deleteOutboxFiles(_ id: UUID) {
        try? FileManager.default.removeItem(at: TransferSharedContainer.outboxFolder.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    private func deletePartial(_ id: UUID) {
        try? FileManager.default.removeItem(at: Self.partialURL(for: id))
    }

    private func update(_ id: UUID, _ body: (inout Activity) -> Void) {
        guard var activity = activities[id] else { return }
        body(&activity)
        activities[id] = activity
    }

    private func sendStatus(_ status: TransferStatus, for id: UUID) {
        guard let handle = link?.handle else { return }
        Task { try? await handle.send(.sharing(.transferStatus(transferID: id, status: status))) }
    }

    /// The paired Macs, for the Share extension's picker.
    private func publishPairedMacs() {
        TransferSharedContainer.setSharingAllowed(SubscriptionStore.shared.entitlement.allows(.sharing))
        let macs = PairedMacsStore.shared.macs.filter { $0.kind == .mac }.map { TransferMacEntry(deviceID: $0.deviceID, name: $0.name) }
        TransferSharedContainer.writePairedMacs(macs)
    }

    /// Documents/Pixel Hand Inbox: Files shows it ("On My iPhone ›
    /// Pixel Hand") with `UIFileSharingEnabled` and
    /// `LSSupportsOpeningDocumentsInPlace`.
    static var inboxFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(inboxFolderName, isDirectory: true)
    }

    private static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Transfers", isDirectory: true)
    }

    private static var inboxFile: URL { supportFolder.appendingPathComponent("inbox.json") }

    private static func partialURL(for id: UUID) -> URL {
        supportFolder.appendingPathComponent("Partial", isDirectory: true).appendingPathComponent(TransferResume.partialFileName(for: id))
    }

    static func fileSize(_ url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        return size
    }

    private static func freeBytes() -> UInt64? {
        #if os(iOS)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return UInt64(max(0, capacity))
        #else
        return nil
        #endif
    }

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
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
