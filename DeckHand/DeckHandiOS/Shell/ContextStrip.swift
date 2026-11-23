//
//  ContextStrip.swift
//  DeckHandiOS – Shell
//
//  The context strip (UX-005): one scrolling row of `ContextChip`s between
//  the canvas and the app dock. What it shows comes from
//  `ContextStripPlan`: a dialog's buttons first (default first on compact),
//  otherwise the front app's chips, then text editing when a field has focus,
//  then "+ Shortcuts" (the rest of the app's shortcuts). Free plan: media
//  keys and a dashed "App chips · Pro" chip.
//
//  Dynamic Type bands (`07-Polish-Spec.md` §6): standard is one row; large
//  wraps into two rows with the chord under the label (the chip does that);
//  huge collapses into one "Actions" button that opens a menu.
//
//  On short windows the app dock folds into a leading app chip
//  (`foldedApps`): the front app's icon with a menu of running apps.
//  Board: `.strip`, `.chip`, `.chip--app` (iPhone SE).
//

import SwiftUI

struct ContextStrip: View {
    let sender: TrackpadSender
    let mode: ContextStripPlan.Mode
    let frontApp: InstalledAppInfo?
    let bindings: [AppShortcutBinding]
    /// When set, the dock is folded into a leading app chip with these apps.
    var foldedApps: [InstalledAppInfo]?
    var margin: CGFloat = PixelHandTheme.Space.lg
    let onOpenAppSheet: (InstalledAppInfo) -> Void
    let onActivate: (InstalledAppInfo) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.typeBand == .huge {
                hugeRow
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    content
                        .padding(.leading, margin)
                        .padding(.trailing, PixelHandTheme.Space.xl)
                        .padding(.vertical, PixelHandTheme.Space.xs)
                }
                .mask(TrailingFade(width: PixelHandTheme.Space.xl))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ContextStripPlan.accessibilityLabel(mode: mode, appName: frontApp?.displayName))
    }

    // MARK: Standard and large bands

    @ViewBuilder
    private var content: some View {
        let items = self.items
        if typeSize.typeBand == .large, items.count > 2 {
            // Two rows: the first half, then the rest, so reading order
            // still runs left to right, top to bottom.
            let split = (items.count + 1) / 2
            HStack(alignment: .top, spacing: PixelHandTheme.Space.sm) {
                leading
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    row(Array(items[..<split]))
                    row(Array(items[split...]))
                }
            }
        } else {
            HStack(spacing: PixelHandTheme.Space.sm) {
                leading
                row(items)
            }
        }
    }

    private func row(_ items: [StripItem]) -> some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            ForEach(items) { item in
                StripChip(item: item, sender: sender, frontApp: frontApp, onOpenAppSheet: onOpenAppSheet)
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let foldedApps {
            FoldedDockChip(frontApp: frontApp, apps: foldedApps, onActivate: onActivate, onShortcuts: onOpenAppSheet)
        }
        if case .dialog(let title, let message, _) = mode, typeSize.typeBand == .standard,
           let text = [title, message].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PixelHandTheme.ink2)
                .lineLimit(2)
                .frame(maxWidth: 96, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Huge band

    private var hugeRow: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            leading
            Menu {
                ForEach(menuItems) { item in
                    Button(item.title) { StripChip.perform(item, sender: sender, frontApp: frontApp, onOpenAppSheet: onOpenAppSheet) }
                }
            } label: {
                HStack(spacing: PixelHandTheme.Space.sm) {
                    PHGlyph(glyph: PixelGlyphs.deck, pitch: PixelPitch.chip)
                        .foregroundStyle(PixelHandTheme.accent)
                    Text(menuTitle)
                        .font(.phChip)
                        .foregroundStyle(PixelHandTheme.ink)
                        .lineLimit(2)
                }
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .frame(minHeight: PixelHandTheme.ControlHeight.standard)
                .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                        .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
                )
            }
            .disabled(menuItems.isEmpty)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, margin)
        .padding(.vertical, PixelHandTheme.Space.xs)
    }

    /// The huge band's menu: everything that does something.
    private var menuItems: [StripItem] {
        items.filter { item in
            if case .idle = item { return false }
            if case .proUpsell = item { return false }
            return true
        }
    }

    private var menuTitle: String {
        if case .dialog = mode { return "Dialog buttons" }
        return "Actions"
    }

    // MARK: Items

    private var items: [StripItem] {
        switch mode {
        case .dialog(_, _, let buttons):
            return buttons.map(StripItem.dialog)
        case .app(let limit, let editing):
            var result = bindings.prefix(limit).map(StripItem.shortcut)
            if let editing {
                result += TextFieldAction.actions(for: editing).map(StripItem.edit)
            }
            if frontApp != nil {
                result.append(.moreShortcuts)
            }
            return result
        case .idle:
            return [.idle]
        case .free:
            return [.media(.previous), .media(.playPause), .media(.next), .proUpsell]
        }
    }
}

// MARK: - Items

enum StripItem: Identifiable {
    case dialog(DialogButton)
    case shortcut(AppShortcutBinding)
    case edit(TextFieldAction)
    case media(MediaKey)
    case moreShortcuts
    case proUpsell
    case idle

    var id: String {
        switch self {
        case .dialog(let button): "dialog-\(button.id)"
        case .shortcut(let binding): "shortcut-\(binding.id)"
        case .edit(let action): "edit-\(action.id)"
        case .media(let key): "media-\(key.rawValue)"
        case .moreShortcuts: "more"
        case .proUpsell: "pro"
        case .idle: "idle"
        }
    }

