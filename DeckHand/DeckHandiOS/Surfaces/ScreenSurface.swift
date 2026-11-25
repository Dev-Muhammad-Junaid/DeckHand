//
//  ScreenSurface.swift
//  DeckHandiOS – Surfaces
//
//  The Screen surface (UX-006): the docked `MirrorPane` across the top with
//  the trackpad under it, so the Mac can be watched and driven from one
//  surface (iPhone portrait, iPad portrait and wide). Where the canvas is
//  too short for both (iPhone landscape rail, small split windows), the
//  pane takes the whole canvas. Choosing the surface starts the mirror;
//  after the person stops it, the navy empty state with "Show screen"
//  (its button carries the Pro lock in the free plan). Under the pane is
//  the Pointer surface's pad, not the classic trackpad (build 18 QA).
//  OR-16: where the pane shows with no trackpad (the screen-only preset,
//  or this surface when the pad doesn't fit), its toolbar offers pointer
//  control on the picture.
//  Spec: `Product/Design/03-Layout-Strategy.md` (Option A), board
//  "New features" › Mirror with display and desktop chrome.
//

import SwiftUI

struct ScreenSurface: View {
    let session: ControlSessionModel
    let macName: String
    /// The trackpad goes under the pane when it fits. The iPad Split preset
    /// draws its own pad next to the deck, so it turns this off (UX-007).
    var includesTrackpad = true
    /// The shell's app dock carries the keyboard button (UX-005).
    var keyboardInDock = true
    /// OR-16: no trackpad shows anywhere else in this arrangement (the
    /// Screen tab, the screen-only preset), so when the pane stands alone
    /// its toolbar offers pointer control on the picture. Off where a pad
    /// sits beside it (Split, Duo).
    var screenOnly = false

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.entitlements) private var entitlements

    /// The trackpad under the pane needs at least this much to be usable.
    static let minimumTrackpadHeight: CGFloat = 200
    /// The pane never takes more than this share of the canvas when the
    /// trackpad sits under it.
    static let maximumPaneShare: CGFloat = 0.62

    var body: some View {
        GeometryReader { proxy in
            if session.isMirrorActive {
                let layout = includesTrackpad
                    ? Self.split(size: proxy.size, aspect: MirrorPicture.aspect(session))
                    : (pane: proxy.size.height, showsTrackpad: false)
                VStack(spacing: PixelHandTheme.Space.md) {
                    MirrorPane(
                        session: session,
                        macName: macName,
                        offersPointerControl: PicturePointerControl.isOffered(
                            screenOnly: screenOnly,
                            showsTrackpad: layout.showsTrackpad
                        )
                    )
                    .frame(height: layout.pane)
                    if layout.showsTrackpad, let sender = session.sender {
                        // The Pointer surface's pad (dot field, click strip,
                        // caption), never the classic TrackpadView with its
                        // slider and action row (VQ-059).
                        PointerSurface(
                            sender: sender,
                            clipboard: session.clipboard,
                            margin: 0,
                            keyboardInDock: keyboardInDock
                        )
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            } else {
                PixelSurface(cornerRadius: PixelHandTheme.Radius.pane) {
                    PHEmptyState(
                        glyph: PixelGlyphs.screen,
                        title: macName,
                        message: "The screen is off. Show it to watch the Mac while you drive it.",
                        primaryTitle: "Show screen",
                        primaryAction: { session.toggleMirror(settings: settings) },
                        primaryRequires: .mirror
                    )
                }
            }
        }
        // Choosing the Screen surface starts the mirror: it's the surface's
        // only purpose (VQ-046). Stopping it from the toolbar is remembered
        // for this session, so the empty state then stays put.
        .onAppear { startIfWanted() }
        .onChange(of: session.isMirrorActive) { wasActive, isActive in
            if wasActive && !isActive { ScreenAutoStart.stopped(session) }
        }
    }

    private func startIfWanted() {
        guard !session.isMirrorActive,
              session.sender != nil,
              entitlements.allows(.mirror),
              !ScreenAutoStart.wasStopped(session) else { return }
        session.toggleMirror(settings: settings)
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

/// Sessions whose mirror the person stopped, so the Screen surface doesn't
/// start it again on its next appearance (rotation, preset change).
@MainActor
private enum ScreenAutoStart {
    private static var stoppedSessions = Set<ObjectIdentifier>()

    static func stopped(_ session: ControlSessionModel) {
        stoppedSessions.insert(ObjectIdentifier(session))
    }

    static func wasStopped(_ session: ControlSessionModel) -> Bool {
        stoppedSessions.contains(ObjectIdentifier(session))
    }
}
