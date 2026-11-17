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
                Label("Full Screen", systemImage: "rectangle.dashed")
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
                Label("Recognize Text", systemImage: "text.viewfinder")
            }
        } label: {
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "camera.viewfinder")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
        } primaryAction: {
            guard !isBusy else { return }
            onPrimary()
        }
        .disabled(isBusy)
        .accessibilityLabel("Capture")
        .accessibilityHint("Tap for a full-screen capture, long-press for region or window options.")
    }
}
