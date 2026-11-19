//
//  ControlToolbar.swift
//  DeckHandiOS
//
//  The control screen's navigation bar: the Mac's name with the approval
//  subtitle, the mirror toggle, the capture capsule, Settings and
//  Disconnect.
//

import SwiftUI

struct ControlToolbar: ToolbarContent {
    let peerName: String
    let connectionID: UUID
    /// The approval state the root view shows, after timeout mapping.
    let authStatus: String
    let activeAppName: String?
    let isMirrorActive: Bool
    let isCaptureBusy: Bool
    let onToggleMirror: () -> Void
    let onFullScreen: () -> Void
    let onRegion: () -> Void
    let onWindow: () -> Void
    let onOCR: () -> Void
    let onPrimaryCapture: () -> Void
    let onSettings: () -> Void
    let onDisconnect: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                // Long Mac names ("Junaid's MacBook Pro (16-inch,
                // 2023)") overflow the principal toolbar slot —
                // middle truncation keeps both the owner and model.
                Text(peerName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    // The icon's mint pixel, breathing while connected.
                    if ApprovalStatusCopy.showsLiveIndicator(status: authStatus) {
                        LivePixel()
                    }
                    Text(ApprovalStatusCopy.headerSubtitle(status: authStatus, activeAppName: activeAppName))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RemoteLinkBadge() // Network lane (S13): "Wired" over a USB cable
                }
                // Surface the live connection id so the session can be
                // matched against the Mac and a silent session swap is
                // visible in the UI.
                Text("session \(connectionID.uuidString.prefix(8))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            // Live mini mirror toggle (WID-403).
            Button {
                onToggleMirror()
            } label: {
                Image(systemName: isMirrorActive
                      ? "rectangle.fill.on.rectangle.fill"
                      : "rectangle.on.rectangle")
            }
            .tint(isMirrorActive ? DeckHandTheme.mint : nil)
            .accessibilityLabel(isMirrorActive ? "Stop live mirror" : "Start live mirror")
        }
        ToolbarItem(placement: .topBarTrailing) {
            CaptureCapsule(
                isBusy: isCaptureBusy,
                onFullScreen: onFullScreen,
                onRegion: onRegion,
                onWindow: onWindow,
                onOCR: onOCR,
                onPrimary: onPrimaryCapture
            )
        }
        // `ToolbarSpacer` is iOS 26 SDK-only — compile-time gate it
        // (Xcode 26 / Swift 6.2) so the toolbar still builds on
        // Xcode 16; the spacer is purely cosmetic on older OSes.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        #endif
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onDisconnect) {
                Image(systemName: "minus.circle")
            }
            .tint(DeckHandTheme.danger)
            .accessibilityLabel("Disconnect")
        }
    }
}
