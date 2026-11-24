//
//  PendingCommandQueue.swift
//  PixelHandCore
//
//  Commands an intent accepted while no Mac was connected: Siri, a widget
//  button or a control opens the app, and the command waits here until a
//  session is live, then runs once. Stored in the App Group container, so a
//  command accepted in the widget extension's process reaches the app.
//
//  A command that waits too long is dropped, not run late: pressing "Lock
//  Screen" and having the Mac lock ten minutes later is worse than nothing.
//

import Foundation

public struct PendingCommand: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var command: RemoteCommand
    /// The Mac it was meant for (`RecentMac.id`), or `nil` for whichever
    /// connects.
    public var macID: String?
    public var queuedAt: Date

    public init(id: UUID = UUID(), command: RemoteCommand, macID: String? = nil, queuedAt: Date) {
        self.id = id
        self.command = command
        self.macID = macID
        self.queuedAt = queuedAt
    }
}

public struct PendingCommandQueue: Codable, Sendable, Equatable {
    /// How long a command waits for a connection.
    public static let lifetime: TimeInterval = 90
    /// At most this many wait; the oldest go first.
    public static let capacity = 8
    public static let fileName = "pending-commands.json"

    public private(set) var items: [PendingCommand]

    public init(items: [PendingCommand] = []) {
        self.items = items
    }

    /// Adds `command`, dropping expired ones and the oldest past capacity.
    /// Invalid commands are refused (returns `false`).
    @discardableResult
    public mutating func enqueue(_ command: PendingCommand, now: Date) -> Bool {
        guard command.command.validationIssue == nil else { return false }
        prune(now: now)
        items.append(command)
        if items.count > Self.capacity { items.removeFirst(items.count - Self.capacity) }
        return true
    }

    /// Removes and returns the commands to run now on the Mac `macID`, in
    /// the order they were queued. Expired commands are dropped. Commands
    /// meant for another Mac stay queued (until they expire).
    public mutating func drain(forMac macID: String?, now: Date) -> [PendingCommand] {
        prune(now: now)
        let ready = items.filter { $0.macID == nil || $0.macID == macID }
        items.removeAll { $0.macID == nil || $0.macID == macID }
        return ready
    }

    public mutating func prune(now: Date) {
        items.removeAll { now.timeIntervalSince($0.queuedAt) > Self.lifetime || $0.queuedAt > now.addingTimeInterval(5) }
    }

    public var isEmpty: Bool { items.isEmpty }

    // MARK: - Coding

    public static func encode(_ queue: PendingCommandQueue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(queue)
    }

    /// A missing or damaged file is an empty queue.
    public static func decode(_ data: Data?) -> PendingCommandQueue {
        guard let data, data.count <= 256 * 1024 else { return PendingCommandQueue() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(PendingCommandQueue.self, from: data)) ?? PendingCommandQueue()
    }
}
