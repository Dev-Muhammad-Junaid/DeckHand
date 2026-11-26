//
//  TypePanel.swift
//  DeckHandiOS – Keyboard
//
//  The Type panel: how text and keys get into the Mac (owner testing,
//  build 24, OT-3), made movable, resizable, collapsible and compact in
//  build 25 (OT-6, OT-7). Rules in Core (`TypePanel.swift`,
//  `TypePanelGeometry.swift`); the shell shows it in one place over every
//  arrangement (`TypePanelHost`, OT-2) and the person puts it where it
//  doesn't hide what they're typing into.
//
//   ┌───────────────────────────────────────────────────────────────┐
//   │ ⠿ [Live│Compose] ⌨ Typing into Safari         [▦] [–] (×)     │ header
//   │ ┌──────────────────┐      ↑      ⌘  ⌥  ⌃  ⇧  ESC TAB──        │
//   │ │ field            │   ←  ↓  →   ⌫  ⏎ HOME END PGUP PGDN FN   │
//   │ └──────────────────┘ [paste][+⏎][Send]                        │
//   └◢──────────────────────────────────────────────────────────◣──┘
//   One block on wide panels; narrower panels (or the numpad on) put
//   the keys under the field and the arrows, and the 5 × 4 numpad docks
//   beside the keys, or under them when it doesn't fit. The layout
//   follows the panel's own width (`TypePanelLayout`), so resizing
//   reflows it. ⠿ drags it (soft magnet to the edges and corners), the
//   bottom corners resize it, – folds it to a pill.
//
//  A raised card (radius 24, 12 inset, hairline), key caps 40 pt on 44 pt
//  cells (radius 8), legends in the dot-matrix font or pixel glyphs;
//  selection by colour and fill only; the panel fades, never slides.
//

import SwiftUI

/// What the host gives the panel so it can move and fold (`nil` when the
/// panel sits inline, as in the classic layout).
struct TypePanelChrome {
    /// The grip is being dragged: the translation in global points.
    var onGripChanged: (CGSize) -> Void
    var onGripEnded: (CGSize) -> Void
    /// Fold to the pill.
    var onCollapse: () -> Void
    /// VoiceOver's move actions: fractions of the free room (`nil` keeps
    /// that axis).
    var onPlace: (_ x: Double?, _ y: Double?) -> Void
}

