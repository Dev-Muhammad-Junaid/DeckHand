//
//  PixelHandShell.swift
//  DeckHandiOS – Shell
//
//  The Pixel Hand control surface (UX-003, Option A "Dock & Canvas"): header,
//  status pills, one canvas, and the glass tab bar with Ask. The canvas
//  reads `LayoutMetrics` from its own size (never the device idiom) and
//  picks an arrangement:
//
//    single   compact widths            one surface, tab bar at the bottom
//    rail     short, not compact        one surface, tab rail on the leading edge
//    split    medium and tall           one surface, tab bar (panes: UX-007)
//    columns  wide and tall             centre surface + the deck column (336 pt)
//
//  The shell hosts today's surfaces as they are (`TrackpadView`,
//  `StreamDeckGridView`, the mirror lane's `MirrorOverlay`); other lanes
//  restyle them. The selected surface is scene storage, so it survives
//  rotation, Split View, Stage Manager resizes and scene restoration.
//  `ControlView` owns the session and the sheets; this view only reads.
//

import SwiftUI

struct PixelHandShell: View {
    let session: ControlSessionModel
    let peerName: String
    /// The approval state the root view shows, after timeout mapping.
    let authStatus: String
    let onSettings: () -> Void
    let onClassicLayout: () -> Void
    let onDisconnect: () -> Void

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("pixelhand.shell.surface") private var surfaceRawValue = ControlSurface.pointer.rawValue
    @State private var isAskPresented = false

    private var selection: Binding<ControlSurface> {
        Binding(
            get: { ControlSurface(rawValue: surfaceRawValue) ?? .pointer },
            set: { surfaceRawValue = $0.rawValue }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(width: proxy.size.width, height: proxy.size.height)
            let arrangement = metrics.arrangement
            let centre = selection.wrappedValue.centre(in: arrangement)

            ZStack {
                PixelHandTheme.canvas.ignoresSafeArea()

                if arrangement == .rail {
                    HStack(spacing: 0) {
                        SurfaceTabBar(
                            selection: selection,
                            tabs: ControlSurface.tabs(for: arrangement),
                            axis: .vertical,
                            onAsk: { isAskPresented = true }
                        )
                        .padding(.leading, PixelHandTheme.Space.sm)
                        .frame(maxHeight: .infinity)
                        mainColumn(metrics: metrics, arrangement: arrangement, centre: centre)
                    }
                } else {
                    mainColumn(metrics: metrics, arrangement: arrangement, centre: centre)
                        .safeAreaInset(edge: .bottom, spacing: PixelHandTheme.Space.sm) {
                            SurfaceTabBar(
                                selection: selection,
                                tabs: ControlSurface.tabs(for: arrangement),
                                onAsk: { isAskPresented = true }
                            )
                            .padding(.horizontal, metrics.margin)
                            .frame(maxWidth: arrangement == .columns ? 420 : .infinity)
                        }
                }
            }
            .animation(PixelHandMotion.reduced(PixelHandMotion.spring, reduceMotion: reduceMotion), value: arrangement)
        }
        .sheet(isPresented: $isAskPresented) {
            AskPlaceholderSheet(macName: peerName)
        }
    }

    // MARK: Columns

    @ViewBuilder
    private func mainColumn(metrics: LayoutMetrics, arrangement: LayoutMetrics.Arrangement, centre: ControlSurface) -> some View {
        VStack(spacing: PixelHandTheme.Space.xs) {
            header
            statusPills
                .padding(.horizontal, metrics.margin)
            if arrangement == .columns {
                HStack(spacing: PixelHandTheme.Space.md) {
                    canvas(centre: centre, metrics: metrics)
                    deckColumn
                        .frame(width: LayoutMetrics.deckColumnWidth)
                }
                .padding(.trailing, metrics.margin)
            } else {
                canvas(centre: centre, metrics: metrics)
            }
        }
    }

    private var header: some View {
        ShellHeader(
            peerName: peerName,
            subtitle: ApprovalStatusCopy.headerSubtitle(status: authStatus, activeAppName: session.activeAppName),
            isLive: ApprovalStatusCopy.showsLiveIndicator(status: authStatus),
            isLocked: session.macLockState.bannerText(macName: peerName) != nil,
            link: RemoteLinkStatus.shared.current,
            isMirrorActive: session.isMirrorActive,
            isCaptureBusy: session.capture.isRequestingScreenshot,
            onToggleMirror: { session.toggleMirror(settings: settings) },
            onFullScreen: { session.capture.beginCapture(intent: .fullScreen, mode: .fullScreen, quality: settings.screenshotQuality) },
            onRegion: { session.capture.beginCapture(intent: .regionPicking, mode: .fullScreen, quality: settings.screenshotQuality) },
            onWindow: { session.capture.openWindowPicker() },
            onOCR: { session.capture.beginCapture(intent: .ocr, mode: .fullScreen, quality: settings.screenshotQuality) },
            onPrimaryCapture: { session.capture.beginDefaultCapture(settings: settings) },
            onSettings: onSettings,
            onClassicLayout: onClassicLayout,
            onDisconnect: onDisconnect
        )
    }

    /// Host permission and lock warnings: the Mac reports what it can do, so
    /// a missing permission shows here instead of taps failing silently.
    @ViewBuilder
    private var statusPills: some View {
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
        .transition(.opacity)
    }

    // MARK: Canvas

    @ViewBuilder
    private func canvas(centre: ControlSurface, metrics: LayoutMetrics) -> some View {
        ZStack {
            if let sender = session.sender {
                surfaceView(centre, sender: sender, metrics: metrics)
                    .id(centre)
                    .transition(.opacity)
            } else {
                PixelSurface {
                    VStack(spacing: PixelHandTheme.Space.lg) {
                        DotWave(label: "Connecting to \(peerName)")
                        DotMatrixText("CONNECTING", pitch: 1.6, label: "Connecting")
                            .foregroundStyle(PixelHandTheme.Brand.phosphor)
                    }
                }
                .padding(.horizontal, metrics.margin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion), value: centre)
        // The floating screen tile on Pointer and Deck (the Screen surface
        // docks it in its own pane).
        .overlay {
            GeometryReader { proxy in
                if session.isMirrorActive && centre != .screen {
                    MirrorOverlay(session: session, containerSize: proxy.size)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: session.isMirrorActive)
    }

    @ViewBuilder
    private func surfaceView(_ surface: ControlSurface, sender: TrackpadSender, metrics: LayoutMetrics) -> some View {
        switch surface {
        case .pointer:
            PointerSurface(sender: sender, clipboard: session.clipboard, margin: metrics.margin)
        case .screen:
            ScreenSurface(session: session, macName: peerName)
                .padding(.horizontal, metrics.margin)
                .padding(.bottom, PixelHandTheme.Space.sm)
        case .deck:
            deck(sender: sender)
        }
    }

    @ViewBuilder
    private var deckColumn: some View {
        if let sender = session.sender {
            deck(sender: sender)
                .background(PixelHandTheme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
        }
    }

    private func deck(sender: TrackpadSender) -> some View {
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
