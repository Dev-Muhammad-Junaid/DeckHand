//
//  MirrorPiPViews.swift
//  DeckHandiOS
//
//  UX-041 in the mirror's views:
//
//  - `.mirrorPiPSync(session:)` tells the session about Pro (the mirror's
//    feature) and the "Keep watching in Picture in Picture" setting;
//  - `MirrorPiPBackground` puts PiP's layer under the inline picture;
//  - `MirrorPiPToolButton` is the PiP button in the docked pane's toolbar
//    (the floating tile has the same action in its display menu).
//

import SwiftUI

extension View {
    /// Keeps the session's PiP state in step with Pro and the setting.
    func mirrorPiPSync(session: ControlSessionModel) -> some View {
        modifier(MirrorPiPSync(session: session))
    }
}

private struct MirrorPiPSync: ViewModifier {
    let session: ControlSessionModel

    @Environment(\.entitlements) private var entitlements
    @EnvironmentObject private var settings: DeckHandSettings

    func body(content: Content) -> some View {
        content
            .onChange(of: entitlements.allows(.mirror), initial: true) { _, allowed in
                session.setMirrorPiPEntitled(allowed)
            }
            .onChange(of: settings.mirrorPiPAutoStart, initial: true) { _, enabled in
                session.setMirrorPiPAutoStart(enabled)
            }
            .onChange(of: settings.mirrorFrameRate) {
                session.updateMirrorPiPPipeline()
            }
    }
}

/// PiP's layer, sized like the picture and drawn under it.
struct MirrorPiPBackground: View {
    let session: ControlSessionModel

    var body: some View {
        if session.mirrorPiPSupported {
            MirrorPiPLayerView(controller: session.mirrorPiP)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The pane toolbar's PiP button: opens PiP, or closes it when open.
struct MirrorPiPToolButton: View {
    let session: ControlSessionModel

    var body: some View {
        if session.mirrorPiPSupported {
            let active = session.mirrorPiPState.isActive
            MirrorToolButton(
                glyph: PixelGlyphs.pictureInPicture,
                label: active ? "Close Picture in Picture" : "Keep watching in Picture in Picture",
                isOn: active,
                isEnabled: session.mirrorPiPCanStart,
                action: { session.toggleMirrorPiP() }
            )
            .accessibilityIdentifier("ph.mirror.pictureInPicture")
            .requiresPro(.mirror)
        }
    }
}
