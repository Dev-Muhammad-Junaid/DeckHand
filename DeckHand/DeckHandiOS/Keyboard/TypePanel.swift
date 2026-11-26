//
//  TypePanel.swift
//  DeckHandiOS – Keyboard
//
//  The Type panel (owner testing, build 24, OT-3): how text and keys get
//  into the Mac. It replaces the keyboard bar, which didn't follow the
//  rebrand, made it hard to put text into a Mac field and had no number
//  keypad. Rules in Core (`TypePanel.swift`); the shell shows it in one
//  place, above the keyboard or the dock (`TypePanelHost`, OT-2).
//
//   ┌──────────────────────────────────────────────────────────────┐
//   │ [Live│Compose]  ⌨ Typing into Safari         [⌨][▦]   (×)    │  header
//   │ ┌────────────────────────────────────────┐ [Paste] [⏎][Send] │  field
//   │ └────────────────────────────────────────┘                   │
//   │ ⌘ ⌥ ⌃ ⇧ │ esc tab ⌫ ⏎ ← ↓ ↑ → home end pg up pg dn │ fn      │  keys
//   └──────────────────────────────────────────────────────────────┘
//   Numpad tab: the field gives way to a 4 × 5 dot-matrix keypad.
//   Hardware keyboard: one line (the field, reading "Typing into …"),
//   then the keys row with the chips, and the close button.
//
//  A raised card (radius 24, 12 inset, hairline), chips and keys at
//  radius 8 / 14 on the 4 pt grid; selection by colour and fill only;
//  the panel fades, never slides.
//

import SwiftUI

