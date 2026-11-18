//
//  LockGate.swift
//  DeckHandMac
//
//  The locked-Mac gate (S8), in front of the router: `ControlReceiver`
//  asks it once per decoded, validated message. It applies Core's
//  `LockPolicy.decide` against `MacLockMonitor`'s state, answers a refused
//  request so the remote doesn't wait (a refused receipt, a screenshot
//  error, an empty window list), and for messages it lets through it does
//  the per-message work of this lane: display wake for a person's action
//  and the pointer-display check for the Spaces snapshot.
//
//  `MacSystemSession` fans connection start/end and lock changes out to
//  this lane's monitors, so `ControlReceiver` needs no more than the one
//  gate call.
//

import Foundation
import LoomKit

@MainActor
final class LockGate {
    static let shared = LockGate()

    /// Remotes whose app-list request was refused while locked; they get
    /// the list at the unlock.
    private var pendingAppLists: [UUID: LoomConnectionHandle] = [:]
    /// Last time a refusal of each kind was logged (at most one a minute).
    private var lastRefusalLog: [String: Date] = [:]

    private init() {}

    /// Whether `message` may go on to its handler.
    func admit(_ message: ControlMessage, from connection: LoomConnectionHandle) async -> Bool {
        let state = MacLockMonitor.shared.state
        switch LockPolicy.decide(message, state: state) {
        case .allow:
            if DisplayWakePolicy.isPersonAction(message) {
                DisplayWake.shared.note(.personAction, lock: state)
            }
            if case .input(.mouseDelta) = message {
                SpacesMonitor.shared.noteCursorActivity()
            }
            return true

        case let .refuse(reply):
            logRefusal(message, state: state)
            await answer(reply, to: connection)
            return false
        }
    }

    private func answer(_ reply: LockRefusalReply, to connection: LoomConnectionHandle) async {
        switch reply {
        case .none:
            break
        case let .receipt(requestID):
            try? await connection.send(.deck(.receipt(requestID: requestID, outcome: .refused(reason: .macLocked))))
        case let .screenshotError(requestID):
            try? await connection.send(.capture(.screenshotError(requestID: requestID, message: LockPolicy.lockedErrorMessage)))
        case let .emptyWindowList(requestID):
            try? await connection.send(.capture(.windowListResponse(requestID: requestID, windows: [])))
        case .appListAfterUnlock:
            pendingAppLists[connection.id] = connection
        }
    }

    private func logRefusal(_ message: ControlMessage, state: MacLockState) {
        let kind = Self.kind(of: message)
        let now = Date()
        if let last = lastRefusalLog[kind], now.timeIntervalSince(last) < 60 { return }
        lastRefusalLog[kind] = now
        DeckHandLog.input.info("Lock gate: refused \(kind, privacy: .public) while \(state.rawValue, privacy: .public) (at most one line a minute per kind)")
    }

    /// The message's domain and case, for logs (no payload).
    private static func kind(of message: ControlMessage) -> String {
        guard let payload = Mirror(reflecting: message).children.first?.value else {
            return message.domain.rawValue
        }
        // A case with values reflects as one child labelled with its name;
        // one without reflects as itself.
        let name = Mirror(reflecting: payload).children.first?.label ?? String(describing: payload)
        return "\(message.domain.rawValue).\(name)"
    }

    // MARK: - Unlock and connection end

    fileprivate func unlocked() {
        let waiting = pendingAppLists
        pendingAppLists.removeAll()
        guard !waiting.isEmpty else { return }
        let apps = InstalledAppScanner.shared.installedApps()
        for handle in waiting.values {
            Task { try? await handle.send(.apps(.appListResponse(apps: apps))) }
        }
    }

    fileprivate func forget(_ id: UUID) {
        pendingAppLists.removeValue(forKey: id)
    }
}

/// Connection start/end and lock changes for the Mac system control lane's
/// monitors. Called from `ActiveAppMonitor` (registered by
/// `ControlReceiver` for every approved connection) and `MacLockMonitor`.
@MainActor
enum MacSystemSession {
    static func connectionAdded(_ handle: LoomConnectionHandle, id: UUID) {
        // Lock state first: the other monitors read it.
        MacLockMonitor.shared.addConnection(handle, id: id)
        DisplayWake.shared.note(.connected, lock: MacLockMonitor.shared.state)
        SpacesMonitor.shared.addConnection(handle, id: id)
    }

    static func connectionRemoved(id: UUID) {
        MacLockMonitor.shared.removeConnection(id: id)
        SpacesMonitor.shared.removeConnection(id: id)
        LockGate.shared.forget(id)
    }

    static func lockStateChanged(from previous: MacLockState, to next: MacLockState) {
        let wasWithheld = LockPolicy.withholdsContext(previous)
        let withheld = LockPolicy.withholdsContext(next)
        if wasWithheld != withheld {
            ActiveAppMonitor.shared.contextVisibilityChanged()
            RunningAppMonitor.shared.contextVisibilityChanged()
            ContextObserver.shared.contextVisibilityChanged()
        }
        SpacesMonitor.shared.scheduleBroadcast()
        if !next.isLocked {
            LockGate.shared.unlocked()
        }
    }
}
