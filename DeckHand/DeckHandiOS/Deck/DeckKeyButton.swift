//
//  DeckKeyButton.swift
//  DeckHandiOS – Deck
//
//  One deck key (UX-020): the design system's `DeckKey` (or `DeckKeyRow`
//  at AX3+) drawn from a stored `PixelHandCore.DeckKey`. Glyph from the
//  9 × 9 set, the user's 8 × 8 drawing or the app's real icon; the chord;
//  the "?" corner for Ask before running; the delivery dots from the Mac's
//  receipt. In edit mode it shows the dotted outline and the remove badge,
//  and a tap opens the inspector instead of running.
//

import PixelHandCore
import SwiftUI
import UIKit

/// The palette tokens a key can be tinted with (`KeyAppearance.tint`).
enum DeckKeyTint: String, CaseIterable, Identifiable {
    case accent
    case navy
    case mint
    case violet
    case glow

    var id: String { rawValue }

    init(token: String?) {
        self = token.flatMap(DeckKeyTint.init(rawValue:)) ?? .accent
    }

    /// `nil` for the default, so the stored deck stays small.
    var token: String? { self == .accent ? nil : rawValue }

    var title: String {
        switch self {
        case .accent: "Cobalt"
        case .navy: "Navy"
        case .mint: "Mint"
        case .violet: "Violet"
        case .glow: "Glow"
        }
    }

    var swatch: Color {
        switch self {
        case .accent: PixelHandTheme.Brand.cobalt
        case .navy: PixelHandTheme.Brand.screen
        case .mint: PixelHandTheme.Brand.mint
        case .violet: PixelHandTheme.Brand.pixelViolet
        case .glow: PixelHandTheme.Brand.glow
        }
    }

    /// The glyph colour on a light key; `nil` keeps the design default.
    var glyphColor: Color? {
        switch self {
        case .accent, .navy: nil
        case .mint: PixelHandTheme.Brand.mint
        case .violet: PixelHandTheme.Brand.pixelViolet
        case .glow: PixelHandTheme.Brand.glow
        }
    }
}

enum DeckAppIcons {
    /// The Mac app's icon, from the installed-apps list.
    static func image(for bundleID: String, in apps: [String: InstalledAppInfo]) -> Image? {
        guard let data = apps[bundleID]?.iconData, let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
    }
}

/// What a key looks like, resolved once for the button and the inspector.
struct DeckKeyFace {
    let title: String
    let glyph: GlyphBitmap
    let icon: Image?
    let chord: String?
    let kind: DeckKey.Kind
    let tint: Color?

    init(key: PixelHandCore.DeckKey, apps: [String: InstalledAppInfo], editing: Bool = false) {
        title = key.label
        chord = key.action.chordText
        let tintToken = DeckKeyTint(token: key.appearance.tint)
        tint = tintToken.glyphColor
        switch DeckGlyphs.resolve(key) {
        case let .pixel(bitmap):
            glyph = bitmap
            icon = nil
        case let .appIcon(bundleID):
            glyph = PixelGlyphs.mac
            icon = DeckAppIcons.image(for: bundleID, in: apps)
        }
        if editing {
            kind = .editing
        } else if tintToken == .navy {
            kind = .system
        } else if case .system = key.action, key.appearance.tint == nil {
            kind = .system
        } else {
            kind = .standard
        }
    }
}

struct DeckKeyButton: View {
    let key: PixelHandCore.DeckKey
    let sender: TrackpadSender
    let apps: [String: InstalledAppInfo]
    /// From the grid (`DeckGrid.keySize`); ignored for rows.
    let size: CGFloat
    let asRow: Bool
    let isEditing: Bool
    /// Edit mode: the dotted key's tap.
    var onEdit: () -> Void = {}
    /// Edit mode: the remove badge; `nil` hides it.
    var onRemove: (() -> Void)?

    @State private var tracker = DeliveryTracker()
    @State private var isConfirming = false

    var body: some View {
        let face = DeckKeyFace(key: key, apps: apps, editing: isEditing)
        Group {
            if asRow {
                DeckKeyRow(title: face.title, glyph: face.glyph, chord: face.chord, delivery: tracker.state, icon: face.icon, tint: face.tint, action: tap)
                    .overlay {
                        if isEditing {
                            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
                                .strokeBorder(PixelHandTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                DeckKey(
                    title: face.title,
                    glyph: face.glyph,
                    chord: face.chord,
                    size: size,
                    kind: face.kind,
                    asksFirst: key.confirm,
                    delivery: tracker.state,
                    icon: face.icon,
                    tint: face.tint,
                    onRemove: isEditing ? onRemove : nil,
                    action: tap
                )
            }
        }
        .accessibilityHint(isEditing ? "Opens the key’s settings" : key.action.summary())
        .confirmationDialog("Run “\(key.label)”?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Run") { run() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(key.action.summary { apps[$0]?.displayName })
        }
    }

    private func tap() {
        if isEditing {
            onEdit()
        } else if key.confirm {
            isConfirming = true
        } else {
            run()
        }
    }

    private func run() {
        GestureHaptic.light.trigger()
        let action = key.action
        let sender = sender
        Task { @MainActor in
            await DeliveryTracker.run($tracker) { await sender.sendConfirmed(action) }
        }
    }
}
