//
//  ControlReceiver.swift
//  DeckHandMac
//

import Foundation
import LoomKit

/// Owns each authorized connection's lifecycle: liveness, the message loop,
/// decoding and validation. Every message then goes to its domain's handler
/// through `MacHandlers.router` (see `Handlers/`).
@MainActor
final class ControlReceiver {
    /// One handler per protocol domain, registered in one place.
    private let handlers = MacHandlers()
    /// Consume tasks keyed by `handle.id` so authorization revocation and
    /// liveness timeouts can cancel consumption *immediately* — buffered
    /// commands from a dead/revoked iPad are dropped, never replayed.
    private var connectionTasks: [UUID: Task<Void, Never>] = [:]
    private var connectionHandles: [UUID: LoomConnectionHandle] = [:]
    /// Liveness per connection. Stamped off the main actor as each message
    /// arrives (`HeartbeatResponder`), so a busy main actor can't make a
    /// live iPad look silent. Only enforced once the peer has pinged.
    private var livenessClocks: [UUID: LivenessClock] = [:]
    /// Connections this Mac dropped for silence, so the loop-ended log can
    /// say which side gave up first.
    private var droppedForSilence: Set<UUID> = []
    private var livenessSweepTask: Task<Void, Never>?
    /// Sampled counter for high-rate input logging (see consumeMessages).
    private var inputMessageCount = 0

    /// Fired with the number of authorized connections being served whenever
    /// one starts or ends. Drives the menu bar icon's connected state.
    var onLiveConnectionsChanged: ((Int) -> Void)?

    // Connections silent for `LivenessPolicy.hostTimeout` (15 s) after
    // having pinged at least once are declared dead. The iPad pings every
    // 2 s and gives up after 10 s, so it normally notices first.

