//
//  FocusTracker.swift
//  DeckHandMac
//
//  Follows the focused text field for remotes that asked
//  (`system.watchFocus(on: true)`, OT-12: the Type panel's loupe) and sends
//  them `system.focusState`. Owned by the Mac system control lane.
//
//  One loop serves every watching remote. It looks about eight times a
//  second while things change and four once it has been quiet for two
//  seconds (`FocusReading.pollInterval`), and sends only when a reading
//  differs beyond 0.75 pt or in anything else (`differsMeaningfully`).
//  The Accessibility reads happen in `FocusReader`, on its own serial
//  queue, never on the main actor: an app that doesn't answer costs that
//  queue 0.1 s a call, not the message loop.
//
//  Why a throttled poll and not AXObserver notifications: the loupe needs
//  the field's *place*, and nothing notifies when a field moves because
//  its window was dragged, resized or scrolled; Chromium and Electron send
//  focus and selection notifications unreliably; an observer has to be
//  re-registered on every app switch and needs a run loop; and the pointer
//  fallback has to be sampled anyway. A look is a handful of AX calls to
//  one app (well under a millisecond for a responsive app), only while a
//  remote watches.
//
//  Stops when the last watcher says `false` or disconnects
//  (`MacSystemSession.connectionRemoved`). While the Mac is locked it
//  reads nothing and sends one `.none` snapshot (`LockPolicy.withholdsFocus`).
//

import Foundation
import LoomKit

@MainActor
final class FocusTracker {
    static let shared = FocusTracker()

    private var watchers: [UUID: LoomConnectionHandle] = [:]
    private var lastSent: FocusedFieldSnapshot?
    private var loop: Task<Void, Never>?
    private let reader = FocusReader()

    private init() {}

    /// `system.watchFocus(on:)` from `connection`.
    func watch(_ on: Bool, connection: LoomConnectionHandle) {
        if on {
            let isNew = watchers[connection.id] == nil
            watchers[connection.id] = connection
            if isNew, let lastSent {
                // A second remote joins a running loop: give it the latest
                // reading now rather than at the next change.
                send(lastSent, to: [connection])
            }
            startIfNeeded()
        } else {
            remove(connection.id)
        }
    }

    /// The remote disconnected.
    func removeConnection(id: UUID) {
        remove(id)
    }

    /// The lock changed: withhold at once, or look again at once.
    func lockStateChanged(_ state: MacLockState) {
        guard !watchers.isEmpty else { return }
        if LockPolicy.withholdsFocus(state) {
            publish(FocusReader.nothing())
        } else {
            lastSent = nil // the next reading goes out whatever it is
        }
    }

    private func remove(_ id: UUID) {
        guard watchers.removeValue(forKey: id) != nil else { return }
        if watchers.isEmpty {
            loop?.cancel()
            loop = nil
            lastSent = nil
            reader.endWatch()
            DeckHandLog.context.info("Focus tracking stopped")
        }
    }

    private func startIfNeeded() {
        guard loop == nil else { return }
        DeckHandLog.context.info("Focus tracking started")
        loop = Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        var lastChange = ContinuousClock.now
        while !Task.isCancelled, !watchers.isEmpty {
            let snapshot: FocusedFieldSnapshot
            if LockPolicy.withholdsFocus(MacLockMonitor.shared.state) {
                snapshot = FocusReader.nothing()
            } else {
                let reading = await reader.read(front: FocusReader.frontmost())
                // The Mac may have locked while the reader looked.
                snapshot = LockPolicy.withholdsFocus(MacLockMonitor.shared.state) ? FocusReader.nothing() : reading
            }
            guard !Task.isCancelled, !watchers.isEmpty else { break }
            if publish(snapshot) {
                lastChange = .now
            }
            let quiet = ContinuousClock.now - lastChange
            let seconds = Double(quiet.components.seconds) + Double(quiet.components.attoseconds) / 1e18
            try? await Task.sleep(for: .seconds(FocusReading.pollInterval(unchangedFor: seconds)))
        }
    }

    /// Sends `snapshot` to every watcher if it differs from the last one
    /// sent. Returns whether it went out.
    @discardableResult
    private func publish(_ snapshot: FocusedFieldSnapshot) -> Bool {
        guard FocusReading.differsMeaningfully(snapshot, from: lastSent) else { return false }
        lastSent = snapshot
        send(snapshot, to: Array(watchers.values))
        return true
    }

    private func send(_ snapshot: FocusedFieldSnapshot, to handles: [LoomConnectionHandle]) {
        let message = ControlMessage.system(.focusState(focus: snapshot))
        for handle in handles {
            Task { try? await handle.send(message) }
        }
    }
}