    var title: String {
        switch self {
        case .dialog(let button): button.title
        case .shortcut(let binding): binding.shortDisplayName
        case .edit(let action): action.label
        case .media(.previous): "Previous track"
        case .media(.playPause): "Play or pause"
        case .media(.next): "Next track"
        case .moreShortcuts: "Shortcuts"
        case .proUpsell: "App chips · Pro"
        case .idle: "Bring an app to the front on the Mac"
        }
    }
}

/// One chip with its own delivery receipt.
private struct StripChip: View {
    let item: StripItem
    let sender: TrackpadSender
    let frontApp: InstalledAppInfo?
    let onOpenAppSheet: (InstalledAppInfo) -> Void

    @State private var delivery = DeliveryTracker()

    var body: some View {
        switch item {
        case .dialog(let button):
            chip(title: button.title, chord: button.isDefault ? "↩" : (button.isCancel ? "esc" : nil),
                 kind: button.isDefault ? .defaultAction : .dialog)
        case .shortcut(let binding):
            chip(title: binding.shortDisplayName, chord: binding.keyGlyphs)
        case .edit(let action):
            chip(title: action.label, chord: ChordText.glyphs(action.keys))
        case .media(let key):
            chip(title: item.title, glyph: Self.glyph(for: key), iconOnly: true)
        case .moreShortcuts:
            ContextChip(title: "Shortcuts", glyph: PixelGlyphs.add, kind: .suggestion) {
                if let frontApp { onOpenAppSheet(frontApp) }
            }
        case .proUpsell:
            ContextChip(title: "App chips · Pro", kind: .suggestion) {}
                .requiresPro(.decks)
        case .idle:
            HStack(spacing: PixelHandTheme.Space.sm) {
                StatusPixel(state: .off, size: 6)
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .lineLimit(1)
            }
            .frame(minHeight: PixelHandTheme.ControlHeight.standard)
            .accessibilityElement(children: .combine)
        }
    }

    private func chip(title: String, glyph: GlyphBitmap? = nil, chord: String? = nil, kind: ContextChip.Kind = .standard, iconOnly: Bool = false) -> some View {
        ContextChip(title: iconOnly ? "" : title, glyph: glyph, chord: chord, kind: kind, delivery: delivery.state, accessibilityTitle: title) {
            Self.haptic(for: item).trigger()
            Task { await DeliveryTracker.run($delivery) { await Self.send(item, sender: sender) } }
        }
    }

    // Shared with the huge band's menu.

    @MainActor
    static func perform(_ item: StripItem, sender: TrackpadSender, frontApp: InstalledAppInfo?, onOpenAppSheet: (InstalledAppInfo) -> Void) {
        switch item {
        case .moreShortcuts:
            if let frontApp { onOpenAppSheet(frontApp) }
        case .proUpsell, .idle:
            break
        default:
            haptic(for: item).trigger()
            Task { _ = await send(item, sender: sender) }
        }
    }

    @MainActor
    static func send(_ item: StripItem, sender: TrackpadSender) async -> CommandDelivery {
        switch item {
        case .dialog(let button):
            await sender.sendConfirmed(.contextAction(id: button.id))
        case .shortcut(let binding):
            await sender.sendConfirmed(.appShortcut(bundleID: binding.bundleID, keys: binding.keys))
        case .edit(let action):
            await sender.sendConfirmed(.shortcut(keys: action.keys))
        case .media(let key):
            await sender.sendConfirmed(.media(key: key))
        case .moreShortcuts, .proUpsell, .idle:
            .sent
        }
    }

    static func haptic(for item: StripItem) -> GestureHaptic {
        switch item {
        case .dialog(let button): button.isDefault ? .medium : .light
        case .shortcut: .medium
        default: .light
        }
    }

    static func glyph(for key: MediaKey) -> GlyphBitmap {
        switch key {
        case .previous: PixelGlyphs.spaceLeft
        case .playPause: PixelGlyphs.play
        case .next: PixelGlyphs.spaceRight
        }
    }
}

/// The app dock folded into the strip on short windows: the front app's
/// icon and a chevron; the menu switches apps or opens the shortcuts.
private struct FoldedDockChip: View {
    let frontApp: InstalledAppInfo?
    let apps: [InstalledAppInfo]
    let onActivate: (InstalledAppInfo) -> Void
    let onShortcuts: (InstalledAppInfo) -> Void

    var body: some View {
        Menu {
            if let frontApp {
                Button("Shortcuts for \(frontApp.displayName)") { onShortcuts(frontApp) }
                Divider()
            }
            ForEach(apps) { app in
                Button {
                    GestureHaptic.medium.trigger()
                    onActivate(app)
                } label: {
                    if app.bundleID == frontApp?.bundleID {
                        Label(app.displayName, systemImage: "checkmark")
                    } else {
                        Text(app.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: PixelHandTheme.Space.sm) {
                if let frontApp {
                    AppIconTile(app: frontApp, side: 28)
                } else {
                    StatusPixel(state: .off, size: 8)
                        .frame(width: 28, height: 28)
                }
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PixelHandTheme.ink2)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(minHeight: PixelHandTheme.ControlHeight.standard)
            .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                    .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel(frontApp.map { "\($0.displayName), switch app" } ?? "Switch app")
    }
}