    /// Called from MacMenuBarView for each newly established incoming connection.
    /// `messages` is the connection's stream after `PreApprovalGate`; read it,
    /// never `connectionHandle.messages`, which the gate already reads.
    func observeConnection(_ connectionHandle: LoomConnectionHandle, messages gatedMessages: AsyncStream<Data>) {
        let key = connectionHandle.id
        connectionHandles[key] = connectionHandle
        let clock = LivenessClock(LivenessPolicy.hostMonitor())
        livenessClocks[key] = clock
        // Pongs go out as pings arrive, off the main actor; everything is
        // still passed on, in order, to the main-actor loop below.
        let messages = HeartbeatResponder.relay(gatedMessages, clock: clock) { seq in
            do {
                try await connectionHandle.send(.session(.pong(seq: seq)))
            } catch {
                DeckHandLog.connection.error("Pong \(seq, privacy: .public) to \(key, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        onLiveConnectionsChanged?(connectionHandles.count)
        startLivenessSweepIfNeeded()
        connectionTasks[key] = Task { [weak self] in
            ActiveAppMonitor.shared.addConnection(connectionHandle, id: key)
            RunningAppMonitor.shared.addConnection(connectionHandle, id: key)
            ContextObserver.shared.addConnection(connectionHandle, id: key)
            // Tell the remote up front what this host can actually do, so
            // it can explain missing permissions instead of failing silently.
            await self?.handlers.session.sendHostStatus(to: connectionHandle)
            await self?.consumeMessages(from: connectionHandle, messages: messages)
            // The message loop has ended (stream finished, task cancelled
            // by revocation, or liveness timeout). Stop any mirror stream
            // so capture doesn't burn CPU/GPU against a dead handle.
            await MirrorStreamService.shared.stop(subscriberID: key)
            _ = await MainActor.run { [weak self] in
                self?.cleanupConnection(key)
            }
        }
    }

    /// Immediately stops consuming a connection's messages. Called on
    /// authorization revocation and liveness timeout: any commands the
    /// iPad queued before dying are discarded instead of executed.
    func cancelConsumption(connectionID: UUID) {
        guard let task = connectionTasks[connectionID] else { return }
        #if DEBUG
        print("Pixel Hand: 🛑 cancelling consumption for \(connectionID) (revoked or liveness timeout)")
        #endif
        task.cancel()
    }

    private func cleanupConnection(_ key: UUID) {
        connectionTasks.removeValue(forKey: key)
        connectionHandles.removeValue(forKey: key)
        onLiveConnectionsChanged?(connectionHandles.count)
        livenessClocks.removeValue(forKey: key)
        droppedForSilence.remove(key)
        ActiveAppMonitor.shared.removeConnection(id: key)
        RunningAppMonitor.shared.removeConnection(id: key)
        ContextObserver.shared.removeConnection(id: key)
    }

    /// Periodic check: any heartbeat-capable connection that has gone
    /// silent past the timeout is dead — cancel its consumption and
    /// disconnect the handle so the menu bar stops showing a zombie row.
    private func startLivenessSweepIfNeeded() {
        guard livenessSweepTask == nil else { return }
        livenessSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LivenessPolicy.hostSweepInterval))
                await self?.sweepDeadConnections()
            }
        }
    }

    private func sweepDeadConnections() async {
        let now = Date()
        for (key, clock) in livenessClocks {
            let verdict = clock.check(at: now)
            if case let .localStall(gap) = verdict {
                DeckHandLog.connection.info("Liveness sweep for \(key, privacy: .public) ran \(gap, format: .fixed(precision: 1), privacy: .public)s late (Mac stalled or slept); restarting its silence clock")
                continue
            }
            guard case let .dead(silence, sinceHeartbeat) = verdict else { continue }
            let state = clock.snapshot
            DeckHandLog.connection.error("Liveness: MAC GAVE UP on \(key, privacy: .public): nothing received for \(silence, format: .fixed(precision: 1), privacy: .public)s (last ping \(sinceHeartbeat, format: .fixed(precision: 1), privacy: .public)s ago, \(state.inboundCount, privacy: .public) messages total, timeout \(LivenessPolicy.hostTimeout, privacy: .public)s) — dropping")
            droppedForSilence.insert(key)
            cancelConsumption(connectionID: key)
            if let handle = connectionHandles[key] {
                Task { await handle.disconnect() }
            }
            cleanupConnection(key)
        }
    }

    private func consumeMessages(from connectionHandle: LoomConnectionHandle, messages: AsyncStream<Data>) async {
        for await data in messages {
            // Honors cancelConsumption: stop dispatching the moment the
            // connection is revoked or timed out, even with a backlog.
            if Task.isCancelled { return }
            let decoded: ControlMessage
            do {
                decoded = try ControlMessageCoding.decode(data, maxBytes: ProtocolLimits.maxRemoteMessageBytes)
            } catch {
                DeckHandLog.connection.error("Dropped an undecodable message (\(data.count, privacy: .public) B) from \(connectionHandle.id, privacy: .public): \(String(describing: error), privacy: .public)")
                continue
            }
            // Every number from the remote is checked here, once, before
            // any handler sees it: non-finite values drop the message and
            // the rest are clamped (PH-031).
            guard let message = RemoteInputValidation.sanitize(decoded) else {
                DeckHandLog.input.error("Dropped a message with an invalid number or an oversize field from \(connectionHandle.id, privacy: .public)")
                continue
            }
            // Arrival visibility: when the iPad "does nothing", the first
            // question is whether its messages reach this loop at all. Logged
            // through DeckHandLog (always-on) so this is visible in Console.app
            // for release/TestFlight builds, not just Xcode-attached DEBUG.
            // High-rate input is sampled so the stream stays readable.
            switch message {
            case .input(.mouseDelta), .input(.mouseScroll):
                inputMessageCount += 1
                if inputMessageCount % 120 == 1 {
                    DeckHandLog.input.info("📥 input stream alive (\(self.inputMessageCount) input messages received)")
                }
            default:
                DeckHandLog.connection.debug("📥 dispatching \(String(describing: message), privacy: .public)")
            }
            // Locked-Mac gate (S8, Mac system control lane): refuses what a
            // locked Mac mustn't do and answers the remote; see LockGate.
            guard await LockGate.shared.admit(message, from: connectionHandle) else { continue }
            await handlers.router.route(message, from: connectionHandle)
        }
        let id = connectionHandle.id
        if droppedForSilence.contains(id) {
            DeckHandLog.connection.info("📪 message loop ended for \(id, privacy: .public): the Mac dropped it for silence")
        } else if Task.isCancelled {
            DeckHandLog.connection.info("📪 message loop ended for \(id, privacy: .public): revoked or replaced on the Mac")
        } else {
            let since = livenessClocks[id].map { Date().timeIntervalSince($0.snapshot.lastInboundAt) } ?? -1
            DeckHandLog.connection.info("📪 message loop ended for \(id, privacy: .public): the iPad closed the connection (IPAD GAVE UP or left; last message \(since, format: .fixed(precision: 1), privacy: .public)s ago)")
        }
    }
}
