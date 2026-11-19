//
//  SessionHandler.swift
//  DeckHandMac
//
//  Domain: session. Heartbeats, the link judgement, the Mac's VPN
//  addresses (S15) and the host status report. Pongs are sent by
//  `HeartbeatResponder` as pings arrive, off the main actor, before the
//  message reaches this handler; keep-alive ticks are stamped and dropped
//  there and never get here. Owned by the network lane (S1, S13, S15).
//

import CoreGraphics
import Foundation
import LoomKit

@MainActor
final class SessionHandler: DomainHandler {
    private let injector = InputInjector.shared

    func handle(_ message: SessionMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case let .ping(seq):
            // The pong already went out from HeartbeatResponder as the ping
            // arrived, so main-actor work here can't delay it.
            // Judge the link once the session is live (idempotent): the
            // remote shows "Wired" when this Mac sees the USB cable.
            HostLinkMonitor.shared.monitor(connection)
            // Re-report capabilities every 5th ping (~10 s): if the user
            // grants/revokes a TCC permission mid-session the remote's
            // warning banner updates without reconnecting.
            if seq % 5 == 0 {
                await sendHostStatus(to: connection)
            }
            // S15: a paired remote learns this Mac's VPN addresses (first
            // ping, then only when they change; checked every 5th ping).
            if seq <= 1 || seq % 5 == 0 {
                let paired = DeviceAuthorizationManager.shared.isPaired(connectionID: connection.id)
                await RemoteAccessGate.reportHosts(to: connection, isPaired: paired)
            }

        case .tick:
            break // HeartbeatResponder drops ticks before the router

        case .pong, .hostStatus, .link, .remoteHosts:
            break // Mac → remote only
        }
    }

    /// Reports what this host can actually execute. Accessibility is read
    /// live (cheap); screen recording uses the preflight toggle — the
    /// PermissionsMonitor probe is authoritative for local UI, but for the
    /// remote's banner the toggle is a good-enough, allocation-free check.
    func sendHostStatus(to handle: LoomConnectionHandle) async {
        // Also says which optional protocol features this host speaks, so
        // the remote only asks for receipts from a host that sends them.
        // Repeated every 5th ping, so a lost one heals within ~10 s.
        try? await handle.send(.session(.hostStatus(status: HostStatus(
            accessibility: injector.isAccessibilityGranted,
            screenRecording: CGPreflightScreenCaptureAccess(),
            features: [.binaryMirrorStream, .commandReceipts]
        ))))
    }
}
