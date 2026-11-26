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
import UIKit

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
/// Always there on phones and wherever the device supports PiP (VQ-060,
/// build 23: `MirrorToolbarPlan.pipButton`): the first tap
/// explains what PiP does in the background and turns on "Keep watching in
/// Picture in Picture", so leaving the app keeps the picture too.
struct MirrorPiPToolButton: View {
    let session: ControlSessionModel

    @EnvironmentObject private var settings: DeckHandSettings
    /// The explanation was shown once (accepted or not).
    @AppStorage("ph.mirror.pipExplained") private var hasExplained = false
    @State private var isExplaining = false
    @State private var isExplainingUnavailable = false

    /// VQ-060: phones always show the button (iPhone simulators report no
    /// PiP; iPhones have it); a tap explains when it can't start here.
    private var plan: MirrorToolbarPlan.PiPButton {
        MirrorToolbarPlan.pipButton(
            systemSupportsPiP: session.mirrorPiPSupported,
            isPhone: UIDevice.current.userInterfaceIdiom == .phone
        )
    }

    var body: some View {
        if plan == .explainsUnavailable {
            MirrorToolButton(
                glyph: PixelGlyphs.pictureInPicture,
                label: "Keep watching in Picture in Picture",
                action: { isExplainingUnavailable = true }
            )
            .accessibilityIdentifier("ph.mirror.pictureInPicture")
            .requiresPro(.mirror, badge: .capsule(.bottomTrailing))
            .alert("Picture in Picture isn’t available", isPresented: $isExplainingUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device can’t show the Mac’s screen in a small window over other apps.")
            }
        } else if plan == .available {
            let active = session.mirrorPiPState.isActive
            MirrorToolButton(
                glyph: PixelGlyphs.pictureInPicture,
                label: active ? "Close Picture in Picture" : "Keep watching in Picture in Picture",
                isOn: active,
                // Usable whenever the mirror runs; a PiP that can't start
                // yet starts once its layer has a picture.
                isEnabled: active || session.mirrorPiPState.isAvailable,
                action: tapped
            )
            .accessibilityIdentifier("ph.mirror.pictureInPicture")
            .requiresPro(.mirror, badge: .capsule(.bottomTrailing))
            .alert("Keep watching in Picture in Picture", isPresented: $isExplaining) {
                Button("Turn on") {
                    settings.mirrorPiPAutoStart = true
                    session.setMirrorPiPAutoStart(true)
                    session.toggleMirrorPiP()
                }
                Button("Just this once") {
                    session.toggleMirrorPiP()
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("The Mac’s screen keeps playing in a small window over other apps, with its sound. Pixel Hand stays connected while it shows. Turn it on to start it whenever you leave the app; change it in Settings › Live mirror.")
            }
        }
    }

    private func tapped() {
        if !session.mirrorPiPState.isActive, !hasExplained, !settings.mirrorPiPAutoStart {
            hasExplained = true
            isExplaining = true
            return
        }
        session.toggleMirrorPiP()
    }
}
