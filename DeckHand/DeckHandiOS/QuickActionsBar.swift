//
//  QuickActionsBar.swift
//  DeckHandiOS
//
//  Horizontally-scrolling, context-aware strip that takes the place of the
//  old static "QUICK ACTIONS" grid. Inspired by Xcode's Touch Bar: content
//  morphs as the Mac's frontmost app changes, so what you see always maps
//  to what's happening on the other end.
//
//  Segments (left → right):
//    1. App context pill — icon + name of the frontmost Mac app. Tap opens
//       the full shortcuts sheet for that app.
//    2. App-contextual chips — top shortcuts for `activeBundleID` (curated
//       ∪ custom, minus hidden) pulled from `ShortcutStore`. Empty state
//       offers an inline "Add shortcuts" CTA.
//    3. Global macros — Mission Control, Launchpad, Show Desktop.
//    4. Media transport — previous / play-pause / next.
//

import SwiftUI
import UIKit

/// Which auxiliary chip row the floating FABs surface in the Quick Actions
/// contextual segment. Keyboard FAB ↔ text editing; numpad FAB ↔ digits.
enum EditFABMode: String, Equatable, Sendable {
    case hidden
    case textEditing
    case numericKeypad
}

struct QuickActionsBar: View {
    let sender: TrackpadSender
    let colorScheme: ColorScheme
    let installedApps: [InstalledAppInfo]
    let activeBundleID: String?
    /// Running apps on the Mac in Cmd+Tab order (most-recently-activated
    /// first). Drives the app-switcher menu next to the app pill.
    let runningBundleIDs: [String]
    /// AX-derived snapshot of what's currently interactable on the Mac.
    /// When this carries a `.dialog(...)`, the middle segment swaps from
    /// per-app shortcut chips to the dialog's buttons.
    let uiContext: UIContextSnapshot
    /// Which extra row (if any) is shown after the app shortcut chips.
    /// Seeded from AX and flipped by the two floating FABs in
    /// `StreamDeckGridView`. Mutually exclusive: only one auxiliary row
    /// at a time.
    let editFABMode: EditFABMode
    /// Invoked when the user taps the app pill, or the "Add shortcuts" CTA
    /// in the empty middle segment. Parent is responsible for presenting
    /// `AppShortcutsSheet`.
    let onOpenAppSheet: (InstalledAppInfo) -> Void

    @ObservedObject private var store = ShortcutStore.shared

    /// How many app-contextual shortcut chips to surface inline before the
    /// user has to open the sheet. Six feels right at ~iPad width; the rest
    /// are reachable via tapping the app pill.
    private let maxContextualChips = 6

    private var activeApp: InstalledAppInfo? {
        guard let bundleID = activeBundleID else { return nil }
        return installedApps.first(where: { $0.bundleID == bundleID })
    }

    private var contextualBindings: [AppShortcutBinding] {
        guard let bundleID = activeBundleID else { return [] }
        // Compress the per-app shortcut slot when a text field is also being
        // surfaced — so a Chrome user keeps quick access to e.g. New Tab
        // while also seeing Cut / Copy / Paste in the same row.
        let cap = hasAuxiliaryEditRow ? 3 : maxContextualChips
        return Array(store.bindings(for: bundleID).prefix(cap))
    }

    /// True when either the text-edit row or the numpad row is visible.
    private var hasAuxiliaryEditRow: Bool {
        editFABMode != .hidden
    }

    /// Kind for the Cut/Copy/Paste row — only when `editFABMode` is
    /// `.textEditing`. AX classification refines secure vs text; manual
    /// activation with no AX field defaults to `.text`.
    private var textEditRowKind: TextFieldContext.Kind? {
        guard editFABMode == .textEditing else { return nil }
        if case .textField(let ctx) = uiContext { return ctx.kind }
        return .text
    }

    private var showNumericKeypad: Bool {
        editFABMode == .numericKeypad
    }

    /// Running apps the user can switch to, excluding whichever one is already
    /// frontmost. Resolved against `installedApps` so we have icons + names.
    private var otherRunningApps: [InstalledAppInfo] {
        let lookup = InstalledAppInfo.byBundleID(installedApps)
        return runningBundleIDs.compactMap { bundleID -> InstalledAppInfo? in
            guard bundleID != activeBundleID else { return nil }
            return lookup[bundleID]
        }
    }

