//
//  DeviceAuthorizationManager.swift
//  DeckHandMac
//

import Foundation
import UserNotifications
import Loom
import LoomKit
import SwiftUI
import Combine

@MainActor
final class DeviceAuthorizationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = DeviceAuthorizationManager()

    /// Devices the user has approved THIS app session. Deliberately not
    /// persisted: every fresh host launch prompts again. Manual accept /
    /// deny with no other checks — auto-grant from persisted state caused
    /// connections to be silently authorized against stale assumptions
    /// after reconnects, which made failures impossible to reason about.
    @Published var authorizedDeviceIDs: Set<LoomPeerID> = []
    
    @Published var pendingConnections: [LoomConnectionSnapshot] = []

    // Retain handles so we can route them after approval
    private var pendingHandles: [UUID: LoomConnectionHandle] = [:]
    private var pendingRequestedAt: [UUID: Date] = [:]
    private var pendingExpiryTasks: [UUID: Task<Void, Never>] = [:]
    /// Reads each pending connection from the moment it arrives and drops
    /// what it sends before Allow. Without it the messages buffered in the
    /// handle and all ran the moment the user clicked Allow.
    private var gates: [UUID: PreApprovalGate] = [:]

    // Callback so MacMenuBarView can pass authorized handles to the receiver,
    // with the gated stream the receiver must read instead of
    // `handle.messages`.
    var onDeviceAuthorized: ((LoomConnectionHandle, AsyncStream<Data>) -> Void)?
    /// Fired when the user revokes a connection so the receiver stops
    /// consuming its messages immediately — buffered commands from the
    /// revoked device are dropped, not executed.
    var onConnectionRevoked: ((UUID) -> Void)?
    private static let pendingRequestTimeout: Duration = .seconds(ApprovalStatusCopy.pendingRequestTimeout)

    override init() {
        super.init()
        // Nothing restored from disk — approval state starts empty every
        // launch, by design.
    }
    
    func prepareNotifications() {
        UNUserNotificationCenter.current().delegate = self

        let acceptAction = UNNotificationAction(identifier: "ACCEPT_ACTION", title: "Allow", options: .foreground)
        let rejectAction = UNNotificationAction(identifier: "REJECT_ACTION", title: "Deny", options: .destructive)
        let category = UNNotificationCategory(
            identifier: "INCOMING_CONNECTION",
            actions: [acceptAction, rejectAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { @Sendable success, error in
                if let error = error {
                    DeckHandLog.trust.error("Notification auth error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Explicit ask from the panel's Fix button. Safe to call when status
    /// is `.notDetermined`; a no-op prompt-wise once the user has decided.
    func requestNotificationPermissions() {
        prepareNotifications()
    }

    func isAuthorized(peerID: LoomPeerID) -> Bool {
        authorizedDeviceIDs.contains(peerID)
    }

    func handleIncomingConnection(_ connection: LoomConnectionSnapshot, handle: LoomConnectionHandle) {
        // Start reading (and discarding) this connection's messages now, so
        // nothing it sends while pending survives to run after Allow. One
        // gate per connection: its stream allows a single reader.
        let gate = gates[connection.id] ?? PreApprovalGate(source: handle.messages)
        // SIMPLE BY DESIGN: every incoming connection goes through an
        // explicit Accept / Deny. No persisted auto-grant, no same-iCloud
        // fast path, no other checks — the user decides, every time.
        // (`authorizedDeviceIDs` only short-circuits REPEAT connections
        // within the same already-approved session.)
        if isAuthorized(peerID: connection.peerID) {
            Task {
                do {
                    try await handle.send(.pairing(.authorizationStatus(state: .granted)))
                } catch {
                    // Recoverable: the iPad polls requestAuthorizationStatus
                    // and ControlReceiver answers it.
                    DeckHandLog.trust.error("Failed to push granted status: \(error.localizedDescription, privacy: .public)")
                }
            }
            gates.removeValue(forKey: connection.id)
            gate.open()
            onDeviceAuthorized?(handle, gate.messages)
            return
        }

        if let existing = pendingConnections.first(where: { $0.peerID == connection.peerID && $0.id != connection.id }) {
            removePendingConnection(id: existing.id)
            if let oldHandle = pendingHandles.removeValue(forKey: existing.id) {
                Task {
                    try? await oldHandle.send(.pairing(.authorizationStatus(state: .denied)))
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await oldHandle.disconnect()
                }
            }
        }
        
        // Not authorized, add to pending list
        if !pendingConnections.contains(where: { $0.id == connection.id }) {
            pendingConnections.append(connection)
            pendingHandles[connection.id] = handle
            gates[connection.id] = gate
            pendingRequestedAt[connection.id] = Date()
            DeckHandLog.trust.info("🔑 New pending request from \(connection.peerName, privacy: .public) conn=\(connection.id, privacy: .public) — awaiting Allow/Deny (approve in menu bar or notification)")
            Task {
                try? await handle.send(.pairing(.authorizationStatus(state: .pending)))
            }
            showNotification(for: connection)
            schedulePendingExpiry(for: connection.id)
        }
    }
    
    /// Grants access for this app session. Manual, every launch.
    func authorize(connection: LoomConnectionSnapshot) {
        authorizedDeviceIDs.insert(connection.peerID)
        let peerPending = pendingConnections
            .filter { $0.peerID == connection.peerID }
            .sorted { $0.connectedAt > $1.connectedAt }
        let target = peerPending.first ?? connection
        let staleForPeer = peerPending.filter { $0.id != target.id }

        for stale in staleForPeer {
            removePendingConnection(id: stale.id)
            if let staleHandle = pendingHandles.removeValue(forKey: stale.id) {
                Task {
                    try? await staleHandle.send(.pairing(.authorizationStatus(state: .denied)))
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await staleHandle.disconnect()
                }
            }
        }

        #if DEBUG
        print("Pixel Hand: 🔑 authorize() granting peer \(connection.peerName) on connection \(target.id); \(pendingConnections.count) other pending, \(peerPending.count) for this peer")
        #endif
        let pendingGate = gates.removeValue(forKey: target.id)
        removePendingConnection(id: target.id)
        if let handle = pendingHandles.removeValue(forKey: target.id) {
            // Open now, at the click: anything the remote sent before this
            // was dropped; from here on its input runs. The remote only
            // starts sending input once it sees `granted`, below.
            let gate = pendingGate ?? PreApprovalGate(source: handle.messages)
            gate.open()
            let messages = gate.messages
            if gate.droppedCount > 0 {
                DeckHandLog.trust.info("🔑 Dropped \(gate.droppedCount, privacy: .public) message(s) sent before approval on conn=\(target.id, privacy: .public)")
            }
            Task {
                // The push is best-effort, but a silent failure here used to
                // strand the iPad on the approval overlay while the host
                // believed the session was live. Log it — and note the iPad
                // also polls `requestAuthorizationStatus`, which is answered
                // from the (now-consuming) ControlReceiver loop, so a lost
                // push self-heals within one poll interval.
                DeckHandLog.trust.info("🔑 Granting \(connection.peerName, privacy: .public); pushing granted on conn=\(target.id, privacy: .public)")
                do {
                    try await handle.send(.pairing(.authorizationStatus(state: .granted)))
                } catch {
                    DeckHandLog.trust.error("Failed to push granted status: \(error.localizedDescription, privacy: .public)")
                }
                onDeviceAuthorized?(handle, messages)
            }
        } else {
            // Approval raced the 45 s expiry (or a dismissal): trust was
            // recorded but there's no live handle to notify. The iPad's
            // next connection attempt will be auto-granted.
            DeckHandLog.trust.info("Authorized \(connection.peerName, privacy: .public) but no pending handle remained (expired/dismissed)")
        }
    }
    
    func reject(connection: LoomConnectionSnapshot, loomContext: LoomContext) {
        removePendingConnection(id: connection.id)
        if let handle = pendingHandles.removeValue(forKey: connection.id) {
            Task {
                try? await handle.send(.pairing(.authorizationStatus(state: .denied)))
                try? await Task.sleep(nanoseconds: 100_000_000) // allow packet to send
                await loomContext.disconnect(connection)
            }
        }
    }
    
    func removeAndDisconnect(connection: LoomConnectionSnapshot, loomContext: LoomContext) {
        // Revoking is per device, so end every connection this peer has,
        // not just the row that was clicked: a second live connection used
        // to keep running input after its device's access was removed.
        var peerConnections = loomContext.connections.filter { $0.peerID == connection.peerID }
        if !peerConnections.contains(where: { $0.id == connection.id }) {
            peerConnections.append(connection)
        }
        authorizedDeviceIDs.remove(connection.peerID)
        for peerConnection in peerConnections {
            // Stop dispatching this device's commands BEFORE tearing down
            // the transport — otherwise buffered input keeps executing
            // during the (async) disconnect.
            onConnectionRevoked?(peerConnection.id)
            removePendingConnection(id: peerConnection.id)
            pendingHandles.removeValue(forKey: peerConnection.id)
        }
        Task {
            for peerConnection in peerConnections {
                await loomContext.disconnect(peerConnection)
            }
        }
    }

    func handleDismissal(_ dismissal: LoomConnectionDismissal) {
        removePendingConnection(id: dismissal.id)
        pendingHandles.removeValue(forKey: dismissal.id)
    }

    func pendingRequestedDate(for connectionID: UUID) -> Date? {
        pendingRequestedAt[connectionID]
    }

    func fallbackPrunePendingWithoutActiveConnection(activeConnectionIDs: Set<UUID>) {
        let orphaned = pendingConnections
            .map(\.id)
            .filter { !activeConnectionIDs.contains($0) }
        for id in orphaned {
            removePendingConnection(id: id)
            pendingHandles.removeValue(forKey: id)
        }
    }

    private func showNotification(for connection: LoomConnectionSnapshot) {
        let content = UNMutableNotificationContent()
        content.title = "Pixel Hand Connection"
        content.body = "Incoming control request from \(connection.peerName). Allow access?"
        content.sound = .default
        content.categoryIdentifier = "INCOMING_CONNECTION"
        
        // Stash both connection and peer IDs so notification actions can
        // still resolve to the latest pending request for this peer.
        content.userInfo = [
            "connectionID": connection.id.uuidString,
            "peerID": connection.peerID.uuidString,
        ]
        
        let request = UNNotificationRequest(identifier: "conn-\(connection.id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func schedulePendingExpiry(for connectionID: UUID) {
        pendingExpiryTasks[connectionID]?.cancel()
        pendingExpiryTasks[connectionID] = Task { [weak self] in
            try? await Task.sleep(for: Self.pendingRequestTimeout)
            await MainActor.run {
                guard let self else { return }
                guard self.pendingConnections.contains(where: { $0.id == connectionID }) else { return }
                self.removePendingConnection(id: connectionID)
                if let handle = self.pendingHandles.removeValue(forKey: connectionID) {
                    Task {
                        try? await handle.send(.pairing(.authorizationStatus(state: .denied)))
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await handle.disconnect()
                    }
                }
            }
        }
    }

    private func removePendingConnection(id: UUID) {
        pendingConnections.removeAll(where: { $0.id == id })
        // Releasing the gate ends its read of the connection.
        gates.removeValue(forKey: id)
        pendingRequestedAt.removeValue(forKey: id)
        pendingExpiryTasks[id]?.cancel()
        pendingExpiryTasks.removeValue(forKey: id)
        let notificationID = "conn-\(id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
    }

    // MARK: - UNUserNotificationCenterDelegate
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let idString = response.notification.request.content.userInfo["connectionID"] as? String
        let peerIDString = response.notification.request.content.userInfo["peerID"] as? String
        
        Task { @MainActor in
            if let idString = idString, let connectionID = UUID(uuidString: idString) {
                // Find the pending connection; if the notification is stale
                // for an older connection ID, fall back to the latest pending
                // request from the same peer.
                let pending =
                    self.pendingConnections.first(where: { $0.id == connectionID })
                    ?? {
                        guard let peerIDString, let peerUUID = UUID(uuidString: peerIDString) else {
                            return nil
                        }
                        let peerID = LoomPeerID(deviceID: peerUUID)
                        return self.pendingConnections.last(where: { $0.peerID == peerID })
                    }()
                if let pending {
                    if actionIdentifier == "ACCEPT_ACTION" {
                        self.authorize(connection: pending)
                    } else if actionIdentifier == "REJECT_ACTION" {
                        // Use `pending.id`, not the notification's original
                        // `connectionID` — when the notification was stale
                        // (peer reconnected, request replaced) the fallback
                        // above resolved a *different* pending entry. Keying
                        // the removal off the stale ID silently no-op'd the
                        // denial and left the iPad waiting out the 45 s
                        // expiry.
                        self.removePendingConnection(id: pending.id)
                        if let handle = self.pendingHandles.removeValue(forKey: pending.id) {
                            Task {
                                try? await handle.send(.pairing(.authorizationStatus(state: .denied)))
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                await handle.disconnect()
                            }
                        }
                    }
                }
            }
        }
        completionHandler()
    }
}
