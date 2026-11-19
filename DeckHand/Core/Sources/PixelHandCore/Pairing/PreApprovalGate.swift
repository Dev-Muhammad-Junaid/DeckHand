//
//  PreApprovalGate.swift
//  PixelHandCore
//
//  Sits between a connection's inbound messages and the Mac's message loop
//  while the user hasn't yet allowed the device.
//
//  Before this, nothing read a pending connection's messages, so they piled
//  up in the handle for up to 45 s. When the user clicked Allow, the message
//  loop started and ran the whole backlog: every tap, scroll and shortcut
//  the remote had sent while waiting fired at once.
//
//  Now the gate reads the connection from the moment it arrives. Until
//  `open()`, it drops everything except a few `requestAuthorizationStatus`
//  queries (the remote's resync path, answered right after approval) and a
//  few `submitCode` messages (S4), which go straight to the Mac's pairing
//  logic instead of the message loop. After `open()`, everything passes
//  through in order.
//

import Foundation

/// The decision logic, separate from the stream plumbing so it can be
/// tested synchronously.
public struct PreApprovalFilter: Sendable {
    /// Status queries kept while pending. The remote polls about once a
    /// second; one answer after approval is enough, a few cover loss.
    public static let maxHeldStatusQueries = 4
    /// Pairing codes taken from one pending connection. The Mac's
    /// `PairingCodeWindow` limits wrong answers across all devices; this
    /// only stops one connection from flooding it.
    public static let maxPairingCodesWhilePending = 8

    public private(set) var isOpen = false
    public private(set) var droppedCount = 0
    private var heldStatusQueries = 0
    private var pairingCodesTaken = 0

    /// What happens to one message.
    public enum Disposition: Equatable, Sendable {
        /// Pass it to the message loop.
        case pass
        /// Drop it.
        case drop
        /// A pairing code sent while pending: hand it to the pairing logic,
        /// not the message loop.
        case pairingCode(String)
    }

    public init() {}

    public mutating func open() {
        isOpen = true
    }

    /// Whether `data` should reach the message loop. A pairing code sent
    /// while pending doesn't (see `take(_:)`).
    public mutating func admit(_ data: Data) -> Bool {
        take(data) == .pass
    }

    /// Decides one message.
    public mutating func take(_ data: Data) -> Disposition {
        if isOpen { return .pass }
        if heldStatusQueries < Self.maxHeldStatusQueries, Self.isStatusQuery(data) {
            heldStatusQueries += 1
            return .pass
        }
        if pairingCodesTaken < Self.maxPairingCodesWhilePending, let code = Self.pairingCode(in: data) {
            pairingCodesTaken += 1
            return .pairingCode(code)
        }
        droppedCount += 1
        return .drop
    }

    public static func isStatusQuery(_ data: Data) -> Bool {
        guard data.count <= 256,
              let message = try? ControlMessageCoding.decode(data) else {
            return false
        }
        if case .pairing(.requestAuthorizationStatus) = message { return true }
        return false
    }

    /// The code in a `pairing.submitCode` message, or `nil` for anything
    /// else (including a code longer than `PairingCode.maxInputLength`).
    public static func pairingCode(in data: Data) -> String? {
        guard data.count <= 256,
              let message = try? ControlMessageCoding.decode(data),
              case let .pairing(.submitCode(code)) = message,
              code.utf8.count <= PairingCode.maxInputLength else {
            return nil
        }
        return code
    }
}

/// Reads `source` from creation and republishes it as `messages`, filtered
/// by `PreApprovalFilter`. Create one per connection, as soon as it arrives,
/// and never read `source` anywhere else (an `AsyncStream` has one reader).
public final class PreApprovalGate: @unchecked Sendable {
    /// What the message loop should read instead of the handle's stream.
    public let messages: AsyncStream<Data>
    private let state: State

    /// - Parameters:
    ///   - source: The connection's inbound messages.
    ///   - onPairingCode: Called (off the main actor, in arrival order) with
    ///     each pairing code the remote sends while pending.
    public init(source: AsyncStream<Data>, onPairingCode: (@Sendable (String) -> Void)? = nil) {
        let (messages, continuation) = AsyncStream.makeStream(of: Data.self)
        let state = State()
        self.messages = messages
        self.state = state
        // Holds `state` and `continuation`, not the gate, so the pump keeps
        // running after the gate itself is released at approval time.
        let pump = Task {
            for await data in source {
                switch state.take(data) {
                case .pass:
                    continuation.yield(data)
                case let .pairingCode(code):
                    onPairingCode?(code)
                case .drop:
                    break
                }
            }
            continuation.finish()
        }
        // When the reader goes away (connection revoked, gate dropped on
        // denial), stop reading the source too.
        continuation.onTermination = { _ in pump.cancel() }
    }

    /// Lets everything after this point through. Call at the moment the
    /// user allows the device.
    public func open() {
        state.open()
    }

    /// Messages dropped while pending, for logging.
    public var droppedCount: Int {
        state.droppedCount
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var filter = PreApprovalFilter()

        func take(_ data: Data) -> PreApprovalFilter.Disposition {
            lock.lock()
            defer { lock.unlock() }
            return filter.take(data)
        }

        func open() {
            lock.lock()
            filter.open()
            lock.unlock()
        }

        var droppedCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return filter.droppedCount
        }
    }
}
