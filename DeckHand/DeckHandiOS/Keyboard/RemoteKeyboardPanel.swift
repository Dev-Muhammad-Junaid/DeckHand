//
//  RemoteKeyboardPanel.swift
//  DeckHandiOS
//
//  The trackpad's keyboard panel: a live typing field (every letter goes
//  to the Mac as you type), a row of keys that aren't characters (Escape,
//  Tab, arrows, Backspace, Return) with latching ⌘ ⌥ ⌃ ⇧, and Paste to Mac.
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

    private struct KeyButton: Identifiable {
        let key: RemoteKey
        let symbol: String
        let label: String
        var id: RemoteKey { key }
    }

    private struct ModifierButton: Identifiable {
        let modifier: KeyModifier
        let glyph: String
        let label: String
        var id: KeyModifier { modifier }
    }

    private static let keys: [KeyButton] = [
        KeyButton(key: .escape, symbol: "escape", label: "Escape"),
        KeyButton(key: .tab, symbol: "arrow.right.to.line", label: "Tab"),
        KeyButton(key: .left, symbol: "arrow.left", label: "Left arrow"),
        KeyButton(key: .down, symbol: "arrow.down", label: "Down arrow"),
        KeyButton(key: .up, symbol: "arrow.up", label: "Up arrow"),
        KeyButton(key: .right, symbol: "arrow.right", label: "Right arrow"),
        KeyButton(key: .delete, symbol: "delete.left", label: "Delete"),
        KeyButton(key: .return, symbol: "return", label: "Return"),
    ]

    private static let modifiers: [ModifierButton] = [
        ModifierButton(modifier: .command, glyph: "⌘", label: "Command"),
        ModifierButton(modifier: .option, glyph: "⌥", label: "Option"),
        ModifierButton(modifier: .control, glyph: "⌃", label: "Control"),
        ModifierButton(modifier: .shift, glyph: "⇧", label: "Shift"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            LiveTypingField(
                placeholder: "Type here: it goes straight to the Mac",
                latchedModifiers: latched,
                onEdit: { edit in
                    onActivity()
                    Task { await sender.sendTypingEdit(edit) }
                },
                onKey: { key, modifiers in
                    onActivity()
                    Task { await sender.sendKey(key, modifiers: modifiers) }
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
                            Task { await sender.sendKey(key, modifiers: modifiers) }
                        } label: {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: key == .return ? .semibold : .medium))
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
            }

            ClipboardRow(sender: sender, clipboard: clipboard, colorScheme: colorScheme, onActivity: onActivity)
        }
    }
}
