//
//  NetworkStartGate.swift
//  PixelHandCore – Network
//
//  Single-flight start for the remote's network runtime (build 22, P2).
//
//  With no iCloud account the first start waited about 45 s on the
//  account check. Meanwhile the picker offered "Can’t find your Mac?" with
//  Try again, which started a second attempt beside the first: the second
//  failed ("Already advertising service"), the first was cancelled, and
//  discovery never ran until a relaunch.
//
//  The gate makes every request go through one start:
//
//  - Launch, or Try again after a failure: start (a new attempt number).
//  - Try again while a start is in flight: join it; nothing new starts and
//    nothing is cancelled.
//  - Try again once running: refresh discovery instead of starting again.
//  - A finished attempt that isn't the current one is ignored, so a late
//    result can't overwrite a newer one.
//

import Foundation

/// The network runtime's start, as a single-flight state machine.
public struct NetworkStartGate: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        /// Nothing asked yet.
        case idle
        /// Attempt `attempt` is in flight.
        case starting(attempt: Int)
        /// Started: advertising and browsing.
        case running
        /// The last attempt failed; Try again starts a new one.
        case failed(message: String)
    }

    /// What the caller does for a request.
    public enum Action: Sendable, Hashable {
        /// Start the runtime; report back with this attempt number.
        case start(attempt: Int)
        /// A start is in flight: wait for it (Try again joins it).
        case join(attempt: Int)
        /// Already running: refresh discovery.
        case refresh
    }

    public private(set) var phase: Phase = .idle
    /// The last attempt number handed out (1 for the first start).
    public private(set) var attempt = 0

    public init() {}

    /// Launch or Try again.
    public mutating func request() -> Action {
        switch phase {
        case .idle, .failed:
            attempt += 1
            phase = .starting(attempt: attempt)
            return .start(attempt: attempt)
        case let .starting(current):
            return .join(attempt: current)
        case .running:
            return .refresh
        }
    }

    /// Attempt `attempt` ended: `error` is `nil` on success. Returns
    /// `false` (and changes nothing) for an attempt that isn't in flight.
    @discardableResult
    public mutating func finished(attempt finished: Int, error: String?) -> Bool {
        guard case let .starting(current) = phase, current == finished else { return false }
        if let error {
            phase = .failed(message: error)
        } else {
            phase = .running
        }
        return true
    }

    /// The runtime was stopped (for example torn down by the system); the
    /// next request starts again.
    public mutating func stopped() {
        phase = .idle
    }

    /// The message the picker shows instead of "Searching", with Retry.
    public var failureMessage: String? {
        if case let .failed(message) = phase { return message }
        return nil
    }

    /// A start is in flight.
    public var isStarting: Bool {
        if case .starting = phase { return true }
        return false
    }

    /// Started and discovering.
    public var isRunning: Bool { phase == .running }
}
