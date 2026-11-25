//
//  MacDeviceListPlan.swift
//  PixelHandCore – Design
//
//  The Mac menu-bar panel's one Devices list (OR-08). Every iPhone or iPad
//  the Mac knows is one row with one state:
//
//  - asking: a connection waiting for Allow / Pair / Deny, amber;
//  - connected: a live session, with the live pixel;
//  - paired, not connected: trusted but away, dim.
//
//  A paired device that is connected shows once, as connected. "Pair a
//  device" sits under the list; Forget and Disconnect live in each row's
//  menu, never as a row of buttons. Plain values so the order, merging and
//  copy are tested here and the panel only draws them.
//

import Foundation

public enum MacDeviceListPlan {
    /// A row's state, in the order rows are listed.
    public enum State: Int, Sendable, Hashable, Comparable {
        /// Waiting for Allow / Pair / Deny. Amber.
        case asking
        /// A live session. The live pixel.
        case connected
        /// Paired, not connected now. Dim.
        case pairedAway

        public static func < (lhs: State, rhs: State) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// What a row's buttons and menu can do.
    public enum Action: String, Sendable, Hashable, CaseIterable {
        case deny, pair, allow, disconnect, forget

        /// The label: no trailing "…" on any button or menu item (OR-12).
        public var title: String {
            switch self {
            case .deny: "Deny"
            case .pair: "Pair"
            case .allow: "Allow"
            case .disconnect: "Disconnect"
            case .forget: "Forget"
            }
        }
    }

    /// A pending request.
    public struct Asking: Sendable, Hashable {
        public let connectionID: UUID
        public let name: String
        public let requestedAt: Date?

        public init(connectionID: UUID, name: String, requestedAt: Date? = nil) {
            self.connectionID = connectionID
            self.name = name
            self.requestedAt = requestedAt
        }
    }

    /// An allowed, live connection. `pairedKey` names its paired record
    /// (any stable string, such as the identity key ID) when it has one.
    public struct Live: Sendable, Hashable {
        public let connectionID: UUID
        public let name: String
        public let connectedAt: Date
        public let pairedKey: String?

        public init(connectionID: UUID, name: String, connectedAt: Date, pairedKey: String? = nil) {
            self.connectionID = connectionID
            self.name = name
            self.connectedAt = connectedAt
            self.pairedKey = pairedKey
        }
    }

    /// A paired device from the trust list.
    public struct Paired: Sendable, Hashable {
        public let key: String
        public let name: String
        public let lastSeenAt: Date

        public init(key: String, name: String, lastSeenAt: Date) {
            self.key = key
            self.name = name
            self.lastSeenAt = lastSeenAt
        }
    }

    /// The line under a row's name; the panel formats the dates.
    public enum Detail: Sendable, Hashable {
        /// "Wants to control this Mac · 2 min ago".
        case asking(since: Date?)
        /// "Connected · paired" or "Connected for this session".
        case connected(since: Date, isPaired: Bool)
        /// "Paired · not connected · last seen yesterday".
        case pairedAway(lastSeen: Date)
    }

    public struct Row: Sendable, Hashable, Identifiable {
        /// "ask-<connection>", "live-<connection>" or "paired-<key>":
        /// stable while the device keeps its state.
        public let id: String
        public let name: String
        public let state: State
        public let detail: Detail
        /// The connection, for asking and connected rows.
        public let connectionID: UUID?
        /// The paired record, for paired rows (connected or away).
        public let pairedKey: String?
        /// Labelled buttons on the row itself: only a request has them.
        public let buttons: [Action]
        /// The row's menu (and its right-click menu).
        public let menu: [Action]

        public var isPaired: Bool { pairedKey != nil }
    }

