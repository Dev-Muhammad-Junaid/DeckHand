//
//  MenuReadBudget.swift
//  PixelHandCore
//
//  Limits for reading an app's menu bar through Accessibility (S9,
//  `MenuShortcutDiscovery` on the Mac). An app that is busy or hung answers
//  each AX call only after the system's messaging timeout (about 6 s by
//  default), and some apps have menus of thousands of items (recent files,
//  bookmarks, windows), so an unbounded walk could stall for minutes. The
//  Mac sets a short per-element messaging timeout and walks within this
//  budget; whatever was read before a limit is still used.
//

import Foundation

public struct MenuReadLimits: Sendable, Equatable {
    /// `AXUIElementSetMessagingTimeout` for the app and every element read,
    /// in seconds.
    public var messagingTimeout: Float
    /// Deepest submenu level walked (the menu bar's titles are level 0).
    public var maxDepth: Int
    /// Most AX elements visited in one read.
    public var maxNodes: Int
    /// Most shortcut-bearing items collected.
    public var maxItems: Int
    /// Most children read from one menu; the rest are skipped.
    public var maxChildrenPerMenu: Int
    /// Wall-clock limit for the whole read, in seconds.
    public var timeLimit: TimeInterval
    /// After this many timed-out AX calls in a row the app is treated as
    /// not answering and the read stops.
    public var maxConsecutiveTimeouts: Int

    public init(
        messagingTimeout: Float = 0.25,
        maxDepth: Int = 5,
        maxNodes: Int = 3_000,
        maxItems: Int = 400,
        maxChildrenPerMenu: Int = 250,
        timeLimit: TimeInterval = 4,
        maxConsecutiveTimeouts: Int = 3
    ) {
        self.messagingTimeout = messagingTimeout
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
        self.maxItems = maxItems
        self.maxChildrenPerMenu = maxChildrenPerMenu
        self.timeLimit = timeLimit
        self.maxConsecutiveTimeouts = maxConsecutiveTimeouts
    }

    public static let standard = MenuReadLimits()
}

/// Why a read stopped early. Logged by the Mac.
public enum MenuReadStop: String, Sendable, Equatable {
    case nodeLimit
    case itemLimit
    case timeLimit
    case appNotAnswering
}

/// Counts one read against `MenuReadLimits`. Not thread-safe: one walk
/// owns one budget.
public struct MenuReadBudget: Sendable {
    public let limits: MenuReadLimits
    public private(set) var nodesVisited = 0
    public private(set) var itemsCollected = 0
    public private(set) var stopReason: MenuReadStop?
    /// Menus whose children were cut at `maxChildrenPerMenu`.
    public private(set) var truncatedMenus = 0
    private var consecutiveTimeouts = 0
    private let deadline: Date

    public init(limits: MenuReadLimits = .standard, start: Date = Date()) {
        self.limits = limits
        self.deadline = start.addingTimeInterval(limits.timeLimit)
    }

    public var isExhausted: Bool { stopReason != nil }

    /// Call before reading an element. `false` means stop the whole walk.
    public mutating func visitNode(now: Date = Date()) -> Bool {
        guard stopReason == nil else { return false }
        if now >= deadline {
            stopReason = .timeLimit
            return false
        }
        guard nodesVisited < limits.maxNodes else {
            stopReason = .nodeLimit
            return false
        }
        nodesVisited += 1
        return true
    }

    /// Whether to descend into an element at `depth`.
    public func mayDescend(toDepth depth: Int) -> Bool {
        stopReason == nil && depth <= limits.maxDepth
    }

    /// How many of a menu's `count` children to read.
    public mutating func childrenToRead(of count: Int) -> Int {
        if count > limits.maxChildrenPerMenu {
            truncatedMenus += 1
            return limits.maxChildrenPerMenu
        }
        return max(0, count)
    }

    /// Call for each item kept. `false` once the item limit is reached
    /// (that item is not kept).
    public mutating func addItem() -> Bool {
        guard stopReason == nil else { return false }
        guard itemsCollected < limits.maxItems else {
            stopReason = .itemLimit
            return false
        }
        itemsCollected += 1
        return true
    }

    /// Call after each AX read with whether it timed out
    /// (`kAXErrorCannotComplete`).
    public mutating func noteRead(timedOut: Bool) {
        guard timedOut else {
            consecutiveTimeouts = 0
            return
        }
        consecutiveTimeouts += 1
        if consecutiveTimeouts >= limits.maxConsecutiveTimeouts, stopReason == nil {
            stopReason = .appNotAnswering
        }
    }
}
