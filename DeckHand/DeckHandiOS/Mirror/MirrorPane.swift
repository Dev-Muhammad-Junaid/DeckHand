//
//  MirrorPane.swift
//  DeckHandiOS – Mirror
//
//  The docked mirror on the Screen surface (UX-006): the live picture in a
//  black pane (radius 24), the status strip top-leading
//  (`STUDIO · D1/2 · DESK 2/3 · 60 FPS`), the cursor badge top-trailing
//  (`ON 2 →`, only while the pointer is on another display), the S6 stats
//  strip under it when turned on, and the glass toolbar at the bottom:
//  display picker (`1/2`), ‹ desktop dots ›, sound, stop.
//
//  Everything the floating tile does still runs here: the binary stream
//  (JPEG or HEVC with its watchdog, in `ControlSessionModel+Mirror`), the
//  pointer sprite, Follow cursor, window mirroring (S14), the Mac's sound
//  (S17) and the stream width, which follows the pane's width in the same
//  tiers as the tile.
//  Board: "New features" › Mirror with display and desktop chrome.
//

import SwiftUI

struct MirrorPane: View {
    let session: ControlSessionModel
    let macName: String

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPickerPresented = false

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 600
            ZStack {
                Color.black
                MirrorPicture(session: session)
                    .mirrorScanline(on: scanKey)
            }
            .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: PixelHandTheme.Stroke.hairline)
            )
            .overlay(alignment: .top) { topChrome(wide: wide) }
            .overlay(alignment: .bottom) { bottomChrome }
            .pixelOnNavy()
            .onAppear { syncStreamWidth(proxy.size.width) }
            .onChange(of: proxy.size.width) { _, width in syncStreamWidth(width) }
        }
        .sheet(isPresented: $isPickerPresented) {
            MirrorDisplayPickerSheet(session: session, macName: macName)
                .environmentObject(settings)
        }
        // S5: HEVC on or off takes effect at once.
        .onChange(of: settings.mirrorPrefersHEVC) {
            session.renegotiateMirror(settings: settings)
        }
        // S17: the Mac's sound on or off takes effect at once.
        .onChange(of: settings.mirrorPlaysMacAudio) {
            session.syncMirrorAudio()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live screen of \(macName)")
    }

    // MARK: Data

    private var strip: MirrorSpaceStrip { session.mirrorSpaceStrip }

    /// A new picture (first frame, display, window or desktop) sweeps in
    /// under the scanline.
    private var scanKey: String {
        let hasFrame = session.mirrorShowsVideo || session.mirrorImage != nil
        let space = strip.dots.firstIndex(where: \.isCurrent) ?? -1
        return "\(hasFrame)-\(session.selectedMirrorDisplayID ?? 0)-\(session.mirrorWindowSelection.isActive)-\(space)"
    }

    private var cursorBadge: MirrorCursorBadge? {
        MirrorPaneChrome.cursorBadge(
            chrome: session.mirrorChrome,
            displays: session.mirrorDisplays,
            mirroredDisplayID: session.selectedMirrorDisplayID,
            layout: session.displayLayout
        )
    }

    /// The pane is the tile at its largest: same tiers, so a pane and a
    /// tile of the same width ask for the same stream.
    private func syncStreamWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        let tier = MirrorThumbnailView.streamWidth(for: width)
        guard tier != session.mirrorNaturalWidth else { return }
        session.mirrorNaturalWidth = tier
        session.renegotiateMirror(settings: settings)
    }

    // MARK: Chrome

    private func topChrome(wide: Bool) -> some View {
        let status = MirrorPaneChrome.paneStrip(
            macName: macName,
            displays: session.mirrorDisplays,
            mirroredDisplayID: session.selectedMirrorDisplayID,
            windowTitle: session.mirrorWindowSelection.window?.longLabel,
            mirroringWindow: session.mirrorWindowSelection.isActive,
            spaces: strip,
            host: session.mirrorHostStats,
            client: session.mirrorClientStats
        )
        return VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
            HStack(alignment: .center, spacing: PixelHandTheme.Space.sm) {
                StatusStrip(items: status.items, pitch: wide ? 1.8 : 1.6, accessibilityText: status.spoken)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if let badge = cursorBadge {
                    MirrorCursorBadgeView(badge: badge) {
                        session.selectMirrorDisplay(badge.displayID)
                    }
                    .transition(.opacity)
                }
            }
            if settings.showMirrorStats {
                StatusStrip(
                    items: MirrorPaneChrome.statsStrip(
                        host: session.mirrorHostStats,
                        client: session.mirrorClientStats,
                        link: RemoteLinkStatus.shared.current
                    ),
                    pitch: wide ? 2 : 1.4,
                    accessibilityText: MirrorStatsLine.text(
                        host: session.mirrorHostStats,
                        client: session.mirrorClientStats,
                        clientName: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
                    )
                )
                .allowsHitTesting(false)
            }
        }
        .padding(wide ? PixelHandTheme.Space.md : PixelHandTheme.Space.sm)
        .animation(PixelHandMotion.reduced(PixelHandMotion.quick, reduceMotion: reduceMotion), value: cursorBadge)
    }

    private var bottomChrome: some View {
        let chrome = session.mirrorChrome
        return VStack(spacing: PixelHandTheme.Space.sm) {
            if let notice = session.mirrorNotice {
                // S14: the mirrored window ended; the mirror shows its display.
                MirrorNoticeLabel(glyph: PixelGlyphs.displays, text: notice)
                    .transition(.opacity)
            }
            if chrome.cursorOutsideWindow {
                MirrorNoticeLabel(glyph: PixelGlyphs.pointer, text: "Pointer outside the window")
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            toolbar
        }
        .padding(PixelHandTheme.Space.sm)
        .animation(PixelHandMotion.reduced(PixelHandMotion.quick, reduceMotion: reduceMotion), value: chrome)
    }

    private var toolbar: some View {
        let windowActive = session.mirrorWindowSelection.isActive
        return HStack(spacing: 0) {
            if !session.mirrorDisplays.isEmpty {
                MirrorToolButton(
                    glyph: windowActive ? PixelGlyphs.region : PixelGlyphs.displays,
                    counter: MirrorPaneChrome.displayCounter(
                        displays: session.mirrorDisplays,
                        mirroredDisplayID: session.selectedMirrorDisplayID,
                        mirroringWindow: windowActive
                    ),
                    label: windowActive ? "Mirrored window. Choose a display or window" : "Choose a display",
                    isOn: settings.mirrorFollowsCursor && !windowActive,
                    action: { isPickerPresented = true }
                )
            }
            if !windowActive {
                MirrorSpaceControls(strip: strip) { direction in
                    GestureHaptic.medium.trigger()
                    session.switchSpace(direction)
                }
            }
            MirrorToolButton(
                glyph: settings.mirrorPlaysMacAudio ? PixelGlyphs.soundOn : PixelGlyphs.soundOff,
                label: settings.mirrorPlaysMacAudio ? "Mute the Mac’s sound" : "Play the Mac’s sound",
                isOn: settings.mirrorPlaysMacAudio,
                action: { settings.mirrorPlaysMacAudio.toggle() }
            )
            MirrorToolButton(
                glyph: PixelGlyphs.close,
                label: "Stop the live screen",
                action: { session.toggleMirror(settings: settings) }
            )
        }
        .padding(.horizontal, 2)
        .phGlass(in: Capsule(), interactive: true)
        .phGlassGroup()
    }
}
