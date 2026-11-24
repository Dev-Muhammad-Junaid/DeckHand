//
//  CaptureCapsule.swift
//  DeckHandiOS
//

import SwiftUI

/// The toolbar's capture button: a tap runs the default capture, a long
/// press offers every mode.
struct CaptureCapsule: View {
    let isBusy: Bool
    let onFullScreen: () -> Void
    let onRegion: () -> Void
    let onWindow: () -> Void
    let onOCR: () -> Void
    /// What a plain tap does, which the user picks in settings. The menu
    /// still offers every mode.
    let onPrimary: () -> Void

    var body: some View {
        Menu {
            Button {
                onFullScreen()
            } label: {
                Label("Full screen", systemImage: "rectangle.dashed")
            }
            Button {
                onRegion()
            } label: {
                Label("Region…", systemImage: "rectangle.dashed.badge.record")
            }
            Button {
                onWindow()
            } label: {
                Label("Window…", systemImage: "macwindow")
            }
            Divider()
            Button {
                onOCR()
            } label: {
                Label("Read text", systemImage: "text.viewfinder")
            }
        } label: {
            // UX-009: the pixel capture glyph; the dot wave while the Mac works.
            if isBusy {
                DotWave(pitch: 2.4, label: "Capturing")
            } else {
                PHGlyph(glyph: PixelGlyphs.capture, pitch: PixelPitch.header)
            }
        } primaryAction: {
            guard !isBusy else { return }
            onPrimary()
        }
        .disabled(isBusy)
        .accessibilityLabel("Capture")
        .accessibilityHint("Takes your default capture. Touch and hold for full screen, region, window or read text.")
    }
}
