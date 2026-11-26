//
//  FocusLoupeView.swift
//  DeckHandiOS – Keyboard
//
//  Zoom to the input (owner testing, build 26, OT-12): the Mac's focused
//  text field up close, attached to the Type panel, so you can read what
//  you type without hunting for it on the mirror. The Mac reports where
//  the field and its caret are (`system.focusState`, while the loupe asks
//  with `watchFocus`); Core's `FocusLoupe` picks the crop (zoom to the
//  field's width, pan with the caret, clamp to the display); this view cuts
//  that crop out of the mirror's own frames: a second HEVC layer fed the
//  same samples (`mirrorLoupeRenderer`), or the JPEG frame.
//
//  It needs the mirror: the Mac has one capture and one encoder per iPad,
//  so a separate crop stream would replace the mirror (see
//  `LANE-owner26.md`). With the mirror off it says so and offers to start
//  it. Pro, like the mirror.
//

import SwiftUI

struct FocusLoupeView: View {
    let session: ControlSessionModel

    @EnvironmentObject private var settings: DeckHandSettings
    @State private var crop: FocusLoupeCrop?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                    .fill(Color.black)
                content(size: size)
                    .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
            }
            // The loupe is exactly the frame the host gives it.
            .frame(width: size.width, height: size.height)
            .clipped()
            .onAppear { update(size: size) }
            .onChange(of: session.focusedField) { _, _ in update(size: size) }
            .onChange(of: size) { _, newSize in update(size: newSize) }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 3)
        // Build 27 bug 1: the picture inside is the whole mirror frame
        // scaled up and offset (about 4,536 pt wide on iPad), and neither
        // `.clipped()` nor `.clipShape` trims hit-testing or the
        // accessibility frame. The loupe's own shape is now the only thing
        // that takes touches, so the Type panel's target chip and close
        // button next to it stay hittable.
        .contentShape(Rectangle())
        .onAppear { session.setMirrorLoupe(active: true) }
        .onDisappear { session.setMirrorLoupe(active: false) }
        // One container at the loupe's own frame: its text line and the
        // Start the mirror button inside stay reachable; the picture is
        // hidden from VoiceOver (it would report the scaled frame).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(loupeDescription)
        .accessibilityIdentifier("ph.type.loupe")
    }

    /// What VoiceOver says for the loupe: what it shows, by state.
    private var loupeDescription: String {
        if !session.isMirrorActive { return "Zoom to the input. The mirror is off." }
        guard let field = session.focusedField else { return "Zoom to the input. Looking for the text field." }
        if field.source == FocusedFieldSnapshot.Source.none { return "Zoom to the input. No text field in focus on the Mac." }
        if crop?.mode == .pointer { return "Zoom to the input, around the pointer in \(field.app ?? "the Mac app")." }
        return "Zoom to the input: the text field in \(field.app ?? "the Mac app"), up close."
    }

    // MARK: Content

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if !session.isMirrorActive {
            message(
                "The loupe cuts from the Mac's picture.",
                detail: "Start the mirror to see the text field up close.",
                action: ("Start the mirror", { session.toggleMirror(settings: settings) })
            )
        } else if session.mirrorWindowSelection.window != nil {
            message("The loupe needs the whole display mirrored.", detail: "Mirror a display, not a window, to zoom to the input.", action: nil)
        } else if let crop, hasFrame {
            ZStack(alignment: .bottomLeading) {
                picture(crop: crop, size: size)
                caretMark(crop: crop, size: size)
                if crop.mode == .pointer {
                    smallPrint("Around the pointer: \(session.focusedField?.app ?? "this app") doesn't say where its text field is.")
                } else if let readout = FocusedTextReadout(session.focusedField?.text) {
                    textLine(readout)
                }
            }
        } else if session.focusedField?.source == FocusedFieldSnapshot.Source.none {
            message("No text field in focus on the Mac.", detail: "Click into one there, or start typing.", action: nil)
        } else if session.focusedField != nil, crop == nil {
            message("The text field is on another display.", detail: "Mirror that display to zoom to it.", action: nil)
        } else {
            message("Looking for the text field…", detail: nil, action: nil)
        }
    }

    private var hasFrame: Bool { session.mirrorShowsVideo || session.mirrorImage != nil }

    /// The whole mirror frame, scaled so the crop fills the loupe, shifted
    /// so the crop's corner is at the loupe's.
    @ViewBuilder
    private func picture(crop: FocusLoupeCrop, size: CGSize) -> some View {
        let rect = crop.rect
        let full = CGSize(width: size.width / CGFloat(max(rect.width, 0.0001)), height: size.height / CGFloat(max(rect.height, 0.0001)))
        let origin = CGPoint(x: -CGFloat(rect.x) * full.width, y: -CGFloat(rect.y) * full.height)
        Group {
            if session.mirrorShowsVideo {
                MirrorVideoLayerView(renderer: session.mirrorLoupeRenderer)
            } else if let image = session.mirrorImage {
                Image(uiImage: image).resizable().interpolation(.high)
            }
        }
        .frame(width: full.width, height: full.height)
        .offset(x: origin.x, y: origin.y)
        // Build 27 bug 1: the scaled frame reaches far outside the loupe.
        // It takes no touches and isn't an accessibility element, so only
        // the loupe's own rectangle counts.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .animation(PixelHandMotion.quick, value: crop.rect)
    }

    /// A thin accent bar where the caret is, so the eye finds it.
    @ViewBuilder
    private func caretMark(crop: FocusLoupeCrop, size: CGSize) -> some View {
        if let field = session.focusedField, let caret = field.caret,
           let normal = FocusLoupe.normalized(caret, displayWidth: field.displayWidth, displayHeight: field.displayHeight),
           let spot = FocusLoupe.position(of: normal, inCrop: crop.rect) {
            Rectangle()
                .fill(PixelHandTheme.accent.opacity(0.85))
                .frame(width: 2, height: max(8, CGFloat(spot.height) * size.height))
                .position(x: CGFloat(spot.x) * size.width, y: CGFloat(spot.y + spot.height / 2) * size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// OT-13: a native field's text around the caret, read by the Mac's
    /// Accessibility, with the caret marked and any inline suggestion
    /// dimmed after it (Accept ⇥ takes it). Web and Electron fields send
    /// no text, so they show the picture alone.
    private func textLine(_ readout: FocusedTextReadout) -> some View {
        (Text(readout.before)
            + Text(readout.selected).foregroundColor(PixelHandTheme.Brand.glow)
            + Text("|").foregroundColor(PixelHandTheme.accent)
            + Text(readout.suggestion ?? "").foregroundColor(Color.white.opacity(0.4))
            + Text(readout.suggestion == nil ? readout.after : ""))
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.horizontal, PixelHandTheme.Space.sm)
            .padding(.vertical, PixelHandTheme.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.6))
            .accessibilityLabel(readout.spoken)
            .accessibilityIdentifier("ph.type.loupe.text")
    }

    private func smallPrint(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, PixelHandTheme.Space.sm)
            .padding(.vertical, PixelHandTheme.Space.xs)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(PixelHandTheme.Space.sm)
    }

    private func message(_ title: String, detail: String?, action: (String, () -> Void)?) -> some View {
        VStack(spacing: PixelHandTheme.Space.xs) {
            PHGlyph(glyph: PixelGlyphs.find, pitch: 2)
                .foregroundStyle(PixelHandTheme.Brand.glow)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(PHButtonStyle(kind: .primary, size: .small))
                    .accessibilityIdentifier("ph.type.loupe.startMirror")
            }
        }
        .multilineTextAlignment(.center)
        .padding(PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Crop

    private func update(size: CGSize) {
        guard let snapshot = session.focusedField, size.width > 0, size.height > 0 else {
            crop = nil
            return
        }
        crop = FocusLoupe.crop(
            for: snapshot,
            mirroredDisplayID: session.selectedMirrorDisplayID,
            loupeWidth: Double(size.width),
            loupeHeight: Double(size.height),
            previous: crop
        )
    }
}
