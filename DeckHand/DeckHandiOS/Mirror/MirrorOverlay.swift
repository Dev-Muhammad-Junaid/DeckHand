//
//  MirrorOverlay.swift
//  DeckHandiOS
//
//  The floating mirror as `ControlView` places it: `MirrorThumbnailView`
//  wired to the session model, plus the pieces the mirror lane adds over
//  the picture:
//
//  - the Mac's pointer, drawn here from the cursor updates (S3);
//  - the display picker with Follow cursor, when the Mac has more than one
//    display;
//  - the "Cursor is on <display>" badge, with Bring here / Show;
//  - the stream stats line (S6), when turned on in Settings;
//  - the HEVC display layer in place of the JPEG image (S5);
//  - the desktop dots under the mirror, and ‹ › dimmed or hidden at the
//    ends of the mirrored display's Spaces (from `system.displayState`);
//  - S14: "Window…" in the picker (mirror one window), "Pointer outside
//    the window" while a window is mirrored, and the notice when a
//    mirrored window ends and the mirror goes back to its display.
//

import SwiftUI

struct MirrorOverlay: View {
    let session: ControlSessionModel
    let containerSize: CGSize

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        let strip = session.mirrorSpaceStrip
        MirrorThumbnailView(
            image: session.mirrorImage,
            containerSize: containerSize,
            onClose: { session.toggleMirror(settings: settings) },
            onSwitchSpace: { direction in
                session.switchSpace(direction)
            },
            onStreamWidthChanged: { naturalWidth in
                session.mirrorNaturalWidth = naturalWidth
                session.renegotiateMirror(settings: settings)
            },
            initialLayout: settings.rememberMirrorLayout
                ? settings.mirrorLayout
                : nil,
            onLayoutChanged: { layout in
                guard settings.rememberMirrorLayout else { return }
                settings.mirrorLayout = layout
            },
            cursorLayer: AnyView(MirrorCursorLayer(session: session)),
            topLeadingAccessory: AnyView(MirrorDisplayPicker(session: session)),
            bottomAccessory: AnyView(MirrorBottomChrome(session: session)),
            belowAccessory: AnyView(MirrorSpaceDots(strip: strip)),
            previousChevron: strip.previous,
            nextChevron: strip.next,
            videoLayer: session.mirrorShowsVideo
                ? AnyView(MirrorVideoLayerView(renderer: session.mirrorVideoRenderer))
                : nil,
            videoSize: session.mirrorVideoSize
        )
        // S5: HEVC on or off takes effect at once.
        .onChange(of: settings.mirrorPrefersHEVC) {
            session.renegotiateMirror(settings: settings)
        }
        // S17: the Mac's sound on or off takes effect at once.
        .onChange(of: settings.mirrorPlaysMacAudio) {
            session.syncMirrorAudio()
        }
    }
}

// MARK: - Cursor (S3)

/// Draws the Mac's pointer over the picture. Reads only the cursor state,
/// so 60 updates a second redraw this layer and nothing else.
struct MirrorCursorLayer: View {
    let session: ControlSessionModel