struct TypePanel: View {
    let sender: TrackpadSender
    var clipboard: RemoteClipboard?
    @Bindable var model: TypePanelModel
    let layout: TypePanelLayout
    var chrome: TypePanelChrome?
    /// A key or text went to the Mac (forgets what a gesture opened).
    var onActivity: () -> Void = {}

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.entitlements) private var entitlements
    /// A Return held back while the person confirms the app (VQ-036).
    @State private var heldReturn: (() -> Void)?
    private let target = TypingTarget.shared

    private var presence: TypePanelPresence { model.presence }
    private let gap = CGFloat(TypePanelLayout.blockGap)

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            if layout.showsHeader {
                header
                if !layout.targetInHeader {
                    targetLine
                }
            }
            PanelBodyLayout(
                arrangement: layout.arrangement,
                numpad: layout.numpadPlacement,
                fieldWidth: CGFloat(layout.fieldWidth),
                gap: gap
            ) {
                // One field in one place in the tree, whatever the
                // arrangement: reflowing never hands the keyboard to a
                // new view (OT-2).
                fieldColumn
                arrowCluster
                keyBlock
                if layout.numpadPlacement != .hidden {
                    NumpadGrid { key in press(key) }
                }
            }
            if layout.showsHeader, presence.mode == .live {
                clipboardLine
            }
        }
        .padding(CGFloat(TypePanelLayout.padding))
        .frame(width: CGFloat(layout.panelWidth), alignment: .leading)
        .environment(\.typeKeyPitch, CGFloat(layout.cellPitch))
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

    /// Grip, mode, target, numpad, collapse, close; on two lines when it
    /// doesn't fit (the narrowest panels at the largest text sizes).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PixelHandTheme.Space.xs) {
                gripHandle
                ModeSwitch(mode: $model.mode)
                if layout.targetInHeader {
                    targetLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                headerButtons
            }
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
                HStack(spacing: PixelHandTheme.Space.xs) {
                    gripHandle
                    Spacer(minLength: 0)
                    headerButtons
                }
                ModeSwitch(mode: $model.mode)
            }
        }
    }

    private var headerButtons: some View {
        HStack(spacing: PixelHandTheme.Space.xs) {
            numpadToggle
            if let chrome {
                GlassCircleButton(glyph: PixelGlyphs.collapse, label: "Collapse the keyboard panel", size: PixelHandTheme.ControlHeight.secondary) {
                    GestureHaptic.selection.trigger()
                    chrome.onCollapse()
                }
                .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                .accessibilityIdentifier("ph.type.collapse")
            }
            closeButton
        }
    }

    /// ⠿: drag the panel anywhere (OT-6). VoiceOver gets move actions
    /// instead of a drag.
    @ViewBuilder
    private var gripHandle: some View {
        if let chrome {
            PHGlyph(glyph: PixelGlyphs.grip, pitch: 1.8)
                .foregroundStyle(PixelHandTheme.ink2)
                .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { chrome.onGripChanged($0.translation) }
                        .onEnded { chrome.onGripEnded($0.translation) }
                )
                .hoverEffect(.highlight)
                .accessibilityElement()
                .accessibilityLabel("Move the keyboard panel")
                .accessibilityHint("Drag to put it where it doesn't cover what you're typing into.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Move to the top") { chrome.onPlace(nil, 0) }
                .accessibilityAction(named: "Move to the bottom") { chrome.onPlace(nil, 1) }
                .accessibilityAction(named: "Move to the left") { chrome.onPlace(0, nil) }
                .accessibilityAction(named: "Move to the centre") { chrome.onPlace(0.5, nil) }
                .accessibilityAction(named: "Move to the right") { chrome.onPlace(1, nil) }
                .accessibilityIdentifier("ph.type.grip")
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

    /// The numpad docks beside the keys or goes away (OT-7).
    private var numpadToggle: some View {
        let isOn = presence.tab == .numpad
        return Button {
            GestureHaptic.selection.trigger()
            model.presence.toggleNumpad()
        } label: {
            PHGlyph(glyph: PixelGlyphs.numpad, pitch: 1.8)
                .foregroundStyle(isOn ? Color.white : PixelHandTheme.ink2)
                .frame(width: 40, height: 32)
                .background(Capsule().fill(isOn ? PixelHandTheme.accent : PixelHandTheme.fill))
                .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .phosphorFocusable(cornerRadius: 16)
        .accessibilityLabel("Numpad")
        .accessibilityValue(isOn ? "Shown" : "Hidden")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("ph.type.tab.numpad")
    }

    private var closeButton: some View {
        GlassCircleButton(glyph: PixelGlyphs.close, label: "Hide keyboard", size: PixelHandTheme.ControlHeight.secondary) {
            model.toggle()
        }
        .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
        .accessibilityIdentifier("ph.type.close")
    }

    // MARK: Field

    /// The field, and under it Paste (and Compose's +⏎ and Send). Without
    /// the header (short room), the grip and close sit beside the field.
    private var fieldColumn: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
            HStack(spacing: PixelHandTheme.Space.xs) {
                if !layout.showsHeader { gripHandle }
                field
                if !layout.showsHeader { closeButton }
            }
            if layout.body == .full {
                HStack(spacing: PixelHandTheme.Space.xs) {
                    pasteButton
                    if presence.mode == .compose {
                        sendReturnToggle
                        sendButton
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var field: some View {
        LiveTypingField(
            mode: presence.mode,
            // Without the header, or with a hardware keyboard, the field
            // says where text goes.
            placeholder: (!layout.showsHeader || layout.body == .keysOnly) && presence.mode == .live
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
            onSubmit: { sendDraft() },
            onFocus: { model.presence.fieldFocused() }
        )
        .padding(.horizontal, PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, minHeight: PixelHandTheme.ControlHeight.standard)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(PixelHandTheme.fill)
        )
    }

    /// Paste from this device's clipboard: into the draft in Compose,
    /// to the Mac in Live (the clipboard feature's setting decides whether
    /// it lands at the Mac's cursor or on its clipboard). Icon only, to
    /// keep the field's column short.
    @ViewBuilder
    private var pasteButton: some View {
        if presence.mode == .compose {
            PasteToMacControl(iconOnly: true) { text in
                model.draft += text
            }
            .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.secondary)
            .frame(height: PixelHandTheme.ControlHeight.hit)
            .accessibilityLabel("Paste into the draft")
            .accessibilityIdentifier("ph.type.paste")
        } else {
            PasteToMacControl(iconOnly: true) { text in
                onActivity()
                clipboard?.pasteToMac(text, paste: settings.pasteRightAway, sender: sender)
            }
            .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.secondary)
            .frame(height: PixelHandTheme.ControlHeight.hit)
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
                .frame(width: 44, height: PixelHandTheme.ControlHeight.secondary)
                .background(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                        .fill(isOn ? PixelHandTheme.accentTint : PixelHandTheme.fill)
                )
                .frame(height: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
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
                .padding(.horizontal, PixelHandTheme.Space.md)
                .frame(height: PixelHandTheme.ControlHeight.secondary)
                .background(Capsule().fill(enabled ? PixelHandTheme.accent : PixelHandTheme.ink3))
                .frame(height: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle())
        .disabled(!enabled)
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.secondary / 2)
        .accessibilityLabel(model.sendsReturn ? "Send, then press Return" : "Send")
        .accessibilityIdentifier("ph.type.send")
    }

    // MARK: Arrows and keys (OT-7)

    /// The inverted T: ↑ over ← ↓ →.
    private var arrowCluster: some View {
        KeyGrid(columns: ArrowCluster.columns, rows: ArrowCluster.rows) {
            ForEach(ArrowCluster.cells, id: \.key) { cell in
                keyButton(cell.key)
                    .keyCell(column: cell.column, row: cell.row)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Arrow keys")
        .accessibilityIdentifier("ph.type.arrows")
    }

    /// Two compact rows: ⌘ ⌥ ⌃ ⇧ esc tab / ⌫ ⏎ home end pg↑ pg↓ fn. With fn
    /// on, the second row's keys give way to a strip of F1–F12.
    private var keyBlock: some View {
        let fnOn = presence.showsFunctionKeys
        return KeyGrid(columns: TypeKeyBlock.columns, rows: TypeKeyBlock.rows) {
            ForEach(TypeKeyBlock.cells.filter { !(fnOn && $0.row == 1 && $0.item != .fn) }, id: \.item) { cell in
                blockItem(cell.item)
                    .keyCell(column: cell.column, row: cell.row, columnSpan: cell.columnSpan)
            }
            if fnOn {
                functionStrip
                    .keyCell(column: 0, row: 1, columnSpan: TypeKeyBlock.functionStripColumns)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keys")
        .accessibilityIdentifier("ph.type.keys")
    }

    @ViewBuilder
    private func blockItem(_ item: TypeKeyBlock.Item) -> some View {
        switch item {
        case let .modifier(modifier): modifierChip(modifier)
        case let .key(key): keyButton(key)
        case .fn: fnToggle
        }
    }

    private var functionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(TypeKeysRow.functionKeys) { key in
                    keyButton(key)
                        .frame(width: CGFloat(layout.cellPitch), height: CGFloat(layout.cellPitch))
                }
            }
            .padding(.trailing, TrailingFade.overflowWidth)
        }
        // Runs past the edge: fade it so it reads as "more this way"
        // (VQ-034).
        .mask { TrailingFade() }
    }

    private func modifierChip(_ modifier: KeyModifier) -> some View {
        let state = presence.modifiers.state(modifier)
        let lit = state != .off
        return Button {
            GestureHaptic.selection.trigger()
            model.presence.modifiers.tap(modifier)
        } label: {
            KeyCap(legend: .text(modifier.chipGlyph), style: lit ? .lit : .plain, isLocked: state == .locked)
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
            KeyCap(legend: KeyCap.Legend(key), style: key.isReturn ? .accent : .plain)
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
            KeyCap(legend: .dots("FN"), style: isOn ? .tint : .plain)
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

// MARK: - Body layout

/// Places the field column, the arrows, the key block and the numpad
/// (`TypePanelLayout`): one block (side by side), or stacked with the
/// numpad beside or under the keys. A `Layout`, so the four keep their
/// identity when the arrangement changes and the field never loses the
/// keyboard to a reflow.
private struct PanelBodyLayout: Layout {
    let arrangement: TypePanelLayout.Arrangement
    let numpad: TypePanelLayout.NumpadPlacement
    let fieldWidth: CGFloat
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(subviews).reduce(CGRect.zero) { $0.union($1) }.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Frames for [field, arrows, keys, numpad?], from the top-leading
    /// corner.
    private func frames(_ subviews: Subviews) -> [CGRect] {
        guard subviews.count >= 3 else { return [] }
        let field = subviews[0].sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil))
        let arrows = subviews[1].sizeThatFits(.unspecified)
        let keys = subviews[2].sizeThatFits(.unspecified)
        let pad = subviews.count > 3 ? subviews[3].sizeThatFits(.unspecified) : .zero
        var frames: [CGRect] = []
        frames.append(CGRect(x: 0, y: 0, width: fieldWidth, height: field.height))
        frames.append(CGRect(x: fieldWidth + gap, y: 0, width: arrows.width, height: arrows.height))
        switch arrangement {
        case .oneBlock:
            frames.append(CGRect(x: fieldWidth + gap + arrows.width + gap, y: 0, width: keys.width, height: keys.height))
            if subviews.count > 3 {
                frames.append(CGRect(x: frames[2].maxX + gap, y: 0, width: pad.width, height: pad.height))
            }
        case .stacked:
            let top = max(field.height, arrows.height) + gap
            frames.append(CGRect(x: 0, y: top, width: keys.width, height: keys.height))
            if subviews.count > 3 {
                switch numpad {
                case .beside, .hidden:
                    frames.append(CGRect(x: keys.width + gap, y: top, width: pad.width, height: pad.height))
                case .below:
                    frames.append(CGRect(x: 0, y: top + keys.height + gap, width: pad.width, height: pad.height))
                }
            }
        }
        return frames
    }
}

// MARK: - Key caps

/// The key cell size the panel draws (`TypePanelLayout.cellPitch`: 44 pt,
/// less only in a panel narrower than the key block).
private struct TypeKeyPitchKey: EnvironmentKey {
    static let defaultValue = CGFloat(TypePanelLayout.keyPitch)
}

extension EnvironmentValues {
    var typeKeyPitch: CGFloat {
        get { self[TypeKeyPitchKey.self] }
        set { self[TypeKeyPitchKey.self] = newValue }
    }
}

/// A grid of key cells (44 pt): each key fills its cell's touch target and
/// draws a cap 4 pt smaller inside it.
private struct KeyGrid<Content: View>: View {
    let columns: Int
    let rows: Int
    @ViewBuilder let content: Content

    @Environment(\.typeKeyPitch) private var pitch

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
        }
        .frame(width: CGFloat(columns) * pitch, height: CGFloat(rows) * pitch, alignment: .topLeading)
    }
}

private extension View {
    /// Puts a key in its grid cell (`KeyGrid`).
    func keyCell(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) -> some View {
        modifier(KeyCell(column: column, row: row, columnSpan: columnSpan, rowSpan: rowSpan))
    }
}

private struct KeyCell: ViewModifier {
    let column: Int
    let row: Int
    let columnSpan: Int
    let rowSpan: Int

    @Environment(\.typeKeyPitch) private var pitch

    func body(content: Content) -> some View {
        content
            .frame(width: CGFloat(columnSpan) * pitch, height: CGFloat(rowSpan) * pitch)
            .offset(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch)
    }
}

/// One key cap: 40 pt tall inside its 44 pt cell, the legend in the
/// dot-matrix font (words), a pixel glyph (arrows) or the rounded chord
/// face (⌘ ⌥ ⌃ ⇧ ⌫ ⏎).
private struct KeyCap: View {
    enum Legend {
        case dots(String)
        case glyph(GlyphBitmap, label: String)
        case text(String)

        init(_ key: TypeKey) {
            if let legend = key.dotMatrixLegend {
                self = .dots(legend)
                return
            }
            switch key {
            case .remote(.up): self = .glyph(PixelGlyphs.keyUp, label: key.spokenName)
            case .remote(.down): self = .glyph(PixelGlyphs.keyDown, label: key.spokenName)
            case .remote(.left): self = .glyph(PixelGlyphs.keyLeft, label: key.spokenName)
            case .remote(.right): self = .glyph(PixelGlyphs.keyRight, label: key.spokenName)
            default: self = .text(key.cap)
            }
        }
    }

    enum Style {
        case plain, accent, lit, tint
    }

    let legend: Legend
    var style: Style = .plain
    var isLocked = false

    private var ink: Color {
        switch style {
        case .plain: PixelHandTheme.ink
        case .accent, .lit: .white
        case .tint: PixelHandTheme.accentInk
        }
    }

    private var plate: Color {
        switch style {
        case .plain: PixelHandTheme.fill
        case .accent, .lit: PixelHandTheme.accent
        case .tint: PixelHandTheme.accentTint
        }
    }

    var body: some View {
        let inset = CGFloat(TypePanelLayout.keyGap) / 2
        ZStack {
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                .fill(plate)
            switch legend {
            case let .dots(text):
                DotMatrixText(text, pitch: 1.4, label: text, glows: false, stepsWithType: false)
            case let .glyph(glyph, label):
                PHGlyph(glyph: glyph, pitch: 1.6)
                    .accessibilityLabel(label)
            case let .text(text):
                Text(text)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(ink)
        // Locked modifier: a 2 pt ring just inside the cell.
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd + 2, style: .continuous)
                .strokeBorder(PixelHandTheme.accent, lineWidth: PixelHandTheme.Stroke.selection)
                .padding(-inset)
                .opacity(isLocked ? 1 : 0)
        )
        .padding(inset)
        .contentShape(Rectangle())
    }
}

// MARK: - Numpad

/// The 5 × 4 keypad in dot-matrix numerals (OT-7): 7 8 9 ÷ ⌫ / 4 5 6 × /
/// 1 2 3 − / 0 . = +, Enter three rows tall in the last column, on the
/// same 44 pt cells as the keys. Operators in accent ink; Enter on the
/// accent.
struct NumpadGrid: View {
    let onPress: (NumpadKey) -> Void

    var body: some View {
        KeyGrid(columns: NumpadKey.columns, rows: NumpadKey.rows) {
            ForEach(NumpadKey.allCases) { key in
                let cell = key.cell
                NumpadKeyButton(key: key) { onPress(key) }
                    .keyCell(column: cell.column, row: cell.row, columnSpan: cell.columnSpan, rowSpan: cell.rowSpan)
            }
        }
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
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                    .fill(key == .enter ? PixelHandTheme.accent : PixelHandTheme.fill)
                if key == .delete {
                    Text("⌫")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PixelHandTheme.ink)
                } else if key == .enter {
                    // Three cells tall: the word stands up the key.
                    DotMatrixText("ENT", pitch: 1.4, label: key.spokenName, glows: false, stepsWithType: false)
                        .foregroundStyle(Color.white)
                } else {
                    DotMatrixText(key.cap, pitch: 2, label: key.spokenName, glows: false, stepsWithType: false)
                        .foregroundStyle(key.isOperator ? PixelHandTheme.accentInk : PixelHandTheme.ink)
                }
            }
            .padding(CGFloat(TypePanelLayout.keyGap) / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(NumpadPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
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

// MARK: - Pill

/// The folded panel (OT-6): "⌨ Safari · Live", one tap to open it again,
/// and it drags like the grip. Close from its context menu.
private struct TypePanelPill: View {
    let model: TypePanelModel
    let chrome: TypePanelChrome
    private let target = TypingTarget.shared

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            PHGlyph(glyph: PixelGlyphs.keyboard, pitch: 1.8)
                .foregroundStyle(PixelHandTheme.accent)
            Text(model.presence.pillCaption(frontApp: target.frontApp))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PixelHandTheme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .frame(minHeight: PixelHandTheme.ControlHeight.hit)
        .background(Capsule().fill(PixelHandTheme.raised).shadow(color: .black.opacity(0.12), radius: 12, y: 3))
        .overlay(Capsule().strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline))
        .contentShape(Capsule())
        .onTapGesture {
            GestureHaptic.selection.trigger()
            model.expand()
        }
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { chrome.onGripChanged($0.translation) }
                .onEnded { chrome.onGripEnded($0.translation) }
        )
        .contextMenu {
            Button("Open") { model.expand() }
            Button("Hide keyboard") { model.close() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard panel, collapsed: \(model.presence.pillCaption(frontApp: target.frontApp))")
        .accessibilityHint("Double-tap to open it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.expand() }
        .accessibilityIdentifier("ph.type.pill")
    }
}

// MARK: - Host

/// Where the shell shows the panel: one place for every arrangement, so the
/// field keeps its identity (and the keyboard) through rotation, Stage
/// Manager resizes and form changes (OT-2). The person moves, resizes and
/// folds it (OT-6); Core's `TypePanelGeometry` keeps it in the free room
/// above the keyboard and the dock, snaps it, and the place is remembered
/// per arrangement and orientation.
struct TypePanelHost: View {
    let session: ControlSessionModel
    let model: TypePanelModel
    /// The window's size, as the shell plans from it.
    let windowSize: CGSize
    /// Whether the form shows the app dock (its last measured top is
    /// stale otherwise).
    var showsDock = true
    /// The arrangement (`CanvasPlan.Form`'s raw value), for remembering one
    /// place per arrangement.
    var arrangement = "single"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var placement = TypePanelPlacement.initial
    @State private var loadedKey: String?
    /// The panel's (or pill's) measured size.
    @State private var measured: CGSize = .zero
    /// A drag or resize in flight: where it started and where it is.
    @State private var gestureStart: PanelRect?
    @State private var liveFrame: PanelRect?

    private var storageKey: String {
        TypePanelPlacement.storageKey(
            arrangement: arrangement,
            orientation: PanelOrientation(width: Double(windowSize.width), height: Double(windowSize.height))
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.frame(in: .global)
            let geometry = TypePanelGeometry(
                container: PanelRect(x: Double(container.minX), y: Double(container.minY), width: Double(container.width), height: Double(container.height)),
                windowWidth: Double(windowSize.width),
                windowHeight: Double(windowSize.height),
                keyboardMinY: model.keyboardMinY,
                dockMinY: showsDock ? model.dockMinY.map { Double($0) } : nil
            )
            let width = liveFrame?.width ?? geometry.width(for: placement)
            let layout = TypePanelLayout(
                width: Double(windowSize.width),
                height: Double(windowSize.height),
                keyboard: model.keyboard,
                keyboardOverlap: model.keyboardOverlap,
                panelWidth: width,
                showsNumpad: model.presence.tab == .numpad
            )
            let size = (
                width: measured == .zero ? layout.panelWidth : Double(measured.width),
                height: measured == .zero ? 200 : Double(measured.height)
            )
            let frame = liveFrame.map { PanelRect(x: $0.x, y: $0.y, width: $0.width, height: size.height) }
                ?? geometry.frame(for: placement, size: model.isCollapsed ? size : (width: width, height: size.height))
            let handles = panelChrome(geometry: geometry, frame: frame)

            ZStack(alignment: .topLeading) {
                if model.isShown, let sender = session.sender {
                    Group {
                        if model.isCollapsed {
                            TypePanelPill(model: model, chrome: handles)
                        } else {
                            TypePanel(sender: sender, clipboard: session.clipboard, model: model, layout: layout, chrome: handles)
                                .overlay(alignment: .bottomLeading) {
                                    if geometry.canResize { resizeHandle(.leading, geometry: geometry, frame: frame) }
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if geometry.canResize { resizeHandle(.trailing, geometry: geometry, frame: frame) }
                                }
                        }
                    }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = $0 }
                    .offset(x: CGFloat(frame.x) - container.minX, y: CGFloat(frame.y) - container.minY)
                    .transition(.opacity) // Glyph rule: panels fade, never slide.
                }
            }
            .frame(width: container.width, height: container.height, alignment: .topLeading)
            .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: model.isShown)
            .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: model.isCollapsed)
        }
        // The panel places itself against the keyboard; it must not be
        // pushed up by the keyboard's safe area as well.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Build 25 bug 1: a keyboard frame reported mid-rotation is read
        // again against the turned window, so the free room ends above the
        // keyboard in the new orientation and the panel (and its close
        // button) stays in view.
        .onChange(of: windowSize) { _, _ in
            DispatchQueue.main.async { model.refreshKeyboard() }
        }
        .onChange(of: storageKey, initial: true) { _, key in
            guard loadedKey != key else { return }
            loadedKey = key
            placement = TypePanelPlacement.restored(UserDefaults.standard.data(forKey: key)) ?? .initial
        }
    }

    // MARK: Moving

    private func panelChrome(geometry: TypePanelGeometry, frame: PanelRect) -> TypePanelChrome {
        TypePanelChrome(
            onGripChanged: { translation in
                let start = gestureStart ?? frame
                if gestureStart == nil { gestureStart = start }
                liveFrame = geometry.clamped(
                    origin: start.x + Double(translation.width),
                    start.y + Double(translation.height),
                    size: (start.width, start.height)
                )
            },
            onGripEnded: { translation in
                let start = gestureStart ?? frame
                let dropped = geometry.placement(
                    droppedAt: start.x + Double(translation.width),
                    start.y + Double(translation.height),
                    size: (start.width, start.height),
                    keeping: placement
                )
                settle(dropped)
            },
            onCollapse: { model.collapse() },
            onPlace: { x, y in
                var next = placement
                if let x { next.x = x }
                if let y { next.y = y }
                settle(next)
            }
        )
    }

    /// The bottom corners resize; the other edge holds (OT-6). The 44 pt
    /// target straddles the card's corner, mostly outside it, so it never
    /// takes taps meant for ⌫ or fn in the corners of the key block; the
    /// mark itself sits just inside the corner.
    private func resizeHandle(_ edge: TypePanelGeometry.ResizeEdge, geometry: TypePanelGeometry, frame: PanelRect) -> some View {
        let target = CGFloat(TypePanelGeometry.handleTarget)
        let outside: CGFloat = 26
        return PHGlyph(glyph: PixelGlyphs.resizeCorner, pitch: 1.4)
            .foregroundStyle(PixelHandTheme.ink3)
            .scaleEffect(x: edge == .leading ? -1 : 1, y: 1)
            .padding(4)
            .frame(width: target, height: target, alignment: edge == .leading ? .topTrailing : .topLeading)
            .contentShape(Rectangle())
            .offset(x: edge == .leading ? -outside : outside, y: outside)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        let start = gestureStart ?? frame
                        if gestureStart == nil { gestureStart = start }
                        liveFrame = geometry.resized(start, edge: edge, translation: Double(value.translation.width))
                    }
                    .onEnded { value in
                        let start = gestureStart ?? frame
                        let end = geometry.resized(start, edge: edge, translation: Double(value.translation.width))
                        settle(geometry.placement(resizedTo: end, keeping: placement))
                    }
            )
            .hoverEffect(.highlight)
            .accessibilityElement()
            .accessibilityLabel(edge == .leading ? "Resize from the left corner" : "Resize from the right corner")
            .accessibilityValue("\(Int(frame.width)) points wide")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 40.0 : -40.0
                var next = placement
                next.width = geometry.clampWidth(frame.width + step)
                settle(next)
            }
            .accessibilityIdentifier("ph.type.resize.\(edge.rawValue)")
    }

    /// Ends a gesture: the new place, snapped with a short spring (none
    /// under Reduce Motion), and remembered.
    private func settle(_ next: TypePanelPlacement) {
        GestureHaptic.selection.trigger()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            placement = next
            liveFrame = nil
            gestureStart = nil
        }
        UserDefaults.standard.set(next.stored, forKey: storageKey)
    }
}
