//
//  MirrorDisplayPickerSheet.swift
//  DeckHandiOS – Mirror
//
//  "Show which display?" (UX-016): the Mac's displays drawn to scale in its
//  arrangement, each with its desktop dots, the phosphor pointer glyph on
//  the display that has the cursor, Follow the cursor, and Window… (S14).
//  Opens from the display button in the mirror toolbar.
//  Board: "New features" › Display picker.
//

import SwiftUI

struct MirrorDisplayPickerSheet: View {
    let session: ControlSessionModel
    let macName: String

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.lg) {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.phInk2)
                        .fixedSize(horizontal: false, vertical: true)

                    arrangement
                        .frame(height: 150)

                    VStack(spacing: 0) {
                        ForEach(arranged) { display in
                            displayRow(display)
                            if display.id != arranged.last?.id {
                                Divider().overlay(PixelHandTheme.hairline)
                            }
                        }
                    }
                    .phCard()

                    VStack(spacing: 0) {
                        if session.mirrorDisplays.count > 1 {
                            Toggle(isOn: $settings.mirrorFollowsCursor) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Follow the cursor")
                                        .font(.body)
                                    Text("Switch the picture when the pointer moves to another display")
                                        .font(.footnote)
                                        .foregroundStyle(.phInk2)
                                }
                            }
                            .tint(PixelHandTheme.accent)
                            .padding(.vertical, PixelHandTheme.Space.md)
                            .padding(.horizontal, PixelHandTheme.Space.lg)
                            .disabled(session.mirrorWindowSelection.isActive)
                            Divider().overlay(PixelHandTheme.hairline)
                        }
                        Button {
                            settings.mirrorFollowsCursor = false
                            dismiss()
                            // The window picker is its own sheet: open it
                            // once this one has gone.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(450))
                                session.openMirrorWindowPicker()
                            }
                        } label: {
                            HStack(spacing: PixelHandTheme.Space.md) {
                                PHGlyph(glyph: PixelGlyphs.region, pitch: 2)
                                    .foregroundStyle(PixelHandTheme.ink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(windowTitle)
                                        .font(.body)
                                        .foregroundStyle(.phInk)
                                    Text("Mirror one app window, sharper on a small screen")
                                        .font(.footnote)
                                        .foregroundStyle(.phInk2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.phInk3)
                            }
                            .padding(.vertical, PixelHandTheme.Space.md)
                            .padding(.horizontal, PixelHandTheme.Space.lg)
                            .frame(minHeight: PixelHandTheme.ControlHeight.hit)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!session.canMirrorWindow)
                    }
                    .phCard()
                }
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .padding(.bottom, PixelHandTheme.Space.xl)
            }
            .background(PixelHandTheme.canvas)
            .navigationTitle("Show which display?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Data

    private var cursorDisplayID: UInt32? {
        MirrorDisplayChrome.cursorDisplayID(stream: session.mirrorCursorDisplayID, layout: session.displayLayout)
    }

    private var arranged: [MirrorArrangedDisplay] {
        // Laid out for a 340 × 150 box; the drawing scales to the real
        // width with the same proportions.
        MirrorPaneChrome.arrangement(
            displays: session.mirrorDisplays,
            layout: session.displayLayout,
            mirroredDisplayID: session.mirrorWindowSelection.isActive ? nil : session.selectedMirrorDisplayID,
            cursorDisplayID: cursorDisplayID,
            boxWidth: 340,
            boxHeight: 150
        )
    }

    private var caption: String {
        let name = cursorDisplayID.flatMap { id in session.mirrorDisplays.first { $0.displayID == id }?.name }
        let base = session.mirrorDisplays.count > 1 ? "Arranged as on \(macName)." : "\(macName) has one display."
        guard let name, session.mirrorDisplays.count > 1 else { return base }
        return "\(base) The cursor is on \(name)."
    }

    private var windowTitle: String {
        if let window = session.mirrorWindowSelection.window { return "Window: \(window.shortLabel)" }
        return "A window…"
    }

    private func select(_ display: MirrorArrangedDisplay) {
        settings.mirrorFollowsCursor = false
        session.selectMirrorDisplay(display.displayID)
        GestureHaptic.selection.trigger()
        dismiss()
    }

    // MARK: Drawing

    private var arrangement: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 340, proxy.size.height / 150)
            let offsetX = (proxy.size.width - 340 * scale) / 2
            ZStack(alignment: .topLeading) {
                ForEach(arranged) { display in
                    let selected = display.isMirrored && !session.mirrorWindowSelection.isActive
                    Button { select(display) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(PixelHandTheme.Brand.screen)
                            RestingDotGrid(pitch: 9, dot: 1.6)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(spacing: 4) {
                                DotMatrixText("\(display.number)", pitch: 3, label: "Display \(display.number)", glows: selected, stepsWithType: false)
                                    .foregroundStyle(selected ? PixelHandTheme.Brand.phosphor : PixelHandTheme.Brand.stripDim)
                                if display.hasCursor {
                                    PHGlyph(glyph: PixelGlyphs.pointer, pitch: 1.6, accent: PixelHandTheme.Brand.phosphor)
                                        .foregroundStyle(PixelHandTheme.Brand.phosphor)
                                }
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? PixelHandTheme.accent : Color.white.opacity(0.14), lineWidth: selected ? 2 : 0.5)
                        )
                        .pixelOnNavy()
                    }
                    .buttonStyle(.plain)
                    .frame(width: display.width * scale, height: display.height * scale)
                    .offset(x: offsetX + display.x * scale, y: display.y * scale)
                    .accessibilityLabel("\(display.name), display \(display.number)\(display.hasCursor ? ", has the pointer" : "")")
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                    .phosphorFocusable(cornerRadius: 8)
                }
            }
        }
    }

    private func displayRow(_ display: MirrorArrangedDisplay) -> some View {
        let selected = display.isMirrored && !session.mirrorWindowSelection.isActive
        return Button { select(display) } label: {
            HStack(spacing: PixelHandTheme.Space.md) {
                PHGlyph(glyph: PixelGlyphs.displays, pitch: 2)
                    .foregroundStyle(selected ? PixelHandTheme.accent : PixelHandTheme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(.phInk)
                        .lineLimit(1)
                    Text(MirrorPaneChrome.displaySubtitle(number: display.number, spaceCount: display.spaceCount))
                        .font(.footnote)
                        .foregroundStyle(.phInk2)
                }
                Spacer(minLength: PixelHandTheme.Space.sm)
                if let count = display.spaceCount, count > 0 {
                    DesktopDots(count: count, current: display.currentSpaceIndex ?? 0, fullScreen: display.fullScreenIndexes)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PixelHandTheme.accent)
                }
            }
            .padding(.vertical, PixelHandTheme.Space.md)
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .frame(minHeight: PixelHandTheme.ControlHeight.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("ph.mirror.displayRow")
    }
}
