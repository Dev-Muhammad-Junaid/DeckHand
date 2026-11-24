//
//  ShellHeader.swift
//  DeckHandiOS – Shell
//
//  The control surface's header (56 pt): the Mac pill with its link badge,
//  then glass circles for the floating screen, capture and More. Disconnect
//  lives in More, away from the primary actions; the session id is no
//  longer shown. Board: `.hdr2`. (UX-003 shell, the basis of UX-008.)
//
//  Build 18 QA: when the circles don't fit beside a readable Mac pill they
//  fold into More (`ShellHeaderPlan`: first all but capture, then capture
//  too; at the Huge type band always), the pill truncates its name at the
//  tail, and in a Stage Manager window the row starts after the window
//  controls. The classic layout is a DEBUG-only item.
//
//  On iPad (UX-007) the header also carries the layout presets, and on
//  wide windows the Ask field (⌘K) between them and capture, and the
//  sidebar button while the Macs sidebar is hidden. In the iPhone
//  landscape rail it sits on top of the deck column without padding or the
//  screen button (the rail has the Screen tab).
//

import PixelHandCore
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
    /// Tap on the Mac pill: My Macs. Swiping the pill sideways switches to
    /// the next or previous Mac (UX-030), or opens My Macs with no other.
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.entitlements) private var entitlements
    @State private var swipeOffset: CGFloat = 0
    /// The header's measured width, for `ShellHeaderPlan`.
    @State private var width: CGFloat = 0
    /// Stage Manager's window controls (iPadOS 26), measured by
    /// `WindowControlsInset`; the header starts after them (VQ-080).
    @State private var windowControlsInset: CGFloat = 0
    /// Bumped by More › Send and Inbox while the send circle is folded.
    @State private var transferRequest = 0
    @State private var lockedFeature: LockedFeature?

    /// The optional circles beside the pill (More is always there).
    private var circleCount: Int {
        (showsMirrorToggle ? 1 : 0) + 1 /* capture */ + 1 /* send */ + (onShowSidebar == nil ? 0 : 1)
    }

    /// Room the presets and the Ask circle take in the row.
    private var reservedWidth: Double {
        (presets == nil ? 0 : 168) + (onAsk == nil ? 0 : 52) + (linkBadge == nil ? 0 : 72)
    }

    /// Which circles stay in the row; the rest fold into More (VQ-032,
    /// VQ-065, VQ-081). Before the first measure, everything shows.
    private var actions: ShellHeaderPlan.Actions {
        guard width > 0 else { return .full }
        return ShellHeaderPlan.actions(
            width: Double(width - windowControlsInset),
            horizontalPadding: Double(horizontalPadding),
            circles: circleCount,
            reserved: reservedWidth,
            band: typeSize.typeBand
        )
    }

    var body: some View {
        let fit = self.actions
        HStack(spacing: PixelHandTheme.Space.sm) {
            MacPill(
                name: peerName,
                subtitle: subtitle,
                status: isLocked ? .locked : (isLive ? .online : .offline),
                nameLines: ShellHeaderPlan.pillNameLines(band: typeSize.typeBand),
                action: onMacs
            )
            .accessibilityHint("Shows My Macs.")
            .accessibilityIdentifier("ph.header.macPill")
            .offset(x: swipeOffset)
            .simultaneousGesture(pillSwipe)
            .layoutPriority(1)
            if fit == .full, let badge = linkBadge {
                LinkBadge(kind: badge)
            }
            if fit == .full, let onAsk {
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
                if fit == .full, let presets {
                    LayoutPresetPicker(selection: presets)
                }
            }
            if fit == .full {
                if showsMirrorToggle {
                    GlassCircleButton(
                        glyph: PixelGlyphs.pictureInPicture,
                        label: isMirrorActive ? "Hide the Mac’s screen" : "Show the Mac’s screen",
                        isOn: isMirrorActive,
                        action: onToggleMirror
                    )
                    .accessibilityIdentifier("ph.header.screen")
                    .requiresPro(.mirror)
                }
            }
            if fit <= .captureAndMore {
                captureMenu
            }
            if fit == .full {
                TransferHeaderButton() // Sharing lane: Send and Inbox (S2)
                if let onShowSidebar {
                    GlassCircleButton(glyph: PixelGlyphs.sidebar, label: "Show the Macs sidebar", action: onShowSidebar)
                }
            }
            moreMenu(folded: fit)
        }
        .padding(.leading, horizontalPadding + windowControlsInset)
        .padding(.trailing, horizontalPadding)
        .frame(minHeight: PixelHandTheme.ControlHeight.dock)
        .phGlassGroup()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background { WindowControlsInset(inset: $windowControlsInset) }
        .background {
            // Folded: the send sheet and its alerts still live here.
            if fit != .full {
                TransferHeaderButton(openRequest: transferRequest)
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $lockedFeature) { locked in
            PaywallView(reason: .feature(locked.feature))
        }
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
                    if !MacSwitcher.shared.step(by: value.translation.width < 0 ? 1 : -1) { onMacs() } // Multi-Mac lane: swipe = next/previous Mac
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
        .accessibilityIdentifier("ph.header.capture")
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.standard / 2)
        .requiresPro(.capture)
    }

    /// More: the circles that didn't fit, Settings, and Disconnect at the
    /// end, away from the rest. Labels never wrap (VQ-035).
    private func moreMenu(folded actions: ShellHeaderPlan.Actions) -> some View {
        Menu {
            if actions != .full {
                Section {
                    if showsMirrorToggle {
                        lockable(.mirror) {
                            Button(action: onToggleMirror) {
                                Label(isMirrorActive ? "Hide screen" : "Show screen", systemImage: "rectangle.inset.topright.filled")
                            }
                        }
                    }
                    if actions == .moreOnly {
                        lockable(.capture) {
                            Menu {
                                Button("Full screen", action: onFullScreen)
                                Button("Region", action: onRegion)
                                Button("Window", action: onWindow)
                                Button("Read text", action: onOCR)
                            } label: {
                                Label("Capture", systemImage: "camera.viewfinder")
                            }
                        }
                    }
                    lockable(.sharing) {
                        Button {
                            transferRequest += 1
                        } label: {
                            Label("Send and Inbox", systemImage: "paperplane")
                        }
                    }
                    if let onShowSidebar {
                        Button(action: onShowSidebar) {
                            Label("Show Macs", systemImage: "sidebar.leading")
                        }
                    }
                    if let onAsk {
                        Button(action: onAsk) {
                            Label("Ask", systemImage: "text.magnifyingglass")
                        }
                    }
                    if let presets {
                        Picker(selection: presets) {
                            ForEach(LayoutPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        } label: {
                            Label("Layout", systemImage: "rectangle.split.2x1")
                        }
                    }
                }
            }
            Button(action: onSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            #if DEBUG
            // The legacy layout is a developer tool, never customer UI (VQ-035).
            Button(action: onClassicLayout) {
                Label("Classic layout (debug)", systemImage: "rectangle.grid.1x2")
            }
            #endif
            Divider()
            Button(role: .destructive, action: onDisconnect) {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .accessibilityLabel("Disconnect from \(peerName)")
        } label: {
            PHGlyph(glyph: PixelGlyphs.settings, pitch: PixelPitch.header)
                .foregroundStyle(PixelHandTheme.ink)
                .frame(width: PixelHandTheme.ControlHeight.standard, height: PixelHandTheme.ControlHeight.standard)
                .phGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("ph.header.more")
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.standard / 2)
    }

    /// A folded item for a Pro feature: as is when unlocked, otherwise a
    /// "· Pro" item that opens the paywall for it.
    @ViewBuilder
    private func lockable<Content: View>(_ feature: ProFeature, @ViewBuilder content: () -> Content) -> some View {
        if entitlements.allows(feature) {
            content()
        } else {
            Button {
                lockedFeature = LockedFeature(feature: feature)
            } label: {
                Label("\(SubscriptionCopy.title(feature)) · Pro", systemImage: "lock")
            }
        }
    }
}

/// A Pro feature the folded More menu opens the paywall for.
private struct LockedFeature: Identifiable {
    let feature: ProFeature
    var id: String { feature.rawValue }
}
