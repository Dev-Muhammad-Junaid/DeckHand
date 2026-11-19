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
                HStack(spacing: 4) {
                    Image(systemName: chipSymbol(windowActive: windowActive))
                    Text(selectedLabel)
                        .lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
            }
            .padding(6)
            .accessibilityLabel(window.map { "Mirrored window: \($0.longLabel)" } ?? "Mirrored display: \(selectedLabel)")
        }
    }

    private func chipSymbol(windowActive: Bool) -> String {
        if windowActive { return "macwindow" }
        if settings.mirrorFollowsCursor { return "cursorarrow.motionlines" }
        return session.mirrorDisplays.count > 1 ? "display.2" : "display"
    }

    private var selectedLabel: String {
        if let window = session.mirrorWindowSelection.window { return window.shortLabel }
        if session.mirrorWindowSelection.isActive { return "Window" }
        return session.mirrorDisplays.first { $0.displayID == session.selectedMirrorDisplayID }?.shortLabel ?? "Display"
    }
}

// MARK: - Desktop dots

/// One dot per Space of the mirrored display, the current one filled;
/// full-screen apps as short labels. Nothing when Spaces aren't known.
struct MirrorSpaceDots: View {
    let strip: MirrorSpaceStrip

    var body: some View {
        if !strip.dots.isEmpty {
            HStack(spacing: 5) {
                ForEach(strip.dots) { dot in
                    switch dot.kind {
                    case .desktop:
                        Circle()
                            .fill(dot.isCurrent ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                    case let .fullScreen(label):
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(dot.isCurrent ? Color.black : Color.white.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(dot.isCurrent ? Color.white : Color.white.opacity(0.18))
                            )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
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
                Label(notice, systemImage: "macwindow.badge.plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .transition(.opacity)
            }
            if let display = chrome.cursorElsewhere {
                cursorBadge(display)
                    .transition(.opacity)
            }
            if chrome.cursorOutsideWindow {
                // S14: the pointer is somewhere else on the Mac.
                Label("Pointer outside the window", systemImage: "cursorarrow.rays")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if settings.showMirrorStats {
                Text(MirrorStatsLine.text(
                    host: session.mirrorHostStats,
                    client: session.mirrorClientStats,
                    clientName: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
                ))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityLabel("Stream stats")
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: chrome)
    }

    private func cursorBadge(_ display: DisplayInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cursorarrow")
            Text("Cursor on \(display.shortLabel)")
                .lineLimit(1)
            Button("Bring Here") { session.bringCursorToMirroredDisplay() }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .underline()
            Button("Show") { session.selectMirrorDisplay(display.displayID) }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .underline()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The cursor is on \(display.name)")
    }
}
