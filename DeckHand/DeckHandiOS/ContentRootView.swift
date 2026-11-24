//
//  ContentRootView.swift
//  DeckHandiOS
//
//  The connection lifecycle: the picker until a Mac connects, then the
//  control view for the focused Mac. Several Macs (UX-030, backlog M1):
//  `MacSwitcher` dials the next Mac while this one keeps running, then
//  hands the new connection here; the canvas slides to it (240 ms, in the
//  list's direction) and the old connection closes after the slide. One
//  `ControlView`, so one session model and one message loop, per focused
//  connection. ⌘1–⌘4 and ⌘` work on every surface; quick reconnect (the
//  last Mac at launch, a dropped Mac with backoff) runs through the same
//  switcher.
//

import LoomKit
import SwiftUI
import UIKit

struct ContentRootView: View {
    @Environment(\.loomContext) private var loomContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: DeckHandSettings
    @LoomQuery(.peers(sort: .name)) private var peers: [LoomPeerSnapshot]
    @State private var activeConnection: (handle: LoomConnectionHandle, peerName: String)?
    @State private var authStatus: String = "pending"
    /// Keeps the approval card up for a moment after a grant, so the hand
    /// can turn into the check while the controls brighten behind it.
    @State private var isShowingApproval = false
    /// When the current wait for approval began. A grant that arrives faster
    /// than a person could click (the user's own iCloud Macs) skips the
    /// check rather than adding a pause.
    @State private var pendingSince = Date()
    /// Why `LoomContext.start()` failed, if it did. Without it the picker
    /// said "Looking for your Mac" forever although discovery never ran.
    @State private var loomStartError: String?
    /// Bumped by Retry to run the start task again.
    @State private var loomStartAttempt = 0
    /// The edge the next Mac slides in from; `nil` fades (first connect,
    /// reconnect).
    @State private var slideEdge: Edge?
    /// Right after a switch, a paired Mac allows this device within a beat:
    /// hold the approval card back so the slide isn't covered by it.
    @State private var isSwitchGrace = false

    private let switcher = MacSwitcher.shared

