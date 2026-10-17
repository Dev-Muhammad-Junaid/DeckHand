//
//  ContentRootView.swift
//  DeckHandiOS
//

import LoomKit
import SwiftUI

struct ContentRootView: View {
    @Environment(\.loomContext) private var loomContext
    @EnvironmentObject private var settings: DeckHandSettings
    @State private var activeConnection: (handle: LoomConnectionHandle, peerName: String)?
    @State private var authStatus: String = "pending"
    /// Keeps the approval card up for a moment after a grant, so the hand
    /// can turn into the check while the controls brighten behind it.
    @State private var isShowingApproval = false
    /// When the current wait for approval began. A grant that arrives faster
    /// than a person could click (the user's own iCloud Macs) skips the
    /// check rather than adding a pause.
    @State private var pendingSince = Date()

    /// How long the check stays up before the card leaves.
    private static let approvalHold: Duration = .milliseconds(900)

    var body: some View {
        ZStack {
            main

            if !settings.hasCompletedOnboarding {
                OnboardingView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        settings.hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private var main: some View {
        Group {
            if let connection = activeConnection {
                ZStack {
                    ControlView(
                        connection: connection.handle,
                        peerName: connection.peerName,
                        onAuthStatusChanged: { status in
                            let isNewGrant = status == "granted" && authStatus == "pending"
                            if isNewGrant, Date().timeIntervalSince(pendingSince) > 0.6 {
                                isShowingApproval = true
                                Task { @MainActor in
                                    try? await Task.sleep(for: Self.approvalHold)
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        isShowingApproval = false
                                    }
                                }
                            }
                            // A grant brightens the controls on the slower
                            // reveal timing, in step with the check forming.
                            withAnimation(isNewGrant ? DeckHandMotion.reveal : .easeInOut(duration: 0.22)) {
                                authStatus = status
                            }
                        },
                        onDisconnect: {
                            DeckHandLog.connection.info("iPad disconnect (user/overlay) for \(connection.peerName, privacy: .public) conn=\(connection.handle.id, privacy: .public)")
                            Task { await connection.handle.disconnect() }
                            activeConnection = nil
                            authStatus = "pending"
                            isShowingApproval = false
                        }
                    )
                    .opacity(authStatus == "granted" ? 1 : 0.38)
                    .disabled(authStatus != "granted")

                    if authStatus != "granted" || isShowingApproval {
                        AuthorizationOverlay(
                            status: authStatus,
                            peerName: connection.peerName
                        ) {
                            Task { await connection.handle.disconnect() }
                            activeConnection = nil
                            authStatus = "pending"
                            isShowingApproval = false
                        }
                        .transition(.opacity)
                    }
                }
                .transition(.opacity)
                .task(id: connection.peerName) {
                    authStatus = "pending"
                    pendingSince = Date()
                    isShowingApproval = false

                    // Only listen for connection-level events (disconnect) here.
                    // All message-level handling is consolidated in ControlView
                    // to avoid competing async consumers on the same stream.
                    for await event in connection.handle.events {
                        if case let .disconnected(reason) = event {
                            DeckHandLog.connection.info("iPad handle disconnected for \(connection.peerName, privacy: .public) conn=\(connection.handle.id, privacy: .public) reason=\(reason ?? "nil", privacy: .public) — leaving ControlView")
                            await MainActor.run {
                                if authStatus != "denied" {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        authStatus = "host_disconnected"
                                    }
                                }
                            }
                            break
                        }
                    }
                }
            } else {
                PeerPickerView { handle, peerName in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        activeConnection = (handle, peerName)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: activeConnection != nil)
        .task {
            do {
                DeckHandLog.app.info("Starting LoomContext")
                try await loomContext.start()
                DeckHandLog.app.info("LoomContext started")
            } catch {
                DeckHandLog.app.fault("LoomContext start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
