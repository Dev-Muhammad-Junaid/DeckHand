//
//  ScreenSurface.swift
//  DeckHandiOS – Surfaces
//
//  The Screen surface (UX-006): the docked `MirrorPane` across the top with
//  the trackpad under it, so the Mac can be watched and driven from one
//  surface (iPhone portrait, iPad portrait and wide). Where the canvas is
//  too short for both (iPhone landscape rail, small split windows), the
//  pane takes the whole canvas. Before the mirror starts: the navy empty
//  state with "Show screen".
//  Spec: `Product/Design/03-Layout-Strategy.md` (Option A), board
//  "New features" › Mirror with display and desktop chrome.
//

import SwiftUI

struct ScreenSurface: View {
    let session: ControlSessionModel
    let macName: String

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.colorScheme) private var colorScheme

    /// The trackpad under the pane needs at least this much to be usable.
    static let minimumTrackpadHeight: CGFloat = 200
    /// The pane never takes more than this share of the canvas when the
    /// trackpad sits under it.
    static let maximumPaneShare: CGFloat = 0.62

    var body: some View {
        GeometryReader { proxy in
            if session.isMirrorActive {
                let layout = Self.split(size: proxy.size, aspect: MirrorPicture.aspect(session))
                VStack(spacing: PixelHandTheme.Space.md) {
                    MirrorPane(session: session, macName: macName)
                        .frame(height: layout.pane)
                    if layout.showsTrackpad, let sender = session.sender {
                        TrackpadView(sender: sender, colorScheme: colorScheme, clipboard: session.clipboard)
                            .frame(maxHeight: .infinity)
                            .transition(.opacity)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            } else {
                PixelSurface(cornerRadius: PixelHandTheme.Radius.pane) {
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

    /// Pane height and whether the trackpad fits under it. The pane is as
    /// tall as the picture at full width (plus room for its chrome on very
    /// wide pictures), capped at `maximumPaneShare`; when that leaves less
    /// than `minimumTrackpadHeight`, the pane takes everything.
    static func split(size: CGSize, aspect: CGFloat) -> (pane: CGFloat, showsTrackpad: Bool) {
        guard size.height > 0, size.width > 0 else { return (0, false) }
        let picture = size.width / max(aspect, 0.1)
        let pane = min(max(picture, 200), size.height * maximumPaneShare).rounded()
        let rest = size.height - pane - PixelHandTheme.Space.md
        guard rest >= minimumTrackpadHeight else { return (size.height, false) }
        return (pane, true)
    }
}
