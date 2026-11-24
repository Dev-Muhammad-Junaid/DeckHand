//
//  MacMemory.swift
//  PixelHandCore – Multi-Mac
//
//  What this device remembers about each Mac it has used (UX-030, backlog
//  M1): when it was first and last used (the first fixes its place in the
//  list, so ⌘1–4 keep naming the same Macs), the surface and deck page that
//  were showing, the mirror's settings, and the last glance. Switching
//  saves the Mac being left and restores the one being entered.
//
//  Stored per device as JSON (`UserDefaults`, `DeckHandSettings`' Multi-Mac
//  key). Bounded: past `capacity` the least recently used Mac is dropped.
//

import Foundation

/// The mirror's settings for one Mac. Kept as plain values so Core doesn't
/// need the app's setting enums; the app maps them back.
public struct MacMirrorMemory: Codable, Equatable, Sendable {
    /// `MirrorSharpness.rawValue` ("auto", "saver", "sharp").
    public var sharpness: String
    /// `MirrorFrameRate.rawValue` (15, 20, 30).
    public var frameRate: Int
    /// The classic layout's floating mirror frame, encoded by the app.
    public var layout: Data?

    public init(sharpness: String, frameRate: Int, layout: Data? = nil) {
        self.sharpness = sharpness
        self.frameRate = frameRate
        self.layout = layout
    }
}

/// One Mac, as this device remembers it.
public struct MacMemory: Codable, Equatable, Sendable, Identifiable {
    public let deviceID: UUID
    public var name: String
    public let firstUsedAt: Date
    public var lastUsedAt: Date
    /// The shell surface that was showing (`ControlSurface.rawValue`).
    public var surface: String?
    /// The deck page that was showing.
    public var deckPageID: String?
    public var mirror: MacMirrorMemory?
    public var glance: MacGlance?

    public var id: UUID { deviceID }

    public init(
        deviceID: UUID,
        name: String,
        firstUsedAt: Date,
        lastUsedAt: Date,
        surface: String? = nil,
        deckPageID: String? = nil,
        mirror: MacMirrorMemory? = nil,
        glance: MacGlance? = nil
    ) {
        self.deviceID = deviceID
        self.name = name
        self.firstUsedAt = firstUsedAt
        self.lastUsedAt = lastUsedAt
        self.surface = surface
        self.deckPageID = deckPageID
        self.mirror = mirror
        self.glance = glance
    }
}

/// Every Mac this device remembers, and the one used last.
public struct MacMemoryBook: Codable, Equatable, Sendable {
    /// More Macs than anyone switches between; keeps storage small.
    public static let capacity = 16
    /// Names longer than this are cut (a hostile or broken advertisement).
    public static let maximumNameLength = 64

    /// Oldest first use first.
    public private(set) var macs: [MacMemory]
    /// The Mac used last, for reconnecting at launch.
    public private(set) var lastActiveDeviceID: UUID?

    public init(macs: [MacMemory] = [], lastActiveDeviceID: UUID? = nil) {
        self.macs = macs.sorted { $0.firstUsedAt < $1.firstUsedAt }
        self.lastActiveDeviceID = lastActiveDeviceID
    }

    /// Decodes stored JSON; anything unreadable starts an empty book.
    public init(storage: Data?) {
        guard let storage, let book = try? JSONDecoder().decode(MacMemoryBook.self, from: storage) else {
            self.init()
            return
        }
        self.init(macs: Array(book.macs.prefix(Self.capacity * 2)), lastActiveDeviceID: book.lastActiveDeviceID)
        trim()
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public func memory(for deviceID: UUID) -> MacMemory? {
        macs.first { $0.deviceID == deviceID }
    }

    /// A Mac became the focused one: remembered (first use fixed), its
    /// name refreshed, and it becomes the Mac used last.
    public mutating func activated(deviceID: UUID, name: String, at now: Date) {
        let cleanName = Self.clean(name)
        if let index = macs.firstIndex(where: { $0.deviceID == deviceID }) {
            macs[index].lastUsedAt = now
            if !cleanName.isEmpty { macs[index].name = cleanName }
        } else {
            macs.append(MacMemory(deviceID: deviceID, name: cleanName, firstUsedAt: now, lastUsedAt: now))
        }
        lastActiveDeviceID = deviceID
        trim()
    }

    /// Changes a remembered Mac. Unknown Macs are ignored: only a Mac that
    /// was activated has state worth keeping.
    public mutating func update(_ deviceID: UUID, _ change: (inout MacMemory) -> Void) {
        guard let index = macs.firstIndex(where: { $0.deviceID == deviceID }) else { return }
        change(&macs[index])
    }

    /// Forgets a Mac (Forget in My Macs or Settings).
    public mutating func forget(_ deviceID: UUID) {
        macs.removeAll { $0.deviceID == deviceID }
        if lastActiveDeviceID == deviceID { lastActiveDeviceID = nil }
    }

    /// The person disconnected on purpose: don't reconnect at next launch.
    public mutating func clearLastActive() {
        lastActiveDeviceID = nil
    }

    private mutating func trim() {
        macs.sort { $0.firstUsedAt < $1.firstUsedAt }
        while macs.count > Self.capacity {
            // Drop the least recently used Mac, never the one used last.
            let candidates = macs.enumerated().filter { $0.element.deviceID != lastActiveDeviceID }
            guard let oldest = candidates.min(by: { $0.element.lastUsedAt < $1.element.lastUsedAt }) else { break }
            macs.remove(at: oldest.offset)
        }
    }

    static func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return String(trimmed.prefix(maximumNameLength))
    }
}
