//
//  MacClipboardSync.swift
//  DeckHandMac
//
//  S10: the Mac's half of clipboard text sync. Rules in Core's
//  `ClipboardPolicy`; re-implemented from Sill's documented behaviour.
//
//  - A remote turns sync on with `sharing.clipboardSync(enabled: true)`.
//    It then gets the Mac's clipboard text at once and on every change.
//  - macOS has no clipboard notification, so this reads
//    `NSPasteboard.general.changeCount` every
//    `ClipboardPolicy.macPollInterval` while at least one remote listens,
//    and only then reads the text.
//  - Nothing is sent while the Mac is locked: the change count isn't
//    taken, so the latest change goes out once it is unlocked.
//  - Items marked concealed or transient (password managers) and text
//    over the size cap are never sent.
//  - `sharing.setClipboard` writes the text, remembers the write so it
//    isn't sent back as a change, and with `paste` presses ⌘V.
//

import AppKit
import Foundation
import LoomKit

@MainActor
final class MacClipboardSync {
    static let shared = MacClipboardSync()

    private var subscribers: [UUID: LoomConnectionHandle] = [:]
    private var pollTask: Task<Void, Never>?
    private var lastChangeCount: Int?
    private var echo = ClipboardEcho()
    private var lastSkipLogAt: Date = .distantPast

    private init() {}

    // MARK: - Remote requests

    func setSync(_ enabled: Bool, for handle: LoomConnectionHandle, id: UUID) {
        if enabled {
            subscribers[id] = handle
            DeckHandLog.connection.info("Clipboard: a remote turned sync on (\(self.subscribers.count, privacy: .public) listening)")
            // The current text, so the remote can paste it straight away.
            if !MacLockMonitor.shared.state.isLocked, let text = shareableText() {
                send(text, to: [handle])
            }
            startPollingIfNeeded()
        } else {
            removeConnection(id: id)
        }
    }

    func setClipboard(_ text: String, paste: Bool, from id: UUID) {
        // The lock gate refuses this while locked; checked again here in
        // case the Mac locked between the gate and now.
        guard !MacLockMonitor.shared.state.isLocked else { return }
        guard ClipboardPolicy.isAcceptable(remoteText: text) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            DeckHandLog.connection.error("Clipboard: couldn't write \(text.utf8.count, privacy: .public) B from a remote")
            return
        }
        echo.wrote(changeCount: pasteboard.changeCount)
        lastChangeCount = pasteboard.changeCount
        DeckHandLog.connection.info("Clipboard: set \(text.utf8.count, privacy: .public) B from a remote\(paste ? " and pasted" : "", privacy: .public)")
        if paste {
            // Through the typing queue, so it lands after text typed before.
            TypingQueue.shared.shortcut(["cmd", "v"])
        }
    }

    func removeConnection(id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else { return }
        if subscribers.isEmpty {
            pollTask?.cancel()
            pollTask = nil
            lastChangeCount = nil
        }
    }

    // MARK: - Watching the pasteboard

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ClipboardPolicy.macPollInterval)
                self?.poll()
            }
        }
    }

    private func poll() {
        guard !subscribers.isEmpty else { return }
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        // Locked: leave the count untaken, so the change goes out at the
        // unlock rather than never.
        guard !MacLockMonitor.shared.state.isLocked else { return }
        lastChangeCount = count
        guard echo.shouldBroadcast(changeCount: count) else { return }
        guard let text = shareableText() else { return }
        send(text, to: Array(subscribers.values))
    }

    /// The pasteboard's text if policy lets it go, else `nil` (logged at
    /// most every 30 s).
    private func shareableText() -> String? {
        let pasteboard = NSPasteboard.general
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let text = pasteboard.string(forType: .string)
        guard ClipboardPolicy.shouldShare(text: text, types: types) else {
            if text != nil, Date().timeIntervalSince(lastSkipLogAt) > 30 {
                lastSkipLogAt = Date()
                DeckHandLog.connection.info("Clipboard: not shared (private item, or over \(ClipboardPolicy.maxTextBytes, privacy: .public) B)")
            }
            return nil
        }
        return text
    }

    private func send(_ text: String, to handles: [LoomConnectionHandle]) {
        for handle in handles {
            Task {
                do {
                    try await handle.send(.sharing(.macClipboard(text: text)))
                } catch {
                    DeckHandLog.connection.error("Clipboard: send failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