    var body: some View {
        GeometryReader { proxy in
            if let state = session.mirrorCursor, state.isVisibleInMirror, proxy.size.width > 0 {
                if let sprite = session.mirrorCursorSprite {
                    let rect = MirrorCursorGeometry.spriteFrame(
                        state: state,
                        shape: sprite.shape,
                        displayPointWidth: session.mirroredDisplayPointWidth,
                        viewWidth: Double(proxy.size.width),
                        viewHeight: Double(proxy.size.height)
                    )
                    Image(uiImage: sprite.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                } else {
                    // The shape hasn't arrived yet: a plain arrow at the tip.
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .position(
                            x: state.x * proxy.size.width + 4,
                            y: state.y * proxy.size.height + 7
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Display picker

/// Which display (or, S14, window) the mirror shows, and Follow cursor.
/// Shown once the Mac has listed its displays: with one display it still
/// offers "Window…".
struct MirrorDisplayPicker: View {
    let session: ControlSessionModel

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        if !session.mirrorDisplays.isEmpty {
            let window = session.mirrorWindowSelection.window
            let windowActive = session.mirrorWindowSelection.isActive
            Menu {
                if let window {
                    Label(window.longLabel, systemImage: "checkmark")
                }
                ForEach(session.mirrorDisplays) { display in
                    Button {
                        settings.mirrorFollowsCursor = false
                        session.selectMirrorDisplay(display.displayID)
                    } label: {
                        if !windowActive, display.displayID == session.selectedMirrorDisplayID {
                            Label(display.name, systemImage: "checkmark")
                        } else {
                            Text(display.name)
                        }
                    }
                }
                Divider()
                Button {
                    settings.mirrorFollowsCursor = false
                    session.openMirrorWindowPicker()
                } label: {
                    Label("Window…", systemImage: "macwindow")
                }
                .disabled(!session.canMirrorWindow)
                if session.mirrorDisplays.count > 1, !windowActive {
                    Toggle(isOn: $settings.mirrorFollowsCursor) {
                        Label("Follow Cursor", systemImage: "cursorarrow.motionlines")
                    }
                }
            } label: {
                let micro = MirrorPaneChrome.tileStrip(
                    displays: session.mirrorDisplays,
                    mirroredDisplayID: session.selectedMirrorDisplayID,
                    mirroringWindow: windowActive,
                    host: session.mirrorHostStats,
                    client: session.mirrorClientStats
                )
                // UX-016: the tile's micro strip (`LIVE · D1 · 60`) is the
                // picker's button.
                StatusStrip(items: micro.items, pitch: 1.4, accessibilityText: micro.spoken)
                    .frame(minHeight: PixelHandTheme.ControlHeight.hit, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .padding(6)
            .accessibilityLabel(window.map { "Mirrored window: \($0.longLabel)" } ?? "Mirrored display: \(selectedLabel)")
        }
    }

    private var selectedLabel: String {
        if let window = session.mirrorWindowSelection.window { return window.shortLabel }
        if session.mirrorWindowSelection.isActive { return "Window" }
        return session.mirrorDisplays.first { $0.displayID == session.selectedMirrorDisplayID }?.shortLabel ?? "Display"
    }
}

// MARK: - Desktop dots

/// One dot per Space of the mirrored display, the current one lit;
/// full-screen app desktops hollow (`DesktopDots`). Nothing when Spaces aren't known.
struct MirrorSpaceDots: View {
    let strip: MirrorSpaceStrip

    var body: some View {
        if !strip.dots.isEmpty {
            DesktopDots(
                count: strip.dots.count,
                current: strip.dots.firstIndex(where: \.isCurrent) ?? 0,
                fullScreen: Set(strip.dots.compactMap { dot -> Int? in
                    if case .fullScreen = dot.kind { return dot.index }
                    return nil
                })
            )
            .padding(.horizontal, 4)
            .frame(height: PixelHandTheme.ControlHeight.badge)
            .background(PixelHandTheme.Brand.screen.opacity(0.84), in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.badge, style: .continuous))
            .pixelOnNavy()
            .animation(.easeInOut(duration: 0.2), value: strip)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strip.accessibilitySummary ?? "")
        }
    }
}

// MARK: - Badge and stats

/// The "Cursor is on …" badge and the stats line, stacked at the bottom of
/// the picture.
struct MirrorBottomChrome: View {
    let session: ControlSessionModel

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        let chrome = session.mirrorChrome
        VStack(alignment: .leading, spacing: 4) {
            if let notice = session.mirrorNotice {
                // S14: the mirrored window ended; the mirror shows its display.
                MirrorNoticeLabel(glyph: PixelGlyphs.displays, text: notice)
                    .transition(.opacity)
            }
            if let badge = MirrorPaneChrome.cursorBadge(
                chrome: chrome,
                displays: session.mirrorDisplays,
                mirroredDisplayID: session.selectedMirrorDisplayID,
                layout: session.displayLayout
            ) {
                MirrorCursorBadgeView(badge: badge) {
                    session.selectMirrorDisplay(badge.displayID)
                }
                .transition(.opacity)
            }
            if chrome.cursorOutsideWindow {
                // S14: the pointer is somewhere else on the Mac.
                MirrorNoticeLabel(glyph: PixelGlyphs.pointer, text: "Pointer outside the window")
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if settings.showMirrorStats {
                StatusStrip(
                    items: MirrorPaneChrome.statsStrip(
                        host: session.mirrorHostStats,
                        client: session.mirrorClientStats,
                        link: RemoteLinkStatus.shared.current
                    ),
                    pitch: 1.3,
                    accessibilityText: MirrorStatsLine.text(
                        host: session.mirrorHostStats,
                        client: session.mirrorClientStats,
                        clientName: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
                    )
                )
                .allowsHitTesting(false)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: chrome)
    }
}
