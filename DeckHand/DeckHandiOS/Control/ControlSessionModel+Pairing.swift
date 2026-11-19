//
//  ControlSessionModel+Pairing.swift
//  DeckHandiOS
//
//  The pairing lane's part of the session model:
//
//  - Approval status from the Mac, and the resync poll that heals a lost
//    `granted` push.
//  - The Mac's verified identity (Loom handshake), registered with
//    `PairedMacsStore` so the approval card and Settings can pair or forget
//    without holding this model.
//  - A QR invite scanned in the picker: sent once this session reaches the
//    approval step, and only if this Mac proved the identity key in the QR
//    code.
//  - `pairedStatus`: keeps the paired-Mac list in step with the Mac; a
//    "not paired" after "paired" means the Mac forgot this device, and the
//    card says so. A forget held from Settings goes out here.
//
//  `stopPairing()` (deferred by `run`) cancels everything with the view.
//

import Foundation
import LoomKit

extension ControlSessionModel {

    func startPairing(sender s: TrackpadSender) {
        let connection = self.connection
        let store = PairedMacsStore.shared
        let token = store.beginSession { message in
            do {
                try await connection.send(.pairing(message))
                return true
            } catch {
                DeckHandLog.connection.error("Pairing send failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        pairingSessionToken = token
        pairedThisSession = false

        pairingTasks = [
            // The Mac's identity as Loom verified it.
            Task { [weak self] in
                let mac = await connection.pairingCandidate()
                guard let self, !Task.isCancelled else { return }
                self.pairingMac = mac
                store.identified(mac: mac, token: token)
                if mac == nil {
                    DeckHandLog.connection.error("🔐 The Mac's identity key wasn't verified; pairing is off for this session")
                }
                self.sendPendingInviteIfReady()
            },
            // ── Authorization resync poll ───────────────────────────
            // The host pushes `authorizationStatus`, and the handle's
            // message stream buffers, so the normal path never loses it.
            // But the push itself is a network send that can fail — and a
            // lost `granted` would strand this view on the approval
            // overlay while the Mac thinks the session is live. Poll
            // until a DECISIVE status (granted/denied) arrives — NOT the
            // initial "pending" the host emits before the user decides.
            // Queries sent while we're still pending are kept by the
            // host's pre-approval gate and answered "granted" the moment
            // approval lands, healing any dropped push. Bounded at 20
            // attempts (~60 s, past the host's 45 s pending expiry) so the
            // loop always terminates even if the view outlives a dead
            // connection.
            Task { [weak self] in
                for _ in 0..<20 {
                    guard let self, !self.hasReceivedAuthStatus, !Task.isCancelled else { break }
                    await s.requestAuthorizationStatus()
                    try? await Task.sleep(for: .seconds(3))
                }
            },
        ]
    }

    func stopPairing() {
        pairingTasks.forEach { $0.cancel() }
        pairingTasks = []
        if let token = pairingSessionToken {
            PairedMacsStore.shared.endSession(token: token)
        }
        pairingSessionToken = nil
    }

    // MARK: - Messages

    func handleAuthorizationStatus(_ state: AuthState) {
        // The UI keeps string states because it adds local ones
        // ("timed_out", "host_disconnected", "forgotten"); see
        // ApprovalStatusCopy.
        let status = state.rawValue
        // Always-on so the pending→granted/denied transition is visible in
        // Console.app for release/TestFlight, not just Xcode-attached
        // DEBUG. `decisive` mirrors the resync-poll gate.
        DeckHandLog.connection.info("🔑 iPad authorizationStatus = \(status, privacy: .public) (decisive=\(status != "pending"))")
        // Only a DECISIVE verdict disarms the resync poll. The host pushes
        // "pending" the instant the connection lands (before the user has
        // decided); treating that as "heard back" used to stop the poll
        // immediately, so if the later "granted" push was dropped on the
        // wire the iPad sat on the approval overlay forever.
        let isFirstGrant = status == "granted" && lastAuthStatus != "granted"
        if status != "pending" {
            hasReceivedAuthStatus = true
        }
        // A forgotten session stays forgotten until the connection ends.
        guard lastAuthStatus != ApprovalStatusCopy.forgottenStatus else { return }
        lastAuthStatus = status
        onAuthStatusChanged(status)
        // The host's pre-approval gate drops everything sent before Allow,
        // including the app-list request made when this view appeared. Ask
        // again once access is granted.
        if isFirstGrant, let sender {
            Task { await sender.requestAppList() }
        }
        sendPendingInviteIfReady()
    }

    func handleCodeResult(_ result: PairingCodeResult) {
        DeckHandLog.connection.info("🔐 Pairing code result: \(String(describing: result), privacy: .public)")
        PairedMacsStore.shared.received(result)
    }

    func handlePairedStatus(_ paired: Bool) {
        let store = PairedMacsStore.shared
        let action = store.macReported(paired: paired)
        if action == .sendForget {
            // Forgotten in Settings while this Mac was away: tell it now.
            // It answers "not paired" and ends the session.
            DeckHandLog.connection.info("🔐 Sending a held Forget to the Mac")
            let connection = self.connection
            Task { try? await connection.send(.pairing(.forget)) }
        }
        if paired {
            pairedThisSession = true
        } else if pairedThisSession {
            pairedThisSession = false
            DeckHandLog.connection.info("🔐 The Mac no longer has this device paired; the session ends")
            lastAuthStatus = ApprovalStatusCopy.forgottenStatus
            onAuthStatusChanged(ApprovalStatusCopy.forgottenStatus)
        }
    }

    // MARK: - QR invite

    /// Sends the code from a QR invite scanned in the picker, once this is
    /// the invite's Mac, its identity is verified, and the Mac has answered
    /// (pending or granted), so the code reaches its pairing logic.
    func sendPendingInviteIfReady() {
        let store = PairedMacsStore.shared
        guard let invite = store.pendingInvite,
              let mac = pairingMac,
              lastAuthStatus == "pending" || lastAuthStatus == "granted" else { return }
        store.pendingInvite = nil
        guard invite.macDeviceID == mac.deviceID else {
            DeckHandLog.connection.info("🔐 Dropping a QR invite for another Mac")
            return
        }
        guard invite.macIdentityKeyID == mac.identityKeyID else {
            DeckHandLog.connection.error("🔐 QR invite key doesn't match this Mac's verified key; not sending the code")
            store.notice = "This Mac isn’t the one that showed the QR code. Its code wasn’t sent."
            return
        }
        Task { await store.submit(invite.code) }
    }
}
