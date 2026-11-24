//
//  PixelHandAppGroup.swift
//  DeckHandiOS + DeckHandWidgets (compiled into both)
//
//  The App Group container the app and its widget extension share:
//
//  - `widget-deck.json`: the `WidgetDeckSnapshot` the app writes (keys to
//    draw, every key for the Shortcuts picker, recent Macs, Pro state);
//  - `pending-commands.json`: the `PendingCommandQueue` of commands an
//    intent accepted while no Mac was connected.
//
//  Files, not `UserDefaults(suiteName:)`, so writes are atomic and a
//  damaged file reads as empty (`WidgetDeckSnapshot.decode`). Without the
//  App Group entitlement (`containerURL` is `nil`) everything degrades to
//  an empty snapshot and an in-memory queue in the app process.
//

import Foundation
import PixelHandCore

enum PixelHandAppGroup {
    /// Must match `com.apple.security.application-groups` in both
    /// targets' entitlements.
    static let identifier = "group.com.widgetsflow.pixelhand"

    /// WidgetKit kinds, so the app can reload exactly these.
    enum WidgetKind {
        static let deck = "PixelHandDeckWidget"
        static let accessory = "PixelHandAccessoryWidget"
        static let keyControl = "PixelHandKeyControl"
        static let missionControl = "PixelHandMissionControlControl"
        static let trackpadControl = "PixelHandTrackpadControl"
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static func url(_ name: String) -> URL? {
        containerURL?.appendingPathComponent(name)
    }

    // MARK: - Snapshot

    static func readSnapshot() -> WidgetDeckSnapshot {
        WidgetDeckSnapshot.decode(url(WidgetDeckSnapshot.fileName).flatMap { try? Data(contentsOf: $0) })
    }

    static func writeSnapshot(_ snapshot: WidgetDeckSnapshot) {
        guard let fileURL = url(WidgetDeckSnapshot.fileName),
              let data = try? WidgetDeckSnapshot.encode(snapshot)
        else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Pending commands

    /// The queue when there is no container (no entitlement yet): commands
    /// still reach the app if they were accepted in its process.
    nonisolated(unsafe) private static var memoryQueue = PendingCommandQueue()
    private static let lock = NSLock()

    static func enqueue(_ command: PendingCommand) {
        lock.withLock {
            var queue = loadQueue()
            queue.enqueue(command, now: Date())
            saveQueue(queue)
        }
    }

    /// Removes and returns the commands ready to run on `macID`.
    static func drainPending(forMac macID: String?) -> [PendingCommand] {
        lock.withLock {
            var queue = loadQueue()
            let ready = queue.drain(forMac: macID, now: Date())
            saveQueue(queue)
            return ready
        }
    }

    private static func loadQueue() -> PendingCommandQueue {
        guard let fileURL = url(PendingCommandQueue.fileName) else { return memoryQueue }
        return PendingCommandQueue.decode(try? Data(contentsOf: fileURL))
    }

    private static func saveQueue(_ queue: PendingCommandQueue) {
        guard let fileURL = url(PendingCommandQueue.fileName) else {
            memoryQueue = queue
            return
        }
        if queue.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else if let data = try? PendingCommandQueue.encode(queue) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
