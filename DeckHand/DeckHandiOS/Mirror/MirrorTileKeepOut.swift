//
//  MirrorTileKeepOut.swift
//  DeckHandiOS – Mirror
//
//  The parts of a surface the floating screen tile must not cover. The
//  Pointer surface reports its pad, click strip, caption and keyboard
//  button, the Deck surface its header (window coordinates), with
//  `.mirrorTileKeepOut(_:owner:)`; the
//  tile (`MirrorOverlay`) reads them for the same session and clamps itself
//  clear with `MirrorTilePlacement` (Core).
//
//  Entries are keyed by the session's `TrackpadSender`, so two windows on
//  iPad, each with its own Mac connection, don't see each other's areas.
//  A part removes itself when it leaves the screen (strip hidden, surface
//  switched), but only the report it made itself: a replacement that
//  appeared first keeps its frame (VQ-083, `MirrorTileKeepOutRegistry`).
//

import SwiftUI

/// A part of a surface the floating tile keeps clear of.
enum MirrorTileKeepOutPart: Hashable {
    /// The pad: the tile's home is its top-trailing corner.
    case pad
    case clickStrip
    case caption
    case keyboard
    /// The deck's header row: page name, counter, pin and Edit (or Undo,
    /// the page menu and Done while editing). Build 19.
    case deckHeader
    /// The page's keys, ghost slots and Add key, reported only while the
    /// deck is being edited (VQ-083). Where it leaves no room, the tile
    /// steps aside until Done.
    case deckEditGrid
    /// The empty page's glyph, "No keys yet", message and Add keys, for the
    /// page on screen (VQ-098). At the Huge band, where it fills the page,
    /// the tile steps aside when nothing is clear.
    case deckEmptyState
}

@MainActor
@Observable
final class MirrorTileKeepOut {
    static let shared = MirrorTileKeepOut()

    /// Keyed by owner and part; each entry remembers which view reported
    /// it, so a view leaving late can't wipe its replacement's frame
    /// (VQ-083: the normal deck header's disappear after the edit header's
    /// appear left the tile over Done).
    private var frames = MirrorTileKeepOutRegistry<ObjectIdentifier, MirrorTileKeepOutPart, CGRect>()

    func set(_ frame: CGRect, for part: MirrorTileKeepOutPart, owner: AnyObject, reporter: UUID) {
        // Mutate a copy, so an unchanged report doesn't invalidate the tile.
        var next = frames
        if next.report(frame, for: part, owner: ObjectIdentifier(owner), reporter: reporter) { frames = next }
    }

    func withdraw(_ part: MirrorTileKeepOutPart, owner: AnyObject, reporter: UUID) {
        var next = frames
        if next.withdraw(part, owner: ObjectIdentifier(owner), reporter: reporter) { frames = next }
    }

    /// The pad (the tile's home anchor), the areas to avoid, and whether
    /// the tile may step aside (deck editing), converted from window
    /// coordinates into the tile's container (whose window frame is
    /// `container`). `band` decides whether an empty deck page lets the
    /// tile step aside (VQ-098).
    func plan(for owner: AnyObject?, in container: CGRect, band: TypeBand = .standard) -> MirrorTileSurfacePlan {
        guard let owner else { return MirrorTileSurfacePlan(anchor: nil, keepOut: []) }
        let key = ObjectIdentifier(owner)
        guard frames.hasParts(owner: key) else { return MirrorTileSurfacePlan(anchor: nil, keepOut: []) }
        func local(_ part: MirrorTileKeepOutPart) -> MirrorRect? {
            guard let rect = frames.frame(part, owner: key), !rect.isEmpty else { return nil }
            return MirrorRect(
                x: Double(rect.minX - container.minX),
                y: Double(rect.minY - container.minY),
                width: Double(rect.width),
                height: Double(rect.height)
            )
        }
        return MirrorTilePlacement.surfacePlan(
            bounds: MirrorRect(x: 0, y: 0, width: Double(container.width), height: Double(container.height)),
            pad: local(.pad),
            clickStrip: local(.clickStrip),
            caption: local(.caption),
            keyboard: local(.keyboard),
            deckHeader: local(.deckHeader),
            deckEditGrid: local(.deckEditGrid),
            deckEmptyState: local(.deckEmptyState),
            band: band
        )
    }
}

extension CGRect {
    init(_ rect: MirrorRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

extension MirrorRect {
    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

private struct MirrorTileKeepOutReporter: ViewModifier {
    let part: MirrorTileKeepOutPart
    let owner: AnyObject
    let isActive: Bool
    /// This reporter's identity: its withdrawal only clears its own report.
    @State private var reporter = UUID()

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { report(frame) }
                    .onChange(of: frame) { _, newFrame in report(newFrame) }
                    .onChange(of: isActive) { _, _ in report(frame) }
                    .onDisappear { MirrorTileKeepOut.shared.withdraw(part, owner: owner, reporter: reporter) }
            }
            .accessibilityHidden(true)
        }
    }

    private func report(_ frame: CGRect) {
        if isActive {
            MirrorTileKeepOut.shared.set(frame, for: part, owner: owner, reporter: reporter)
        } else {
            MirrorTileKeepOut.shared.withdraw(part, owner: owner, reporter: reporter)
        }
    }
}

extension View {
    /// Reports this view's frame as an area the floating screen tile keeps
    /// clear of, for the session that `owner` (its `TrackpadSender`) belongs to.
    /// `isActive: false` withdraws the area while the view stays on screen
    /// (the deck's edit grid outside edit mode).
    func mirrorTileKeepOut(_ part: MirrorTileKeepOutPart, owner: AnyObject, isActive: Bool = true) -> some View {
        modifier(MirrorTileKeepOutReporter(part: part, owner: owner, isActive: isActive))
    }
}
