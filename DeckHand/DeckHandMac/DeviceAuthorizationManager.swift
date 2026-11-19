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

    /// Devices with a live, allowed session, for the menu bar's list. Not a
    /// trust decision: trust is keyed on the verified identity
    /// (`sessionApprovedRefs`, `PairedDeviceStore`).
    @Published var authorizedDeviceIDs: Set<LoomPeerID> = []
    
    @Published var pendingConnections: [LoomConnectionSnapshot] = []

    // MARK: Pairing (S4)

    /// The paired-device list (persisted). Paired devices skip the prompt.
    let store: PairedDeviceStore
    /// Loom's trust hooks over `store`; a correct pairing code goes through
    /// its `grantTrust(to:)`.
    private let trustProvider: DeckHandHandshakeTrustProvider
    /// Devices the user clicked Allow for in this app session, by verified
    /// identity. Deliberately not persisted: "Allow" lasts one launch;
    /// pairing is what persists. (Keyed on the identity, not the Loom
    /// device ID, so another key can't reuse an allowed device's ID.)
    private var sessionApprovedRefs: Set<PairedDeviceRef> = []
    /// The verified identity of every connection the Mac is handling.
    private var identities: [UUID: TrustCandidate] = [:]
    private var rawIdentities: [UUID: LoomPeerIdentity] = [:]
    /// Allowed connections, so "Forget" can end a live session.
    private var liveHandles: [UUID: LoomConnectionHandle] = [:]
    private var livePeerIDs: [UUID: LoomPeerID] = [:]
    /// Paired or allowed devices with a live session, for the menu bar.
    @Published private(set) var liveRefs: Set<PairedDeviceRef> = []
    /// The Mac's one pairing code at a time.
    private var codeWindow = PairingCodeWindow()
    /// What the menu bar's pairing panel shows.
    @Published private(set) var pairingDisplay: PairingCodeWindow.Display = .none
    /// What the pairing QR code holds while a code is showing.
    @Published private(set) var pairingInvite: PairingInvite?

    // Retain handles so we can route them after approval
    private var pendingHandles: [UUID: LoomConnectionHandle] = [:]
    private var pendingRequestedAt: [UUID: Date] = [:]
    private var pendingExpiryTasks: [UUID: Task<Void, Never>] = [:]
    /// Reads each pending connection from the moment it arrives and drops
    /// what it sends before Allow. Without it the messages buffered in the
    /// handle and all ran the moment the user clicked Allow. It hands
    /// pairing codes sent while pending to `handlePendingCode`.
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

    init(store: PairedDeviceStore = .shared) {
        self.store = store
        trustProvider = DeckHandHandshakeTrustProvider(store: store)
        super.init()
        // "Allow" starts empty every launch, by design; only pairing
        // (PairedDeviceStore) persists.
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
        // gate per connection: its stream allows a single reader. Pairing
        // codes it sends while pending come back to `handlePendingCode`.
        let connectionID = connection.id
        let gate = gates[connectionID] ?? PreApprovalGate(source: handle.messages) { [weak self] code in
            Task { @MainActor in
                await self?.handlePendingCode(code, connectionID: connectionID)
            }
        }
        gates[connectionID] = gate
        Task {
            let identity = await handle.verifiedPeerIdentity()
            admit(connection, handle: handle, gate: gate, identity: identity)
        }
    }

    /// Decides a new connection from the identity Loom verified:
    /// paired → no prompt; allowed earlier this launch → no prompt;
    /// otherwise Allow / Deny (or a pairing code); unverified → refused.
    private func admit(
        _ connection: LoomConnectionSnapshot,
        handle: LoomConnectionHandle,
        gate: PreApprovalGate,
        identity: LoomPeerIdentity?
    ) {
        let admission = store.admission(for: identity)
        if let identity, let candidate = TrustCandidate(identity: identity) {
            identities[connection.id] = candidate
            rawIdentities[connection.id] = identity
        }

        switch admission {
        case .refuse:
            // Loom's handshake already requires a verified key
            // (DeckHandHandshakeTrustProvider); this is the second lock.
            DeckHandLog.trust.error("🔑 Refusing \(connection.peerName, privacy: .public) conn=\(connection.id, privacy: .public): no verified identity key")
            gates.removeValue(forKey: connection.id)
            forgetConnection(connection.id)
            Task {
                try? await handle.send(.pairing(.authorizationStatus(state: .denied)))
                try? await Task.sleep(nanoseconds: 100_000_000)
                await handle.disconnect()
            }
            return

        case let .autoGrant(device):
            if let candidate = identities[connection.id] {
                store.noteSeen(candidate)
            }
            DeckHandLog.trust.info("🔑 \(device.name, privacy: .public) is paired; connecting without a prompt conn=\(connection.id, privacy: .public)")
            grant(connection, handle: handle, gate: gate)
            return

        case let .askUser(ref):
            if sessionApprovedRefs.contains(ref) {
                // Allowed earlier in this app session.
                grant(connection, handle: handle, gate: gate)
                return
            }
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
            DeckHandLog.trust.info("🔑 New pending request from \(connection.peerName, privacy: .public) conn=\(connection.id, privacy: .public) — awaiting Allow/Deny or a pairing code (menu bar or notification)")
            Task {
                try? await handle.send(.pairing(.authorizationStatus(state: .pending)))
            }
            showNotification(for: connection)
            schedulePendingExpiry(for: connection.id)
        }
    }

    /// Lets a connection's messages through and tells the remote, with
    /// whether it is paired.
    private func grant(_ connection: LoomConnectionSnapshot, handle: LoomConnectionHandle, gate: PreApprovalGate) {
        gates.removeValue(forKey: connection.id)
        authorizedDeviceIDs.insert(connection.peerID)
        liveHandles[connection.id] = handle
        livePeerIDs[connection.id] = connection.peerID
        refreshLiveRefs()
        let paired = isPaired(connectionID: connection.id)
        // Open now: anything sent before this was dropped; from here on its
        // input runs. The remote only starts sending input once it sees
        // `granted`, below.
        gate.open()
        let messages = gate.messages
        if gate.droppedCount > 0 {
            DeckHandLog.trust.info("🔑 Dropped \(gate.droppedCount, privacy: .public) message(s) sent before approval on conn=\(connection.id, privacy: .public)")
        }
        Task {
            // The push is best-effort, but a silent failure here used to
            // strand the iPad on the approval overlay while the host
            // believed the session was live. Log it — and note the iPad
            // also polls `requestAuthorizationStatus`, which is answered
            // from the (now-consuming) ControlReceiver loop, so a lost
            // push self-heals within one poll interval.
            DeckHandLog.trust.info("🔑 Granting \(connection.peerName, privacy: .public) (paired: \(paired)); pushing granted on conn=\(connection.id, privacy: .public)")
            do {
                try await handle.send(.pairing(.authorizationStatus(state: .granted)))
                try await handle.send(.pairing(.pairedStatus(paired: paired)))
            } catch {
                DeckHandLog.trust.error("Failed to push granted status: \(error.localizedDescription, privacy: .public)")
            }
            onDeviceAuthorized?(handle, messages)
        }
    }

    /// Grants access for this app session (the Allow button). Manual,
    /// every launch, unless the device pairs.
    func authorize(connection: LoomConnectionSnapshot) {
        let peerPending = pendingConnections
            .filter { $0.peerID == connection.peerID }
            .sorted { $0.connectedAt > $1.connectedAt }
        let target = peerPending.first ?? connection
        let staleForPeer = peerPending.filter { $0.id != target.id }
        if let ref = identities[target.id]?.ref {
            sessionApprovedRefs.insert(ref)
        }

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
            let gate = pendingGate ?? PreApprovalGate(source: handle.messages)
            grant(target, handle: handle, gate: gate)
        } else {
            // Approval raced the 45 s expiry (or a dismissal): there's no
            // live handle to notify. The device asks again next time.
            DeckHandLog.trust.info("Authorized \(connection.peerName, privacy: .public) but no pending handle remained (expired/dismissed)")
        }
    }

    // MARK: - Pairing code (S4)

    /// Shows a new pairing code (and its QR invite) in the menu bar.
    func showPairingCode() {
        let result = codeWindow.issue(now: Date())
        if case let .issued(code, _) = result {
            pairingInvite = Self.makeInvite(code: code)
            DeckHandLog.trust.info("🔐 Showing a pairing code (valid \(Int(PairingCodeWindow.lifetime), privacy: .public) s)")
        }
        refreshPairingDisplay()
    }

    /// Stops showing the code (the user closed the panel).
    func cancelPairingCode() {
        codeWindow.cancel()
        refreshPairingDisplay()
    }

    /// Moves an expired code or an ended lockout on. The panel calls this
    /// on a timer while it is open.
    func refreshPairingDisplay() {
        let now = Date()
        codeWindow.refresh(now: now)
        let display = codeWindow.display(now: now)
        if display != pairingDisplay { pairingDisplay = display }
        if case .code = display {} else if pairingInvite != nil {
            pairingInvite = nil
        }
    }

    private static func makeInvite(code: PairingCode) -> PairingInvite? {
        guard let keyID = try? LoomIdentityManager.shared.currentIdentity().keyID else { return nil }
        let deviceID = LoomSharedDeviceID.getOrCreate(suiteName: "DeckHandLoomStore")
        return PairingInvite(code: code, macDeviceID: deviceID, macIdentityKeyID: keyID)
    }

    /// Checks a code against the window for a verified device and pairs it
    /// when right. An already-paired device is told `.accepted` without
    /// touching the window.
    private func verifyCode(_ code: String, connectionID: UUID) async -> PairingCodeResult {
        guard let candidate = identities[connectionID], let identity = rawIdentities[connectionID] else {
            return .noActiveCode
        }
        if store.isPaired(candidate.ref) { return .accepted }
        let result = codeWindow.verify(code, identityKeyID: candidate.identityKeyID, now: Date())
        refreshPairingDisplay()
        DeckHandLog.trust.info("🔐 Pairing code from \(candidate.name, privacy: .public): \(String(describing: result), privacy: .public)")
        guard result == .accepted else { return result }
        do {
            try await trustProvider.grantTrust(to: identity)
            return .accepted
        } catch {
            DeckHandLog.trust.error("Pairing failed: \(error.localizedDescription, privacy: .public)")
            return .noActiveCode
        }
    }

    /// A code sent while the device's request is pending (from its
    /// `PreApprovalGate`). Right code: paired and granted at once.
    func handlePendingCode(_ code: String, connectionID: UUID) async {
        guard let pending = pendingConnections.first(where: { $0.id == connectionID }),
              let handle = pendingHandles[connectionID] else {
            DeckHandLog.trust.info("🔐 Ignoring a pairing code from conn=\(connectionID, privacy: .public): not pending")
            return
        }
        let result = await verifyCode(code, connectionID: connectionID)
        try? await handle.send(.pairing(.codeResult(result: result)))
        if result == .accepted {
            authorize(connection: pending)
        }
    }

    /// A code sent by a device already allowed for this session (to pair
    /// it for next time). Answered by `PairingHandler`.
    func handleSubmittedCode(_ code: String, from handle: LoomConnectionHandle) async {
        let result = await verifyCode(code, connectionID: handle.id)
        do {
            try await handle.send(.pairing(.codeResult(result: result)))
            if result == .accepted {
                try await handle.send(.pairing(.pairedStatus(paired: true)))
            }
        } catch {
            DeckHandLog.trust.error("Failed to answer a pairing code: \(error.localizedDescription, privacy: .public)")
        }
        refreshLiveRefs()
    }

    /// Whether the device on `connectionID` is on the paired list.
    func isPaired(connectionID: UUID) -> Bool {
        guard let ref = identities[connectionID]?.ref else { return false }
        return store.isPaired(ref)
    }

    // MARK: - Forget (S4)

    /// "Forget" in the menu bar: unpairs the device and ends its live
    /// sessions. It gets the Allow prompt (or pairs again) next time.
    func forget(_ ref: PairedDeviceRef) {
        store.forget(ref)
        sessionApprovedRefs.remove(ref)
        for (connectionID, candidate) in identities where candidate.ref == ref {
            endSession(connectionID, reason: "forgotten on the Mac")
        }
        refreshLiveRefs()
    }

    /// The remote's "Forget this Mac" (`pairing.forget`).
    func remoteAskedToForget(_ handle: LoomConnectionHandle) {
        guard let ref = identities[handle.id]?.ref else {
            endSession(handle.id, reason: "forget from an unidentified connection")
            return
        }
        let name = identities[handle.id]?.name ?? "A remote"
        DeckHandLog.trust.info("🔐 \(name, privacy: .public) asked this Mac to forget it")
        forget(ref)
    }

    /// Stops a live session: no more of its messages run, the remote hears
    /// it is no longer paired, then the connection closes.
    private func endSession(_ connectionID: UUID, reason: String) {
        guard let handle = liveHandles.removeValue(forKey: connectionID) else { return }
        onConnectionRevoked?(connectionID)
        if let peerID = livePeerIDs.removeValue(forKey: connectionID),
           !livePeerIDs.values.contains(peerID) {
            authorizedDeviceIDs.remove(peerID)
        }
        DeckHandLog.trust.info("🔐 Ending session conn=\(connectionID, privacy: .public): \(reason, privacy: .public)")
        Task {
            try? await handle.send(.pairing(.pairedStatus(paired: false)))
            try? await Task.sleep(nanoseconds: 100_000_000)
            await handle.disconnect()
        }
    }

    /// Drops what the Mac knew about a connection that is gone.
    private func forgetConnection(_ connectionID: UUID) {
        identities.removeValue(forKey: connectionID)
        rawIdentities.removeValue(forKey: connectionID)
        liveHandles.removeValue(forKey: connectionID)
        if let peerID = livePeerIDs.removeValue(forKey: connectionID),
           !livePeerIDs.values.contains(peerID) {
            authorizedDeviceIDs.remove(peerID)
        }
        refreshLiveRefs()
    }

    private func refreshLiveRefs() {
        let refs = Set(liveHandles.keys.compactMap { identities[$0]?.ref })
        if refs != liveRefs { liveRefs = refs }
    }

    func reject(connection: LoomConnectionSnapshot, loomContext: LoomContext) {
        removePendingConnection(id: connection.id)
        forgetConnection(connection.id)
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
            // This launch's Allow ends too; a paired device stays paired
            // (Forget it in the paired list to require approval again).
            if let ref = identities[peerConnection.id]?.ref {
                sessionApprovedRefs.remove(ref)
            }
            // Stop dispatching this device's commands BEFORE tearing down
            // the transport — otherwise buffered input keeps executing
            // during the (async) disconnect.
            onConnectionRevoked?(peerConnection.id)
            removePendingConnection(id: peerConnection.id)
            pendingHandles.removeValue(forKey: peerConnection.id)
            forgetConnection(peerConnection.id)
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
        forgetConnection(dismissal.id)
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
        // Allowed sessions that ended without a dismissal.
        for id in Set(identities.keys).union(liveHandles.keys)
        where !activeConnectionIDs.contains(id) && gates[id] == nil {
            forgetConnection(id)
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
