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
//  switched).
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
}

@MainActor
@Observable
final class MirrorTileKeepOut {
    static let shared = MirrorTileKeepOut()

    private var frames: [ObjectIdentifier: [MirrorTileKeepOutPart: CGRect]] = [:]

    func set(_ frame: CGRect?, for part: MirrorTileKeepOutPart, owner: AnyObject) {
        let key = ObjectIdentifier(owner)
        var parts = frames[key] ?? [:]
        guard parts[part] != frame else { return }
        parts[part] = frame
        frames[key] = parts.isEmpty ? nil : parts
    }

    /// The pad (the tile's home anchor) and the areas to avoid, converted
    /// from window coordinates into the tile's container (whose window
    /// frame is `container`).
    func layout(for owner: AnyObject?, in container: CGRect) -> (anchor: CGRect?, keepOut: [CGRect]) {
        guard let owner, let parts = frames[ObjectIdentifier(owner)] else { return (nil, []) }
        func local(_ part: MirrorTileKeepOutPart) -> MirrorRect? {
            guard let rect = parts[part], !rect.isEmpty else { return nil }
            return MirrorRect(
                x: Double(rect.minX - container.minX),
                y: Double(rect.minY - container.minY),
                width: Double(rect.width),
                height: Double(rect.height)
            )
        }
        let layout = MirrorTilePlacement.surfaceLayout(
            bounds: MirrorRect(x: 0, y: 0, width: Double(container.width), height: Double(container.height)),
            pad: local(.pad),
            clickStrip: local(.clickStrip),
            caption: local(.caption),
            keyboard: local(.keyboard),
            deckHeader: local(.deckHeader)
        )
        return (layout.anchor.map { CGRect($0) }, layout.keepOut.map { CGRect($0) })
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

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { MirrorTileKeepOut.shared.set(frame, for: part, owner: owner) }
                    .onChange(of: frame) { _, newFrame in
                        MirrorTileKeepOut.shared.set(newFrame, for: part, owner: owner)
                    }
                    .onDisappear { MirrorTileKeepOut.shared.set(nil, for: part, owner: owner) }
            }
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Reports this view's frame as an area the floating screen tile keeps
    /// clear of, for the session that `owner` (its `TrackpadSender`) belongs to.
    func mirrorTileKeepOut(_ part: MirrorTileKeepOutPart, owner: AnyObject) -> some View {
        modifier(MirrorTileKeepOutReporter(part: part, owner: owner))
    }
}