struct TypePanel: View {
    let sender: TrackpadSender
    var clipboard: RemoteClipboard?
    @Bindable var model: TypePanelModel
    let layout: TypePanelLayout
    /// A key or text went to the Mac (forgets what a gesture opened).
    var onActivity: () -> Void = {}

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.entitlements) private var entitlements
    /// A Return held back while the person confirms the app (VQ-036).
    @State private var heldReturn: (() -> Void)?
    private let target = TypingTarget.shared

    private var presence: TypePanelPresence { model.presence }

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            if layout.showsHeader {
                header
                if !layout.targetInHeader {
                    targetLine
                }
            }
            if presence.tab == .keys || !layout.showsHeader {
                fieldRow
            } else {
                NumpadGrid(keySize: CGFloat(layout.numpadKeySize)) { key in press(key) }
                    .frame(maxWidth: .infinity)
            }
            keysRow
            if !layout.modifiersInKeysRow {
                modifierRow
            }
            if layout.showsHeader, presence.mode == .live {
                clipboardLine
            }
        }
        .padding(PixelHandTheme.Space.md)
        .frame(maxWidth: CGFloat(layout.maximumWidth))
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .fill(PixelHandTheme.raised)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type on the Mac")
        .accessibilityIdentifier("ph.type.panel")
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

    // MARK: Header

    private var header: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            ModeSwitch(mode: $model.mode)
            if layout.targetInHeader {
                targetLine
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            tabSwitch
            closeButton
        }
    }

    /// "Typing into Messages": where keys go, always in view (VQ-036).
    private var targetLine: some View {
        HStack(spacing: PixelHandTheme.Space.xs) {
            PHGlyph(glyph: PixelGlyphs.keyboard, pitch: CGFloat(PixelPitch.badge), stepsWithType: true)
            Text(TypingTargetGuard.caption(frontApp: target.frontApp))
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(PixelHandTheme.ink2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ph.type.target")
    }

    private var tabSwitch: some View {
        HStack(spacing: 2) {
            tabButton(.keys, glyph: PixelGlyphs.keyboard)
            tabButton(.numpad, glyph: PixelGlyphs.numpad)
        }
        .padding(2)
        .background(PixelHandTheme.fill, in: Capsule())
    }

    private func tabButton(_ tab: TypeTab, glyph: GlyphBitmap) -> some View {
        let isOn = presence.tab == tab
        return Button {
            GestureHaptic.selection.trigger()
            model.presence.select(tab)
        } label: {
            PHGlyph(glyph: glyph, pitch: 1.8)
                .foregroundStyle(isOn ? Color.white : PixelHandTheme.ink2)
                .frame(width: 40, height: 32)
                .background(Capsule().fill(isOn ? PixelHandTheme.accent : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: PixelHandTheme.ControlHeight.secondary)
        .phosphorFocusable(cornerRadius: 16)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("ph.type.tab.\(tab.rawValue)")
    }

    private var closeButton: some View {
        GlassCircleButton(glyph: PixelGlyphs.close, label: "Hide keyboard", size: PixelHandTheme.ControlHeight.secondary) {
            model.toggle()
        }
        .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
        .accessibilityIdentifier("ph.type.close")
    }

    // MARK: Field

    private var fieldRow: some View {
        HStack(alignment: .bottom, spacing: PixelHandTheme.Space.sm) {
            LiveTypingField(
                mode: presence.mode,
                // Without the header, the field says where text goes.
                placeholder: !layout.showsHeader && presence.mode == .live
                    ? TypingTargetGuard.caption(frontApp: target.frontApp)
                    : presence.mode.placeholder,
                latchedModifiers: presence.modifiers.held,
                draft: $model.draft,
                wantsFocus: presence.wantsFocus || layout.body == .keysOnly,
                focusRequest: presence.focusRequest,
                composeLines: layout.composeLines,
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
                onModifiersUsed: { _ = model.presence.modifiers.consume() },
                onSubmit: { sendDraft() }
            )
            .padding(.horizontal, PixelHandTheme.Space.md)
            .frame(minHeight: PixelHandTheme.ControlHeight.standard)
            .background(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                    .fill(PixelHandTheme.fill)
            )

            pasteButton
            if presence.mode == .compose {
                sendReturnToggle
                sendButton
            }
            if !layout.showsHeader {
                closeButton
            }
        }
    }

    /// Paste from this device's clipboard: into the draft in Compose,
    /// to the Mac in Live (the clipboard feature's setting decides whether
    /// it lands at the Mac's cursor or on its clipboard).
    @ViewBuilder
    private var pasteButton: some View {
        if presence.mode == .compose {
            PasteToMacControl { text in
                model.draft += text
            }
            .fixedSize()
            .frame(height: PixelHandTheme.ControlHeight.standard)
            .accessibilityLabel("Paste into the draft")
            .accessibilityIdentifier("ph.type.paste")
        } else {
            PasteToMacControl { text in
                onActivity()
                clipboard?.pasteToMac(text, paste: settings.pasteRightAway, sender: sender)
            }
            .fixedSize()
            .frame(height: PixelHandTheme.ControlHeight.standard)
            .accessibilityHint(settings.pasteRightAway ? "Pastes at the Mac’s cursor" : "Puts the text on the Mac’s clipboard")
            .accessibilityIdentifier("ph.type.paste")
            .requiresPro(.sharing)
        }
    }

    /// What the last paste did, or what was last copied on the Mac (S10),
    /// in one quiet line; nothing when there's nothing to say.
    @ViewBuilder
    private var clipboardLine: some View {
        if let status = clipboard?.pasteStatus {
            Text(status)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(PixelHandTheme.ink2)
                .lineLimit(1)
                .padding(.horizontal, PixelHandTheme.Space.xs)
        } else if settings.clipboardSync, let fromMac = clipboard?.lastFromMac {
            Text("Copied on the Mac: “\(fromMac)”")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(PixelHandTheme.ink2)
                .lineLimit(1)
                .padding(.horizontal, PixelHandTheme.Space.xs)
        }
    }

    private var sendReturnToggle: some View {
        let isOn = model.sendsReturn
        return Button {
            GestureHaptic.selection.trigger()
            model.sendsReturn.toggle()
        } label: {
            Text("+⏎")
                .font(.phChord)
                .foregroundStyle(isOn ? PixelHandTheme.accentInk : PixelHandTheme.ink2)
                .frame(minWidth: 44, minHeight: PixelHandTheme.ControlHeight.standard)
                .background(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                        .fill(isOn ? PixelHandTheme.accentTint : PixelHandTheme.fill)
                )
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
        .accessibilityLabel("Press Return after sending")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("ph.type.sendReturn")
    }

    private var sendButton: some View {
        let enabled = ComposeSend.canSend(draft: model.draft, withReturn: model.sendsReturn)
        return Button(action: sendDraft) {
            Text("Send")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .frame(minHeight: PixelHandTheme.ControlHeight.standard)
                .background(Capsule().fill(enabled ? PixelHandTheme.accent : PixelHandTheme.ink3))
        }
        .buttonStyle(ChipPressStyle())
        .disabled(!enabled)
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.standard / 2)
        .accessibilityLabel(model.sendsReturn ? "Send, then press Return" : "Send")
        .accessibilityIdentifier("ph.type.send")
    }

    // MARK: Keys

    private var keysRow: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            if layout.modifiersInKeysRow {
                modifierChips
                Rectangle()
                    .fill(PixelHandTheme.hairline)
                    .frame(width: 1, height: 28)
                    .accessibilityHidden(true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TypeKeysRow.keys(showsFunctionKeys: presence.showsFunctionKeys)) { key in
                        keyButton(key)
                    }
                }
                .padding(.trailing, TrailingFade.overflowWidth)
            }
            // Runs past the edge on a phone: fade it so it reads as "more
            // this way" (VQ-034).
            .mask { TrailingFade() }
            fnToggle
        }
    }

    private var modifierRow: some View {
        HStack(spacing: 6) {
            modifierChips
            Spacer(minLength: 0)
        }
    }

    private var modifierChips: some View {
        HStack(spacing: 6) {
            ForEach(ModifierLatch.chips, id: \.self) { modifier in
                modifierChip(modifier)
            }
        }
    }

    private func modifierChip(_ modifier: KeyModifier) -> some View {
        let state = presence.modifiers.state(modifier)
        let lit = state != .off
        return Button {
            GestureHaptic.selection.trigger()
            model.presence.modifiers.tap(modifier)
        } label: {
            Text(modifier.chipGlyph)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(lit ? Color.white : PixelHandTheme.ink)
                .frame(width: 40, height: PixelHandTheme.ControlHeight.secondary)
                .background(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                        .fill(lit ? PixelHandTheme.accent : PixelHandTheme.fill)
                )
                // Locked: a 2 pt ring outside the lit chip.
                .overlay(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd + 3, style: .continuous)
                        .strokeBorder(PixelHandTheme.accent, lineWidth: PixelHandTheme.Stroke.selection)
                        .padding(-3)
                        .opacity(state == .locked ? 1 : 0)
                )
                .frame(minHeight: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
        .accessibilityLabel(modifier.spokenName)
        .accessibilityValue(presence.modifiers.spokenValue(modifier))
        .accessibilityHint("Tap to hold for the next key, again to lock, again to let go")
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("ph.type.modifier.\(modifier.rawValue)")
    }

    private func keyButton(_ key: TypeKey) -> some View {
        Button {
            onActivity()
            GestureHaptic.light.trigger()
            let modifiers = model.presence.modifiers.consume()
            guardReturn(if: key.isReturn) {
                Task { await sender.sendShortcut(key.chord(with: modifiers)) }
            }
        } label: {
            Text(key.cap)
                .font(.phChord)
                .foregroundStyle(key.isReturn ? Color.white : PixelHandTheme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, PixelHandTheme.Space.sm)
                .frame(minWidth: 40, minHeight: PixelHandTheme.ControlHeight.secondary)
                .background(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                        .fill(key.isReturn ? PixelHandTheme.accent : PixelHandTheme.fill)
                )
                .frame(minHeight: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
        .accessibilityLabel(key.spokenName)
        .accessibilityIdentifier("ph.type.key.\(key.wireName)")
    }

    private var fnToggle: some View {
        let isOn = presence.showsFunctionKeys
        return Button {
            GestureHaptic.selection.trigger()
            model.presence.showsFunctionKeys.toggle()
        } label: {
            Text("fn")
                .font(.phChord)
                .foregroundStyle(isOn ? PixelHandTheme.accentInk : PixelHandTheme.ink2)
                .frame(width: 40, height: PixelHandTheme.ControlHeight.secondary)
                .background(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                        .fill(isOn ? PixelHandTheme.accentTint : PixelHandTheme.fill)
                )
                .frame(minHeight: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
        .accessibilityLabel(isOn ? "Show the editing keys" : "Show F1 to F12")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("ph.type.fn")
    }

    // MARK: Sending

    /// Compose's Send: the draft as typed text, then Return when asked, in
    /// order, then a clear field.
    private func sendDraft() {
        let draft = model.draft
        let withReturn = model.sendsReturn
        guard ComposeSend.canSend(draft: draft, withReturn: withReturn) else { return }
        onActivity()
        GestureHaptic.light.trigger()
        let messages = ComposeSend.messages(draft: draft, withReturn: withReturn)
        guardReturn(if: withReturn || draft.contains("\n")) {
            Task {
                for message in messages {
                    switch message {
                    case let .text(text): await sender.typeText(text)
                    case let .key(name): await sender.sendShortcut([name])
                    }
                }
            }
            model.draft = ""
        }
    }

    private func press(_ key: NumpadKey) {
        onActivity()
        GestureHaptic.light.trigger()
        // Compose: the numpad writes into the draft.
        if presence.mode == .compose {
            switch key.output {
            case let .text(text): model.draft += text
            case .key:
                if key == .delete {
                    if !model.draft.isEmpty { model.draft.removeLast() }
                } else {
                    sendDraft()
                }
            }
            return
        }
        let modifiers = model.presence.modifiers.consume()
        switch key.output {
        case let .text(text):
            target.guardrail.typed(into: target.frontApp)
            if modifiers.isEmpty {
                Task { await sender.typeText(text) }
            } else if KeyTable.keyCode(for: text) != nil {
                Task { await sender.sendShortcut(KeyModifier.pressOrder.filter(modifiers.contains).map(\.wireName) + [text]) }
            } else {
                Task { await sender.typeText(text) }
            }
        case let .key(name):
            guardReturn(if: key == .enter) {
                Task { await sender.sendShortcut(KeyModifier.pressOrder.filter(modifiers.contains).map(\.wireName) + [name]) }
            }
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
}

// MARK: - Mode switch

/// Live | Compose, selection by colour and fill only (like the right
/// column's Deck | Ask).
private struct ModeSwitch: View {
    @Binding var mode: TypeMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TypeMode.allCases, id: \.self) { item in
                let isOn = mode == item
                Button {
                    guard mode != item else { return }
                    GestureHaptic.selection.trigger()
                    mode = item
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(isOn ? Color.white : PixelHandTheme.ink2)
                        .padding(.horizontal, PixelHandTheme.Space.md)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(isOn ? PixelHandTheme.accent : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .phosphorFocusable(cornerRadius: 16)
                .accessibilityLabel(item.title)
                .accessibilityHint(item.spokenHint)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("ph.type.mode.\(item.rawValue)")
            }
        }
        .padding(2)
        .background(PixelHandTheme.fill, in: Capsule())
        .frame(minHeight: PixelHandTheme.ControlHeight.secondary)
    }
}

// MARK: - Numpad

/// The 4 × 5 keypad in dot-matrix numerals: 0 spans two columns, Enter two
/// rows (`NumpadKey.cell`). Operators in accent ink; Enter on the accent.
struct NumpadGrid: View {
    let keySize: CGFloat
    let onPress: (NumpadKey) -> Void

    private let gap = CGFloat(TypePanelLayout.numpadGap)

    var body: some View {
        let width = CGFloat(NumpadKey.columns) * keySize + CGFloat(NumpadKey.columns - 1) * gap
        let height = CGFloat(NumpadKey.rows) * keySize + CGFloat(NumpadKey.rows - 1) * gap
        ZStack(alignment: .topLeading) {
            ForEach(NumpadKey.allCases) { key in
                let cell = key.cell
                let w = CGFloat(cell.columnSpan) * keySize + CGFloat(cell.columnSpan - 1) * gap
                let h = CGFloat(cell.rowSpan) * keySize + CGFloat(cell.rowSpan - 1) * gap
                NumpadKeyButton(key: key) { onPress(key) }
                    .frame(width: w, height: h)
                    .offset(
                        x: CGFloat(cell.column) * (keySize + gap),
                        y: CGFloat(cell.row) * (keySize + gap)
                    )
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Numpad")
        .accessibilityIdentifier("ph.type.numpad")
    }
}

private struct NumpadKeyButton: View {
    let key: NumpadKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                    .fill(key == .enter ? PixelHandTheme.accent : PixelHandTheme.fill)
                if key == .delete {
                    Image(systemName: "delete.left")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PixelHandTheme.ink)
                } else {
                    DotMatrixText(key.cap, pitch: key == .enter ? 1.6 : 2.6, label: key.spokenName, glows: false)
                        .foregroundStyle(
                            key == .enter ? Color.white
                                : key.isOperator ? PixelHandTheme.accentInk : PixelHandTheme.ink
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
        }
        .buttonStyle(NumpadPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
        .accessibilityLabel(key.spokenName)
        .accessibilityIdentifier("ph.type.numpad.\(key.rawValue)")
    }
}

/// A key press: a quick dip, no plate change (the glyph rule's press flash).
private struct NumpadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(PixelHandMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Host

/// Where the shell shows the panel: one place for every arrangement, so the
/// field keeps its identity (and the keyboard) through rotation, Stage
/// Manager resizes and form changes (OT-2). It sits above whichever is
/// higher of the on-screen keyboard and the app dock
/// (`TypePanelLayout.bottomPadding`) and never moves the shell under it.
struct TypePanelHost: View {
    let session: ControlSessionModel
    let model: TypePanelModel
    /// The window's size, as the shell plans from it.
    let windowSize: CGSize
    /// Whether the form shows the app dock (its last measured top is
    /// stale otherwise).
    var showsDock = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let layout = TypePanelLayout(
                width: Double(windowSize.width),
                height: Double(windowSize.height),
                keyboard: model.keyboard,
                keyboardOverlap: model.keyboardOverlap
            )
            let padding = TypePanelLayout.bottomPadding(
                containerMaxY: Double(frame.maxY),
                keyboardMinY: model.keyboardMinY,
                dockMinY: showsDock ? model.dockMinY.map { Double($0) } : nil
            )
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if model.isShown, let sender = session.sender {
                    TypePanel(sender: sender, clipboard: session.clipboard, model: model, layout: layout)
                        .padding(.horizontal, CGFloat(layout.margin))
                        .padding(.bottom, CGFloat(padding))
                        .transition(.opacity) // Glyph rule: panels fade, never slide.
                }
            }
            .frame(maxWidth: .infinity)
            .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: model.isShown)
        }
        // The panel places itself against the keyboard; it must not be
        // pushed up by the keyboard's safe area as well.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
