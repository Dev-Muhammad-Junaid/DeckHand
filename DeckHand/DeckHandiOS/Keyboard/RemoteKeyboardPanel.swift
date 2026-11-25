//
//  RemoteKeyboardPanel.swift
//  DeckHandiOS
//
//  The trackpad's keyboard panel: a live typing field (every letter goes
//  to the Mac as you type), a row of keys that aren't characters (Escape,
//  Tab, arrows, Backspace, Return) with latching ⌘ ⌥ ⌃ ⇧, and Paste to Mac.
//  Escape and Tab are labelled in text; the row fades at its trailing edge
//  when it runs on (build 18 QA, VQ-034).
//

import SwiftUI

struct RemoteKeyboardPanel: View {
    let sender: TrackpadSender
    var clipboard: RemoteClipboard?
    let colorScheme: ColorScheme
    /// A key or text went to the Mac (forgets what a gesture opened).
    var onActivity: () -> Void = {}

    @EnvironmentObject private var settings: DeckHandSettings
    @State private var latched: [KeyModifier] = []
    /// A Return held back while the person confirms the app (VQ-036).
    @State private var heldReturn: (() -> Void)?
    private let target = TypingTarget.shared

    private struct KeyButton: Identifiable {
        let key: RemoteKey
        let symbol: String
        let label: String
        /// Shown as text instead of the symbol, where the symbol alone
        /// doesn't say what the key is (VQ-034: Escape read as "⟲").
        var text: String?
        var id: RemoteKey { key }
    }

    private struct ModifierButton: Identifiable {
        let modifier: KeyModifier
        let glyph: String
        let label: String
        var id: KeyModifier { modifier }
    }

    private static let keys: [KeyButton] = [
        KeyButton(key: .escape, symbol: "escape", label: "Escape", text: "esc"),
        KeyButton(key: .tab, symbol: "arrow.right.to.line", label: "Tab", text: "tab"),
        KeyButton(key: .left, symbol: "arrow.left", label: "Left arrow"),
        KeyButton(key: .down, symbol: "arrow.down", label: "Down arrow"),
        KeyButton(key: .up, symbol: "arrow.up", label: "Up arrow"),
        KeyButton(key: .right, symbol: "arrow.right", label: "Right arrow"),
        KeyButton(key: .delete, symbol: "delete.left", label: "Delete"),
        KeyButton(key: .return, symbol: "return", label: "Return"),
    ]

    /// "Typing into Messages": where keys go, always in view (VQ-036).
    private var targetLine: some View {
        HStack(spacing: PixelHandTheme.Space.xs) {
            PHGlyph(glyph: PixelGlyphs.keyboard, pitch: CGFloat(PixelPitch.badge), stepsWithType: true)
                .foregroundStyle(.secondary)
            Text(TypingTargetGuard.caption(frontApp: target.frontApp))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ph.keyboard.target")
        .alert(
            "Send Return to \(target.frontApp ?? "the Mac")?",
            isPresented: Binding(get: { heldReturn != nil }, set: { if !$0 { heldReturn = nil } })
        ) {
            Button("Send") {
                target.guardrail.confirmed(target.frontApp)
                heldReturn?()
                heldReturn = nil
            }
            Button("Cancel", role: .cancel) { heldReturn = nil }
        } message: {
            Text("\(target.frontApp ?? "Another app") is in front on the Mac now, not \(target.guardrail.acknowledgedApp ?? "the app you were typing into"). Return might send or submit something there.")
        }
    }

    /// Sends now, or holds a Return that would land in an app the person
    /// hasn't typed into (the front app changed under them).
    private func guardReturn(if isReturn: Bool, send: @escaping () -> Void) {
        if isReturn, target.guardrail.shouldConfirmReturn(frontApp: target.frontApp) {
            heldReturn = send
            return
        }
        if !isReturn { target.guardrail.typed(into: target.frontApp) }
        send()
    }

    private static let modifiers: [ModifierButton] = [
        ModifierButton(modifier: .command, glyph: "⌘", label: "Command"),
        ModifierButton(modifier: .option, glyph: "⌥", label: "Option"),
        ModifierButton(modifier: .control, glyph: "⌃", label: "Control"),
        ModifierButton(modifier: .shift, glyph: "⇧", label: "Shift"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            targetLine

            LiveTypingField(
                placeholder: "Type here: it goes straight to the Mac",
                latchedModifiers: latched,
                onEdit: { edit in
                    onActivity()
                    guardReturn(if: edit.insert.contains("\n")) {
                        Task { await sender.sendTypingEdit(edit) }
                    }
                },
                onKey: { key, modifiers in
                    onActivity()
                    guardReturn(if: key == .return) {
                        Task { await sender.sendKey(key, modifiers: modifiers) }
                    }
                },
                onChord: { keys in
                    onActivity()
                    Task { await sender.sendShortcut(keys) }
                },
                onModifiersUsed: { latched = [] }
            )
            .frame(height: 40)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                    .fill(PixelHandTheme.color(PaletteTokens.fill, for: colorScheme))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.modifiers) { item in
                        let modifier = item.modifier
                        let isOn = latched.contains(modifier)
                        Button {
                            if isOn { latched.removeAll { $0 == modifier } } else { latched.append(modifier) }
                            GestureHaptic.selection.trigger()
                        } label: {
                            Text(item.glyph)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(minWidth: 36, minHeight: 36)
                                .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.85))
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isOn ? PixelHandTheme.accent : PixelHandTheme.color(PaletteTokens.fill, for: colorScheme))
                                )
                        }
                        .buttonStyle(.plain)
                        .phosphorFocusable(cornerRadius: 8)
                        .accessibilityLabel(item.label)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .accessibilityHint("Holds for the next key")
                        .accessibilityIdentifier("ph.keyboard.modifier")
                    }

                    Divider().frame(height: 28)

                    ForEach(Self.keys) { item in
                        let key = item.key
                        Button {
                            onActivity()
                            let modifiers = latched
                            latched = []
                            GestureHaptic.light.trigger()
                            guardReturn(if: key == .return) {
                                Task { await sender.sendKey(key, modifiers: modifiers) }
                            }
                        } label: {
                            Group {
                                if let text = item.text {
                                    Text(text)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 4)
                                } else {
                                    Image(systemName: item.symbol)
                                        .font(.system(size: 14, weight: key == .return ? .semibold : .medium))
                                }
                            }
                                .frame(minWidth: 40, minHeight: 36)
                                .foregroundStyle(key == .return ? Color.white : Color.primary.opacity(0.85))
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(key == .return ? PixelHandTheme.accent : PixelHandTheme.color(PaletteTokens.fill, for: colorScheme))
                                )
                        }
                        .buttonStyle(.plain)
                        .phosphorFocusable(cornerRadius: 8)
                        .accessibilityLabel(item.label)
                        .accessibilityIdentifier("ph.keyboard.key")
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, TrailingFade.overflowWidth)
            }
            .frame(maxWidth: .infinity)
            // The row runs past the edge on a phone: fade it so it reads
            // as "more this way" (VQ-034; build 23: a key wide, it was
            // 16 pt and went unseen).
            .mask { TrailingFade() }

            ClipboardRow(sender: sender, clipboard: clipboard, colorScheme: colorScheme, onActivity: onActivity)
        }
    }
}
