//
//  ControlView.swift
//  DeckHandiOS
//
//  The control screen for one connected Mac. Owns the session, the sheets
//  and the session's lifetime, and shows either the Pixel Hand shell
//  (`Shell/PixelHandShell.swift`, the default) or the classic layout (tabs,
//  floating mirror, navigation toolbar), switched from each one's menu.
//  Connection state and the message loop live in `ControlSessionModel`
//  (Control/), captures in `CaptureCoordinator`.
//

import LoomKit
import SwiftUI

struct ControlView: View {
    let connection: LoomConnectionHandle
    let peerName: String
    /// The approval state the root view shows, after timeout mapping.
    let authStatus: String
    let onAuthStatusChanged: (String) -> Void
    let onDisconnect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: DeckHandSettings
    @State private var selectedTab: Tab = .trackpad
    @State private var isSettingsPresented = false
    @State private var session: ControlSessionModel
    /// The redesign's shell is the default; the classic layout stays one
    /// tap away while the other lanes restyle their surfaces.
    @AppStorage("pixelhand.usesPixelHandShell") private var usesPixelHandShell = true

    init(
        connection: LoomConnectionHandle,
        peerName: String,
        authStatus: String,
        onAuthStatusChanged: @escaping (String) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self.connection = connection
        self.peerName = peerName
        self.authStatus = authStatus
        self.onAuthStatusChanged = onAuthStatusChanged
        self.onDisconnect = onDisconnect
        _session = State(initialValue: ControlSessionModel(
            connection: connection,
            onAuthStatusChanged: onAuthStatusChanged
        ))
    }

    enum Tab: String, CaseIterable {
        case trackpad   = "Trackpad"
        case streamdeck = "Apps"

        var icon: String {
            switch self {
            case .trackpad:   "hand.draw"
            case .streamdeck: "square.grid.3x2"
            }
        }
    }

    private var hasStatusPills: Bool {
        session.hostAccessibilityGranted == false
            || session.macLockState.bannerText(macName: peerName) != nil
            || session.hostScreenRecordingGranted == false
    }

    var body: some View {
        Group {
            if usesPixelHandShell {
                PixelHandShell(
                    session: session,
                    peerName: peerName,
                    authStatus: authStatus,
                    onSettings: { isSettingsPresented = true },
                    onClassicLayout: { usesPixelHandShell = false },
                    onDisconnect: onDisconnect
                )
            } else {
                classicLayout
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        // Mirror settings only take effect on the next stream, so a change
        // made while the mirror is up has to restart it.
        .onChange(of: settings.mirrorSharpness) { session.renegotiateMirror(settings: settings) }
        .onChange(of: settings.mirrorFrameRate) { session.renegotiateMirror(settings: settings) }
        .onChange(of: settings.inputSendRate) { _, rate in
            Task { await session.sender?.setSendRate(hz: rate.rawValue) }
        }
        .modifier(ControlCaptureSheets(capture: session.capture, runningBundleIDs: session.runningBundleIDs))
        .task {
            await session.run(settings: settings)
        }
        .intentBridge(session: session, settings: settings, macID: connection.peer.deviceID, macName: peerName) // Intents lane
    }

    // MARK: - Classic layout

    private var classicLayout: some View {
        NavigationStack {
            ZStack {
                DeckHandTheme.canvasBackground(colorScheme).ignoresSafeArea()

                if let sender = session.sender {
                    VStack(spacing: 0) {
                        // Host-permission warnings: the host reports what it
                        // can execute; missing permissions show here instead
                        // of taps failing silently.
                        VStack(spacing: PixelHandTheme.Space.sm) {
                            if session.hostAccessibilityGranted == false {
                                StatusPill(
                                    title: "\(peerName) needs Accessibility.",
                                    message: "Mouse, keyboard and shortcuts won’t work until you allow it in Pixel Hand’s menu on the Mac."
                                )
                            }
                            if let lockText = session.macLockState.bannerText(macName: peerName) {
                                StatusPill(kind: .locked, message: lockText)
                            }
                            if session.hostScreenRecordingGranted == false {
                                StatusPill(
                                    title: "\(peerName) needs Screen Recording.",
                                    message: "Screenshots and the live screen won’t work until you allow it on the Mac."
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, hasStatusPills ? PixelHandTheme.Space.sm : 0)
                        .transition(.opacity)

                        tabSwitcher
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        Divider().overlay(DeckHandTheme.navDivider(colorScheme))

                        Group {
                            switch selectedTab {
                            case .trackpad:
                                TrackpadView(sender: sender, colorScheme: colorScheme, clipboard: session.clipboard)
                            case .streamdeck:
                                StreamDeckGridView(
                                    sender: sender,
                                    colorScheme: colorScheme,
                                    installedApps: session.installedApps,
                                    activeBundleID: session.activeBundleID,
                                    runningBundleIDs: session.runningBundleIDs,
                                    uiContext: session.uiContext
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.18), value: selectedTab)
                    }
                } else {
                    DeckHandLoadingStateView(
                        title: "Initializing…",
                        verticalPadding: 48
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // Floating live-mirror thumbnail (WID-403). Sits above both
            // tabs so the user can keep an eye on the Mac while driving
            // the trackpad or the shortcut deck.
            .overlay {
                // The reader supplies the space the mirror may occupy, which
                // is what bounds its pinch zoom and keeps it draggable only
                // to somewhere it can still be reached.
                GeometryReader { proxy in
                    if session.isMirrorActive {
                        // The mirror lane's wrapper: picture, pointer,
                        // display picker, badge and stats.
                        MirrorOverlay(session: session, containerSize: proxy.size)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomTrailing
                        )
                    }
                }
            }
            .animation(.snappy(duration: 0.2), value: session.isMirrorActive)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ControlToolbar(
                    peerName: peerName,
                    connectionID: connection.id,
                    authStatus: authStatus,
                    activeAppName: session.activeAppName,
                    isMirrorActive: session.isMirrorActive,
                    isCaptureBusy: session.capture.isRequestingScreenshot,
                    onToggleMirror: { session.toggleMirror(settings: settings) },
                    onFullScreen: { session.capture.beginCapture(intent: .fullScreen, mode: .fullScreen, quality: settings.screenshotQuality) },
                    onRegion: { session.capture.beginCapture(intent: .regionPicking, mode: .fullScreen, quality: settings.screenshotQuality) },
                    onWindow: { session.capture.openWindowPicker() },
                    onOCR: { session.capture.beginCapture(intent: .ocr, mode: .fullScreen, quality: settings.screenshotQuality) },
                    onPrimaryCapture: { session.capture.beginDefaultCapture(settings: settings) },
                    onSettings: { isSettingsPresented = true },
                    onNewLayout: { usesPixelHandShell = true },
                    onDisconnect: onDisconnect
                )
            }
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        Picker("View", selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .labelStyle(.titleAndIcon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
}
