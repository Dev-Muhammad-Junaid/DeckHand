//
//  ShellHeader.swift
//  DeckHandiOS – Shell
//
//  The control surface's header (56 pt): the Mac pill with its link badge,
//  then glass circles for the floating screen, capture and More. Disconnect
//  lives in More, away from the primary actions; the session id is no
//  longer shown. Board: `.hdr2`. (UX-003 shell, the basis of UX-008.)
//
//  On iPad (UX-007) the header also carries the layout presets, and on
//  wide windows the Ask field (⌘K) between them and capture, and the
//  sidebar button while the Macs sidebar is hidden. In the iPhone
//  landscape rail it sits on top of the deck column without padding or the
//  screen button (the rail has the Screen tab).
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
    /// Tap on the Mac pill: My Macs. Swiping the pill sideways will switch
    /// Macs in 1.3; until then the swipe nudges the pill and opens My Macs.
    let onMacs: () -> Void
    let onSettings: () -> Void
    let onClassicLayout: () -> Void
    let onDisconnect: () -> Void
    /// iPad: the layout presets (UX-007).
    var presets: Binding<LayoutPreset>?
    /// Wide: Ask as a field in the header (a circle when the row is tight).
    var onAsk: (() -> Void)?
    /// Wide, sidebar hidden: the button that shows it again.
    var onShowSidebar: (() -> Void)?
    var showsMirrorToggle = true
    var horizontalPadding: CGFloat = PixelHandTheme.Space.lg

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            MacPill(
                name: peerName,
                subtitle: subtitle,
                status: isLocked ? .locked : (isLive ? .online : .offline),
                action: onMacs
            )
            .accessibilityHint("Shows My Macs.")
            .offset(x: swipeOffset)
            .simultaneousGesture(pillSwipe)
            .layoutPriority(1)
            if let badge = linkBadge {
                LinkBadge(kind: badge)
            }
            if let onAsk {
                if let presets {
                    LayoutPresetPicker(selection: presets)
                }
                ViewThatFits(in: .horizontal) {
                    AskField(macName: peerName, action: onAsk)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        AskCircleButton(size: PixelHandTheme.ControlHeight.standard, action: onAsk)
                    }
                }
            } else {
                Spacer(minLength: 0)
                if let presets {
                    LayoutPresetPicker(selection: presets)
                }
            }
            if showsMirrorToggle {
                GlassCircleButton(
                    glyph: PixelGlyphs.pictureInPicture,
                    label: isMirrorActive ? "Hide the Mac’s screen" : "Show the Mac’s screen",
                    isOn: isMirrorActive,
                    action: onToggleMirror
                )
                .requiresPro(.mirror)
            }
            captureMenu
            if let onShowSidebar {
                GlassCircleButton(glyph: PixelGlyphs.sidebar, label: "Show the Macs sidebar", action: onShowSidebar)
            }
            moreMenu
        }
        .padding(.horizontal, horizontalPadding)
        .frame(minHeight: PixelHandTheme.ControlHeight.dock)
        .phGlassGroup()
    }

    /// The pill swipe placeholder (UX-008): follows the finger a little
    /// with resistance, springs back, and opens My Macs past 40 pt.
    private var pillSwipe: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                swipeOffset = reduceMotion ? 0 : max(-24, min(24, value.translation.width * 0.25))
            }
            .onEnded { value in
                withAnimation(PixelHandMotion.reduced(PixelHandMotion.spring, reduceMotion: reduceMotion)) {
                    swipeOffset = 0
                }
                if abs(value.translation.width) > 40, abs(value.translation.width) > abs(value.translation.height) {
                    GestureHaptic.selection.trigger()
                    onMacs()
                }
            }
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
