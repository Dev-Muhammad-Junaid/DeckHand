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
//  - the stream stats line (S6), when turned on in Settings.
//

import SwiftUI

struct MirrorOverlay: View {
    let session: ControlSessionModel
    let containerSize: CGSize

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
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
            bottomAccessory: AnyView(MirrorBottomChrome(session: session))
        )
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

/// Which display the mirror shows, and Follow cursor. Only when the Mac
/// has more than one display.
struct MirrorDisplayPicker: View {
    let session: ControlSessionModel

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        if session.mirrorDisplays.count > 1 {
            Menu {
                ForEach(session.mirrorDisplays) { display in
                    Button {
                        settings.mirrorFollowsCursor = false
                        session.selectMirrorDisplay(display.displayID)
                    } label: {
                        if display.displayID == session.selectedMirrorDisplayID {
                            Label(display.name, systemImage: "checkmark")
                        } else {
                            Text(display.name)
                        }
                    }
                }
                Divider()
                Toggle(isOn: $settings.mirrorFollowsCursor) {
                    Label("Follow Cursor", systemImage: "cursorarrow.motionlines")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: settings.mirrorFollowsCursor ? "cursorarrow.motionlines" : "display.2")
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
            .accessibilityLabel("Mirrored display: \(selectedLabel)")
        }
    }

    private var selectedLabel: String {
        session.mirrorDisplays.first { $0.displayID == session.selectedMirrorDisplayID }?.shortLabel ?? "Display"
    }
}

// MARK: - Badge and stats

/// The "Cursor is on …" badge and the stats line, stacked at the bottom of
/// the picture.
struct MirrorBottomChrome: View {
    let session: ControlSessionModel

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let display = session.mirrorChrome.cursorElsewhere {
                cursorBadge(display)
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
        .animation(.easeInOut(duration: 0.2), value: session.mirrorChrome.cursorElsewhere)
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
