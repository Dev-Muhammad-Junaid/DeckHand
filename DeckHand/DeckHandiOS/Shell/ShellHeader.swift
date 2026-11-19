//
//  ShellHeader.swift
//  DeckHandiOS – Shell
//
//  The control surface's header (56 pt): the Mac pill with its link badge,
//  then glass circles for the floating screen, capture and More. Disconnect
//  lives in More, away from the primary actions; the session id is no
//  longer shown. Board: `.hdr2`. (UX-003 shell, the basis of UX-008.)
//

import SwiftUI

struct ShellHeader: View {
    let peerName: String
    let subtitle: String
    let isLive: Bool
    let isLocked: Bool
    let link: LinkKind?
    let isMirrorActive: Bool
    let isCaptureBusy: Bool
    let onToggleMirror: () -> Void
    let onFullScreen: () -> Void
    let onRegion: () -> Void
    let onWindow: () -> Void
    let onOCR: () -> Void
    let onPrimaryCapture: () -> Void
    let onSettings: () -> Void
    let onClassicLayout: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            MacPill(
                name: peerName,
                subtitle: subtitle,
                status: isLocked ? .locked : (isLive ? .online : .offline)
            )
            .layoutPriority(1)
            if let badge = linkBadge {
                LinkBadge(kind: badge)
            }
            Spacer(minLength: 0)
            GlassCircleButton(
                glyph: PixelGlyphs.pictureInPicture,
                label: isMirrorActive ? "Hide the Mac’s screen" : "Show the Mac’s screen",
                isOn: isMirrorActive,
                action: onToggleMirror
            )
            .requiresPro(.mirror)
            captureMenu
            moreMenu
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .frame(minHeight: PixelHandTheme.ControlHeight.dock)
        .phGlassGroup()
    }

    /// Quiet on plain Wi-Fi: only cable and VPN get a badge.
    private var linkBadge: LinkBadge.Kind? {
        switch link {
        case .wired, .ethernet: .wired
        case .tunnel: .vpn
        default: nil
        }
    }

    private var captureMenu: some View {
        Menu {
            Button("Full screen", action: onFullScreen)
            Button("Region", action: onRegion)
            Button("Window", action: onWindow)
            Button("Read text", action: onOCR)
        } label: {
            Group {
                if isCaptureBusy {
                    DotWave(pitch: 3, label: "Capturing")
                } else {
                    PHGlyph(glyph: PixelGlyphs.capture, pitch: PixelPitch.header)
                        .foregroundStyle(PixelHandTheme.ink)
                }
            }
            .frame(width: PixelHandTheme.ControlHeight.standard, height: PixelHandTheme.ControlHeight.standard)
            .phGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
        } primaryAction: {
            onPrimaryCapture()
        }
        .disabled(isCaptureBusy)
        .accessibilityLabel("Capture")
        .accessibilityHint("Takes a screenshot. Touch and hold for more options.")
        .requiresPro(.capture)
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            Button(action: onClassicLayout) {
                Label("Use the classic layout", systemImage: "rectangle.grid.1x2")
            }
            Divider()
            Button(role: .destructive, action: onDisconnect) {
                Label("Disconnect from \(peerName)", systemImage: "xmark.circle")
            }
        } label: {
            PHGlyph(glyph: PixelGlyphs.settings, pitch: PixelPitch.header)
                .foregroundStyle(PixelHandTheme.ink)
                .frame(width: PixelHandTheme.ControlHeight.standard, height: PixelHandTheme.ControlHeight.standard)
                .phGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }
}
