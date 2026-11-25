//
//  TransferPanelPlan.swift
//  PixelHandCore – Transfer
//
//  The Mac panel's Transfers tab (OR-13). With five or six files moving,
//  transfer rows pushed everything else off the panel, so they live in
//  their own tab beside Devices:
//
//  - the tab shows only while a transfer is under way, an item is waiting
//    for Accept, or one finished in the last hour; its badge counts them;
//  - the Devices view shows one summary row ("3 files sending · 42 %")
//    that opens the tab;
//  - in the tab, transfers under way come first, then the finished ones,
//    newest first; finished ones drop out an hour after they end.
//

import Foundation

public enum TransferPanelPlan {
    /// How long a finished transfer stays listed.
    public static let finishedLifetime: TimeInterval = 60 * 60

    public enum Direction: Sendable, Hashable {
        case incoming, outgoing
    }

    /// How a transfer ended, or that it hasn't.
    public enum Outcome: Sendable, Hashable {
        /// Moving bytes, or waiting for the other side's Accept.
        case underWay
        case saved
        /// Someone pressed Cancel (either side).
        case cancelled
        /// Declined, refused by a rule, or a failure.
        case failed
    }

    /// One transfer as the panel sees it.
    public struct Item: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let direction: Direction
        public let outcome: Outcome
        public let bytes: UInt64
        public let totalBytes: UInt64
        public let startedAt: Date
        /// When it stopped moving; `nil` while under way.
        public let finishedAt: Date?

        public init(
            id: UUID,
            direction: Direction,
            outcome: Outcome,
            bytes: UInt64,
            totalBytes: UInt64,
            startedAt: Date,
            finishedAt: Date? = nil
        ) {
            self.id = id
            self.direction = direction
            self.outcome = outcome
            self.bytes = bytes
            self.totalBytes = totalBytes
            self.startedAt = startedAt
            self.finishedAt = finishedAt
        }

        public var isUnderWay: Bool { outcome == .underWay }

        /// Still listed at `now`: under way, or finished within the hour.
        public func isListed(at now: Date) -> Bool {
            guard !isUnderWay else { return true }
            guard let finishedAt else { return true }
            return now.timeIntervalSince(finishedAt) < TransferPanelPlan.finishedLifetime
        }
    }

    /// The tab's two groups.
    public enum Group: String, Sendable, Hashable, CaseIterable {
        case underWay, finished

        public var title: String {
            switch self {
            case .underWay: "Now"
            case .finished: "Last hour"
            }
        }
    }

    /// The items still listed at `now`.
    public static func listed(_ items: [Item], at now: Date) -> [Item] {
        items.filter { $0.isListed(at: now) }
    }

    /// The tab's groups, empty ones left out: under way newest first, then
    /// finished, most recently finished first.
    public static func groups(_ items: [Item], at now: Date) -> [(group: Group, items: [Item])] {
        let shown = listed(items, at: now)
        let underWay = shown.filter(\.isUnderWay).sorted { $0.startedAt > $1.startedAt }
        let finished = shown.filter { !$0.isUnderWay }
            .sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
        var result: [(group: Group, items: [Item])] = []
        if !underWay.isEmpty { result.append((.underWay, underWay)) }
        if !finished.isEmpty { result.append((.finished, finished)) }
        return result
    }

    /// Whether the Transfers tab shows.
    public static func showsTab(_ items: [Item], waitingPrompts: Int = 0, at now: Date) -> Bool {
        waitingPrompts > 0 || !listed(items, at: now).isEmpty
    }

    /// The tab's badge: what is under way (prompts included), or, when
    /// nothing is, how many finished in the last hour. `nil` hides it.
    public static func badge(_ items: [Item], waitingPrompts: Int = 0, at now: Date) -> Int? {
        let shown = listed(items, at: now)
        let underWay = shown.filter(\.isUnderWay).count + waitingPrompts
        let count = underWay > 0 ? underWay : shown.count
        return count > 0 ? count : nil
    }

    /// The fraction done across everything under way, by bytes; `nil` when
    /// nothing is under way or the sizes are unknown.
    public static func overallFraction(_ items: [Item], at now: Date) -> Double? {
        let active = listed(items, at: now).filter(\.isUnderWay)
        let total = active.reduce(UInt64(0)) { $0 + $1.totalBytes }
        guard !active.isEmpty, total > 0 else { return nil }
        let done = active.reduce(UInt64(0)) { $0 + min($1.bytes, $1.totalBytes) }
        return min(1, Double(done) / Double(total))
    }

    /// Whole percent, rounded down so it never says 100 % early.
    public static func percent(_ fraction: Double) -> Int {
        max(0, min(100, Int((fraction * 100).rounded(.down))))
    }

    /// The Devices view's one summary row; `nil` when there's nothing to
    /// list (the row and the tab are gone).
    ///
    /// - "3 files sending · 42 %", "1 file receiving · 8 %",
    ///   "5 files moving · 61 %" when both ways;
    /// - "1 waiting for you" while a prompt is up and nothing moves;
    /// - when everything has finished: "4 saved · 1 cancelled · 1 failed".
    public static func summary(_ items: [Item], waitingPrompts: Int = 0, at now: Date) -> String? {
        let shown = listed(items, at: now)
        let active = shown.filter(\.isUnderWay)
        if !active.isEmpty {
            let sending = active.filter { $0.direction == .outgoing }.count
            let receiving = active.count - sending
            let verb = receiving == 0 ? "sending" : sending == 0 ? "receiving" : "moving"
            var text = "\(active.count) \(active.count == 1 ? "file" : "files") \(verb)"
            if let fraction = overallFraction(items, at: now) {
                text += " · \(percent(fraction)) %"
            }
            if waitingPrompts > 0 { text += " · \(waitingPrompts) waiting for you" }
            return text
        }
        if waitingPrompts > 0 { return "\(waitingPrompts) waiting for you" }
        guard !shown.isEmpty else { return nil }
        let saved = shown.filter { $0.outcome == .saved }.count
        let cancelled = shown.filter { $0.outcome == .cancelled }.count
        let failed = shown.filter { $0.outcome == .failed }.count
        var parts: [String] = []
        if saved > 0 { parts.append("\(saved) saved") }
        if cancelled > 0 { parts.append("\(cancelled) cancelled") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }

    /// When the next finished item drops out, so the panel can refresh
    /// then; `nil` when nothing will.
    public static func nextExpiry(_ items: [Item], at now: Date) -> Date? {
        listed(items, at: now)
            .compactMap { $0.isUnderWay ? nil : $0.finishedAt.map { $0.addingTimeInterval(finishedLifetime) } }
            .min()
    }

    /// The outcome a transfer status means for the panel.
    public static func outcome(status: TransferStatus?, isActive: Bool) -> Outcome {
        switch status {
        case .saved?: return .saved
        case .failed(.cancelled)?: return .cancelled
        case .failed?, .refused?: return .failed
        // Bytes all sent and no answer yet: done as far as the panel knows.
        case nil: return isActive ? .underWay : .saved
        // Stopped while still waiting for the other side: it didn't go.
        case .awaitingApproval?: return isActive ? .underWay : .failed
        }
    }
}
