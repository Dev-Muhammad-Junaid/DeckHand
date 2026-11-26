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
import PixelHandCore
import SwiftUI
import UIKit

struct ContentRootView: View {
    @Environment(\.loomContext) private var loomContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var settings: DeckHandSettings
    @LoomQuery(.peers(sort: .name)) private var discoveredPeers: [LoomPeerSnapshot]
    /// Only Macs: other iPads and iPhones running Pixel Hand advertise the
    /// same service (build 19, `PeerRole`).
    private var peers: [LoomPeerSnapshot] { discoveredPeers.macsOnly }
    @State private var activeConnection: (handle: LoomConnectionHandle, peerName: String)?
    @State private var authStatus: String = "pending"
    /// Keeps the approval card up for a moment after a grant, so the hand
    /// can turn into the check while the controls brighten behind it.
    @State private var isShowingApproval = false
    /// When the current wait for approval began. A grant that arrives faster
    /// than a person could click (the user's own iCloud Macs) skips the
    /// check rather than adding a pause.
    @State private var pendingSince = Date()
    /// `LoomContext.start()`, single-flight (build 22): launch and every
    /// Try again go through it, so a Try again during a slow first start
    /// joins that start instead of racing it ("Already advertising
    /// service", then `CancellationError`). Its failure message replaces
    /// "Searching" in the picker, with Retry.
    @State private var startGate = NetworkStartGate()
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

                    // While reconnecting on its own, only the toast says so;
                    // the card comes once the retries give up (VQ-027).
                    if (lossMode == .card && !showsSwitchGrace) || isShowingApproval {
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
                    startError: startGate.failureMessage,
                    onRetryStart: { requestLoomStart() }
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
        .task { requestLoomStart() }
    }

    /// Launch and Try again. Starts Loom at most once at a time: the start
    /// runs in its own task, so neither a second request nor this view's
    /// task ending cancels it; a request while it runs only waits, and one
    /// once it's running refreshes discovery.
    private func requestLoomStart() {
        let action = withAnimation(.easeInOut(duration: 0.22)) { startGate.request() }
        switch action {
        case let .start(attempt):
            DeckHandLog.app.info("Starting LoomContext (attempt \(attempt, privacy: .public))")
            let context = loomContext
            Task { @MainActor in
                do {
                    try await context.start()
                    guard startGate.finished(attempt: attempt, error: nil) else { return }
                    switcher.start(context: context)
                    switcher.update(peers: peers)
                    DeckHandLog.app.info("LoomContext started")
                } catch {
                    DeckHandLog.app.fault("LoomContext start failed: \(error.localizedDescription, privacy: .public)")
                    _ = withAnimation(.easeInOut(duration: 0.22)) {
                        startGate.finished(attempt: attempt, error: error.localizedDescription)
                    }
                }
            }
        case let .join(attempt):
            DeckHandLog.app.info("Try again: LoomContext start (attempt \(attempt, privacy: .public)) is still running; waiting for it")
        case .refresh:
            DeckHandLog.app.info("Try again: LoomContext is running; refreshing peers")
            let context = loomContext
            Task { await context.refreshPeers() }
        }
    }

    private var lossMode: ConnectionLossPresentation.Mode {
        ConnectionLossPresentation.mode(
            status: authStatus,
            isReconnecting: switcher.reconnectingDeviceID != nil && switcher.reconnectingDeviceID == activeConnection?.handle.peer.deviceID
        )
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
    /// Sits below the shell's header so it never covers the Mac pill
    /// (VQ-028); the pixel is unlit while no Mac is talking; a dial or a
    /// reconnect can be cancelled (VQ-058).
    @ViewBuilder
    private var switchToast: some View {
        let listings = switcher.listings
        let dialing = switcher.machine.dialingDeviceID.flatMap { id in listings.first { $0.deviceID == id } }
        let reconnecting = switcher.reconnectingDeviceID.flatMap { id in listings.first { $0.deviceID == id } }
        // VQ-101: the launch reconnect waiting for Loom to start (7–15 s
        // after a cold boot) says so too, instead of a bare "Paired · Nearby".
        let waiting = switcher.pendingLaunchDeviceID.flatMap { id in listings.first { $0.deviceID == id } }
        Group {
            if let notice = switcher.notice {
                PHToast(message: notice, isFailure: true)
                    .allowsHitTesting(false)
            } else if let reconnecting {
                cancellableToast("Reconnecting to \(reconnecting.name)…")
            } else if let dialing {
                cancellableToast(MacReconnectPolicy.connectingLine(macName: dialing.name))
            } else if let waiting {
                cancellableToast(MacReconnectPolicy.connectingLine(macName: waiting.name))
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.xl)
        // VQ-107: on the picker the toast sits under Pair and Settings, not
        // over them.
        .padding(.top, CGFloat(ConnectToastPlan.topInset(
            hasSession: activeConnection != nil,
            headerClearance: Double(Self.headerClearance)
        )))
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: switcher.notice)
        .animation(.easeOut(duration: 0.2), value: dialing?.deviceID)
        .animation(.easeOut(duration: 0.2), value: reconnecting?.deviceID)
        .animation(.easeOut(duration: 0.2), value: waiting?.deviceID)
    }

    /// Room for the shell's header row above the toast.
    private static let headerClearance: CGFloat = PixelHandTheme.ControlHeight.standard + PixelHandTheme.Space.xl

    /// The toast and its Cancel. In a row when that fits; at the
    /// accessibility sizes, or when the row doesn't fit, the text gets the
    /// full width and wraps at words, with Cancel under it (VQ-107: at AX3
    /// the row squeezed it to "Con- / necti…").
    @ViewBuilder
    private func cancellableToast(_ message: String) -> some View {
        let inline = HStack(spacing: PixelHandTheme.Space.sm) {
            connectToast(message, arrangement: .inline)
                .layoutPriority(1)
            connectCancel
                .fixedSize()
        }
        let stacked = VStack(spacing: PixelHandTheme.Space.sm) {
            connectToast(message, arrangement: .stacked)
            connectCancel
        }
        .frame(maxWidth: 480)
        switch ConnectToastPlan.arrangement(band: typeSize.typeBand) {
        case .stacked:
            stacked
        case .inline:
            ViewThatFits(in: .horizontal) {
                inline
                stacked
            }
        }
    }

    private func connectToast(_ message: String, arrangement: ConnectToastPlan.Arrangement) -> some View {
        PHToast(message: message, pixel: .off, lineLimit: ConnectToastPlan.lineLimit(arrangement))
            // Build 28 (`test04`): one element, the whole toast, so the
            // identifier names the toast and not its 8 pt status dot.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ph.connect.toast")
    }

    private var connectCancel: some View {
        Button("Cancel") { switcher.cancelDial() }
            .buttonStyle(.ph(.secondary, size: .regular))
            .accessibilityIdentifier("ph.connect.cancel")
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
                ConnectionDiagnostics.shared.record("Disconnected from \(peerName)" + (reason.map { ": \($0)" } ?? ""))
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