    /// How long the check stays up before the card leaves.
    private static let approvalHold: Duration = .milliseconds(900)
    /// The canvas slide between Macs (`03-Layout-Strategy.md`).
    private static let slide = Animation.easeInOut(duration: 0.24)

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
        .overlay(alignment: .top) { switchToast }
        .perMacMirrorSettings()
        .onAppear {
            switcher.thisDeviceKind = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
            switcher.onAdopt = { adoption in adopt(adoption) }
        }
        .onChange(of: peers, initial: true) { _, peers in
            switcher.update(peers: peers)
        }
        .onChange(of: settings.hasCompletedOnboarding) {
            switcher.update(peers: peers)
        }
    }

    private var main: some View {
        Group {
            if let connection = activeConnection {
                ZStack {
                    ControlView(
                        connection: connection.handle,
                        peerName: connection.peerName,
                        authStatus: authStatus,
                        onAuthStatusChanged: { wireStatus in
                            authStatusChanged(wireStatus)
                        },
                        onDisconnect: {
                            DeckHandLog.connection.info("iPad disconnect (user/overlay) for \(connection.peerName, privacy: .public) conn=\(connection.handle.id, privacy: .public)")
                            disconnect(connection.handle)
                        }
                    )
                    .opacity(authStatus == "granted" || showsSwitchGrace ? 1 : 0.38)
                    .disabled(authStatus != "granted")

                    if (authStatus != "granted" && !showsSwitchGrace) || isShowingApproval {
                        AuthorizationOverlay(
                            status: authStatus,
                            peerName: connection.peerName
                        ) {
                            disconnect(connection.handle)
                        }
                        .transition(.opacity)
                    }
                }
                .background { MacSwitchCommands() }
                .id(connection.handle.id)
                .transition(slideTransition)
                .task(id: connection.handle.id) {
                    await watch(connection.handle, peerName: connection.peerName)
                }
            } else {
                PeerPickerView(
                    startError: loomStartError,
                    onRetryStart: { loomStartAttempt += 1 }
                ) { handle, peerName in
                    switcher.adoptFromPicker(handle, name: peerName)
                    slideEdge = nil
                    withAnimation(.easeInOut(duration: 0.28)) {
                        activeConnection = (handle, peerName)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: activeConnection != nil)
        .task(id: loomStartAttempt) {
            do {
                DeckHandLog.app.info("Starting LoomContext (attempt \(loomStartAttempt + 1))")
                withAnimation(.easeInOut(duration: 0.22)) { loomStartError = nil }
                try await loomContext.start()
                switcher.start(context: loomContext)
                switcher.update(peers: peers)
                DeckHandLog.app.info("LoomContext started")
            } catch {
                DeckHandLog.app.fault("LoomContext start failed: \(error.localizedDescription, privacy: .public)")
                withAnimation(.easeInOut(duration: 0.22)) {
                    loomStartError = error.localizedDescription
                }
            }
        }
    }

    private var showsSwitchGrace: Bool {
        isSwitchGrace && authStatus == "pending"
    }

    private var slideTransition: AnyTransition {
        guard let slideEdge, !reduceMotion else { return .opacity }
        let opposite: Edge = slideEdge == .trailing ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: slideEdge), removal: .move(edge: opposite))
    }

    // MARK: - Switch toast

    /// "Connecting to Laptop…", "Reconnecting to Studio…", or why a switch
    /// couldn't start. Sheets and the sidebar show the same notice inline.
    @ViewBuilder
    private var switchToast: some View {
        let listings = switcher.listings
        let dialing = switcher.machine.dialingDeviceID.flatMap { id in listings.first { $0.deviceID == id } }
        let reconnecting = switcher.reconnectingDeviceID.flatMap { id in listings.first { $0.deviceID == id } }
        Group {
            if let notice = switcher.notice {
                PHToast(message: notice, isFailure: true)
            } else if let reconnecting {
                PHToast(message: "Reconnecting to \(reconnecting.name)…")
            } else if let dialing {
                PHToast(message: "Connecting to \(dialing.name)…")
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.xl)
        .padding(.top, PixelHandTheme.Space.sm)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        .animation(.easeOut(duration: 0.22), value: switcher.notice)
        .animation(.easeOut(duration: 0.22), value: dialing?.deviceID)
        .animation(.easeOut(duration: 0.22), value: reconnecting?.deviceID)
        .allowsHitTesting(false)
    }

    // MARK: - Lifecycle

    /// Moves to a session `MacSwitcher` connected: a switch slides, a
    /// reconnect or launch fades. The Mac switched away from is closed
    /// once the slide is over.
    private func adopt(_ adoption: MacSwitcher.Adoption) {
        let isSwitch = activeConnection != nil && adoption.release != nil
        // A reconnect replaces a dead connection the switcher no longer holds.
        let stale = adoption.release ?? activeConnection.map { $0.handle }.flatMap { $0.id == adoption.handle.id ? nil : $0 }
        slideEdge = isSwitch ? (adoption.direction == .forward ? .trailing : .leading) : nil
        Task { @MainActor in
            // Let the removed view pick up the new transition first.
            await Task.yield()
            isSwitchGrace = true
            withAnimation(isSwitch ? Self.slide : .easeInOut(duration: 0.28)) {
                authStatus = "pending"
                isShowingApproval = false
                activeConnection = (adoption.handle, adoption.name)
            }
            if let old = stale {
                try? await Task.sleep(for: .milliseconds(600))
                DeckHandLog.connection.info("📡 Closing the Mac switched away from conn=\(old.id, privacy: .public)")
                await old.disconnect()
            }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeInOut(duration: 0.22)) { isSwitchGrace = false }
        }
    }

    private func disconnect(_ handle: LoomConnectionHandle) {
        switcher.endedByUser()
        Task { await handle.disconnect() }
        slideEdge = nil
        activeConnection = nil
        authStatus = "pending"
        isShowingApproval = false
    }

    private func authStatusChanged(_ wireStatus: String) {
        // The Mac answers "denied" both when the user clicks Deny and when
        // its 45 s window runs out.
        let status = ApprovalStatusCopy.displayStatus(
            forWireStatus: wireStatus,
            pendingFor: Date().timeIntervalSince(pendingSince)
        )
        // A heartbeat loss after the verdict mustn't replace the reason the
        // connection ended.
        if status == "host_disconnected", ApprovalStatusCopy.isFinalVerdict(authStatus) {
            return
        }
        let isNewGrant = status == "granted" && authStatus == "pending"
        if isNewGrant, Date().timeIntervalSince(pendingSince) > 0.6, !isSwitchGrace {
            isShowingApproval = true
            Task { @MainActor in
                try? await Task.sleep(for: Self.approvalHold)
                withAnimation(.easeOut(duration: 0.3)) {
                    isShowingApproval = false
                }
            }
        }
        // A grant brightens the controls on the slower reveal timing, in
        // step with the check forming.
        withAnimation(isNewGrant ? DeckHandMotion.reveal : .easeInOut(duration: 0.22)) {
            authStatus = status
        }
        // The heartbeat gave up on the Mac: quick reconnect.
        if status == "host_disconnected", let handle = activeConnection?.handle {
            switcher.connectionDropped(handle, isVerdict: false)
        }
    }

    /// Connection-level events only (disconnect). All message-level
    /// handling is in the session model, so there is one reader of the
    /// message stream.
    private func watch(_ handle: LoomConnectionHandle, peerName: String) async {
        authStatus = "pending"
        pendingSince = Date()
        isShowingApproval = false

        for await event in handle.events {
            if case let .disconnected(reason) = event {
                DeckHandLog.connection.info("iPad handle disconnected for \(peerName, privacy: .public) conn=\(handle.id, privacy: .public) reason=\(reason ?? "nil", privacy: .public) — leaving ControlView")
                // A Mac switched away from closes after the new one is on
                // screen; its end isn't news.
                guard activeConnection?.handle.id == handle.id else { break }
                let isVerdict = ApprovalStatusCopy.isFinalVerdict(authStatus)
                if !isVerdict {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        authStatus = "host_disconnected"
                    }
                }
                switcher.connectionDropped(handle, isVerdict: isVerdict)
                break
            }
        }
    }
}