    var body: some View {
        Group {
            if case .dialog(let ctx) = uiContext {
                // Takeover layout — mirrors how Apple's Touch Bar went
                // "all-hands" for NSAlerts: static macros/media hide so
                // the dialog's message + buttons get the full width.
                dialogTakeoverBar(ctx)
                    .id("takeover-\(ctx.revision)")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .center)),
                        removal: .opacity
                    ))
            } else {
                normalBar
                    .transition(.opacity)
            }
        }
        .frame(height: 64)
        .background(barBackground)
        .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .strokeBorder(PixelHandTheme.color(PaletteTokens.hairline, for: colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeBundleID)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isDialogActive)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: editFABMode)
    }

    /// `true` while the Mac is reporting an active modal dialog/sheet. Drives
    /// the full-width takeover layout.
    private var isDialogActive: Bool {
        if case .dialog = uiContext { return true }
        return false
    }

    private var normalBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                appContextSegment
                segmentDivider
                contextualSegment
                segmentDivider
                globalSegment
                segmentDivider
                mediaSegment
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func dialogTakeoverBar(_ ctx: DialogContext) -> some View {
        HStack(spacing: 10) {
            appContextSegment
            segmentDivider
            DialogInfoButton(title: ctx.title, message: ctx.message, colorScheme: colorScheme)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(ctx.buttons) { button in
                    DialogButtonChip(button: button, colorScheme: colorScheme) {
                        (button.isDefault ? GestureHaptic.medium : .light).trigger()
                        return await sender.sendConfirmed(.contextAction(id: button.id))
                    }
                }
            }
            .requiresPro(.decks) // Store lane
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Segments

    @ViewBuilder
    private var appContextSegment: some View {
        HStack(spacing: 2) {
            if let app = activeApp {
                AppContextPill(app: app, colorScheme: colorScheme) {
                    GestureHaptic.light.trigger()
                    onOpenAppSheet(app)
                }
                .id("pill-\(app.bundleID)")
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                IdlePill(colorScheme: colorScheme)
                    .transition(.opacity)
            }

            if !otherRunningApps.isEmpty {
                AppSwitcherMenu(apps: otherRunningApps, colorScheme: colorScheme) { app in
                    GestureHaptic.medium.trigger()
                    Task { await sender.sendLaunchApp(app.bundleID) }
                }
            }
        }
    }

    // The contextual middle segment is only used in the normal (non-dialog)
    // layout — the takeover bar renders dialog content in its own path.
    //
    // Layout policy:
    //   • App shortcuts are ALWAYS shown (up to `maxContextualChips`), even
    //     when a text field is focused — just compressed to 3 so the row
    //     stays reasonable. This is the "append, don't replace" rule that
    //     lets users in Chrome / Cursor / Slack etc. keep flipping between
    //     app commands and edit actions without losing either side.
    //   • When AX surfaced a focused text/numeric/secure field, the edit
    //     chips are appended after a thin divider.
    @ViewBuilder
    private var contextualSegment: some View {
        HStack(spacing: 8) {
            shortcutChipsSegment
                .id("ctx-\(activeBundleID ?? "none")")
                .requiresPro(.decks) // Store lane

            if showNumericKeypad {
                chipDivider
                numpadChips
                    .id("numpad-row")
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if let kind = textEditRowKind {
                chipDivider
                textFieldChips(kind)
                    .id("textfield-\(kind.rawValue)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    private var numpadChips: some View {
        HStack(spacing: 5) {
            ForEach(NumpadAction.all) { key in
                NumpadChip(key: key, colorScheme: colorScheme) {
                    (key.isPrimary ? GestureHaptic.medium : .light).trigger()
                    Task { await sender.sendShortcut(key.keys) }
                }
            }
        }
    }

    /// Slim divider rendered inline between the app-shortcut chips and the
    /// text-edit chips when both are present. Shorter than the main
    /// segment divider so the appended section feels tied to the app row.
    private var chipDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 24)
    }

    @ViewBuilder
    private var shortcutChipsSegment: some View {
        HStack(spacing: 8) {
            if contextualBindings.isEmpty {
                if let app = activeApp {
                    AddShortcutsChip(appName: app.displayName, colorScheme: colorScheme) {
                        GestureHaptic.light.trigger()
                        onOpenAppSheet(app)
                    }
                } else {
                    PlaceholderChip(text: "Focus an app on your Mac",
                                    systemImage: "dot.radiowaves.left.and.right",
                                    colorScheme: colorScheme)
                }
            } else {
                ForEach(contextualBindings) { binding in
                    ShortcutChip(binding: binding, colorScheme: colorScheme) {
                        GestureHaptic.medium.trigger()
                        return await sender.sendConfirmed(
                            .appShortcut(bundleID: binding.bundleID, keys: binding.keys)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func textFieldChips(_ kind: TextFieldContext.Kind) -> some View {
        HStack(spacing: 6) {
            ForEach(TextFieldAction.actions(for: kind)) { action in
                TextFieldChip(action: action, colorScheme: colorScheme) {
                    (action.isPrimary ? GestureHaptic.medium : .light).trigger()
                    Task { await sender.sendShortcut(action.keys) }
                }
            }
        }
    }

    private var globalSegment: some View {
        HStack(spacing: 4) {
            IconButton(symbol: "macwindow.on.rectangle", colorScheme: colorScheme) {
                GestureHaptic.medium.trigger()
                Task { await sender.sendSystemAction(.missionControl) }
            }
            IconButton(symbol: "square.grid.3x3.fill", colorScheme: colorScheme) {
                GestureHaptic.medium.trigger()
                Task { await sender.sendSystemAction(.launchpad) }
            }
            IconButton(symbol: "macwindow", colorScheme: colorScheme) {
                GestureHaptic.medium.trigger()
                Task { await sender.sendSystemAction(.showDesktop) }
            }
        }
    }

    private var mediaSegment: some View {
        HStack(spacing: 4) {
            IconButton(symbol: "backward.fill", colorScheme: colorScheme) {
                GestureHaptic.light.trigger()
                Task { await sender.sendMediaKey(.previous) }
            }
            IconButton(symbol: "playpause.fill", colorScheme: colorScheme) {
                GestureHaptic.medium.trigger()
                Task { await sender.sendMediaKey(.playPause) }
            }
            IconButton(symbol: "forward.fill", colorScheme: colorScheme) {
                GestureHaptic.light.trigger()
                Task { await sender.sendMediaKey(.next) }
            }
        }
    }

    // MARK: - Chrome

    private var segmentDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 28)
    }

    private var barBackground: some View {
        PixelHandTheme.color(PaletteTokens.fill, for: colorScheme)
    }
}
