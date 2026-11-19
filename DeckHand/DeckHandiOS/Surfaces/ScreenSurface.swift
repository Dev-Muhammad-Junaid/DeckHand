//
//  ScreenSurface.swift
//  DeckHandiOS – Surfaces
//
//  The Screen surface as the shell hosts it today: a navy pane that holds
//  the mirror lane's `MirrorOverlay`, or an empty state that starts the live
//  screen. The Mirror lane turns this into the docked `MirrorPane` (UX-006).
//

import SwiftUI

struct ScreenSurface: View {
    let session: ControlSessionModel
    let macName: String

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        GeometryReader { proxy in
            PixelSurface(cornerRadius: PixelHandTheme.Radius.pane, showsGrid: !session.isMirrorActive) {
                if session.isMirrorActive {
                    MirrorOverlay(session: session, containerSize: proxy.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    PHEmptyState(
                        glyph: PixelGlyphs.screen,
                        title: "See \(macName)’s screen",
                        message: "Watch the Mac live while you drive it from here.",
                        primaryTitle: "Show screen",
                        primaryAction: { session.toggleMirror(settings: settings) }
                    )
                    .requiresPro(.mirror)
                }
            }
        }
    }
}