    /// One list: requests first, then live sessions newest first, then
    /// paired devices that are away, most recently seen first. A paired
    /// device that is connected appears once, as connected.
    public static func rows(asking: [Asking], live: [Live], paired: [Paired]) -> [Row] {
        var rows: [Row] = []

        let liveIDs = Set(live.map(\.connectionID))
        for request in asking where !liveIDs.contains(request.connectionID) {
            rows.append(Row(
                id: "ask-\(request.connectionID.uuidString)",
                name: request.name,
                state: .asking,
                detail: .asking(since: request.requestedAt),
                connectionID: request.connectionID,
                pairedKey: nil,
                buttons: [.deny, .pair, .allow],
                menu: []
            ))
        }

        let pairedKeys = Set(paired.map(\.key))
        for session in live.sorted(by: { $0.connectedAt > $1.connectedAt }) {
            // A key the trust list no longer holds (just forgotten) isn't paired.
            let key = session.pairedKey.flatMap { pairedKeys.contains($0) ? $0 : nil }
            rows.append(Row(
                id: "live-\(session.connectionID.uuidString)",
                name: session.name,
                state: .connected,
                detail: .connected(since: session.connectedAt, isPaired: key != nil),
                connectionID: session.connectionID,
                pairedKey: key,
                buttons: [],
                menu: key != nil ? [.disconnect, .forget] : [.pair, .disconnect]
            ))
        }

        let liveKeys = Set(live.compactMap(\.pairedKey))
        for device in paired.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }) where !liveKeys.contains(device.key) {
            rows.append(Row(
                id: "paired-\(device.key)",
                name: device.name,
                state: .pairedAway,
                detail: .pairedAway(lastSeen: device.lastSeenAt),
                connectionID: nil,
                pairedKey: device.key,
                buttons: [],
                menu: [.forget]
            ))
        }
        return rows
    }

    // MARK: Copy

    /// The row's second line. `relative` is the panel's "2 min ago" for a
    /// date (the app formats it; tests pass a fixed string).
    public static func detailText(_ detail: Detail, relative: (Date) -> String) -> String {
        switch detail {
        case let .asking(since):
            guard let since else { return "Wants to control this Mac" }
            return "Wants to control this Mac · \(relative(since))"
        case let .connected(_, isPaired):
            return isPaired ? "Connected · paired" : "Connected for this session"
        case let .pairedAway(lastSeen):
            return "Paired · not connected · last seen \(relative(lastSeen))"
        }
    }

    /// How often the panel redraws "last seen" (build 23, VQ-097).
    public static let seenRefreshInterval: TimeInterval = 30

    /// "just now", "1 min ago", "38 min ago", or nil from an hour on
    /// (the app then uses the system's relative date: "2 hours ago",
    /// "yesterday"). Minutes at the finest, so the panel's periodic
    /// redraw keeps it true: build 23 showed "38 seconds ago" and froze
    /// there while the panel stayed open (VQ-097).
    public static func recentSeen(_ date: Date, now: Date) -> String? {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed.isFinite else { return nil }
        if elapsed < 60 { return "just now" }
        let minutes = Int(elapsed / 60)
        return minutes < 60 ? "\(minutes) min ago" : nil
    }

    /// The short state word VoiceOver reads after the name.
    public static func spokenState(_ state: State) -> String {
        switch state {
        case .asking: "asking to connect"
        case .connected: "connected"
        case .pairedAway: "paired, not connected"
        }
    }

    /// The line under the list when nobody is connected or asking: none
    /// when a device is live or asking (the rows say it).
    public static func hint(rows: [Row], macName: String) -> String? {
        guard !rows.contains(where: { $0.state != .pairedAway }) else { return nil }
        if rows.isEmpty {
            return "Open Pixel Hand on your iPhone or iPad and choose \(macName). Paired devices connect without asking."
        }
        return "Open Pixel Hand on one of them and choose \(macName)."
    }

    /// The confirmation shown in the row before Forget runs.
    public static func forgetPrompt(name: String, isConnected: Bool) -> String {
        isConnected
            ? "Forget \(name)? It disconnects now and must be allowed or paired again."
            : "Forget \(name)? It must be allowed or paired again."
    }

    /// The button under the list.
    public static let pairButton = "Pair a device"
}
