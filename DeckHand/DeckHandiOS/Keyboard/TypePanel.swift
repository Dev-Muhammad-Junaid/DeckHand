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
    /// The Mac app's icon for the header (from the installed-apps list),
    /// `nil` when unknown.
    var targetIcon: Image?
    /// The header's target chip zooms to the Mac's focused field (OT-12).
    /// `nil` where there is no loupe (the classic layout).
    var zoom: TypePanelZoom?
    /// A key or text went to the Mac (forgets what a gesture opened).
    var onActivity: () -> Void = {}
    /// Live text sync (protocol 17): the Mac's focused field in the Live
    /// field. `nil` keeps Live blind (the classic layout).
    var liveSync: LiveTextSync? = nil
    /// The Live field opened (`true`) or closed: the Mac sends text only
    /// while it's open (`ControlSessionModel.setLiveTextWanted`).
    var onLiveTextWanted: ((Bool) -> Void)? = nil

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.entitlements) private var entitlements
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A Return held back while the person confirms the app (VQ-036).
    @State private var heldReturn: (() -> Void)?
    /// The arrow joystick (hold an arrow, then drag).
    @State private var joystick = ArrowJoystickModel()
    private let target = TypingTarget.shared

    private var presence: TypePanelPresence { model.presence }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(TypePanelLayout.headerSpacing)) {
            if layout.showsHeader {
                // Build 30 bug 2: the header is cut to the card's inner
                // width like every block, so nothing it holds can run past
                // the card (the panel measured 12 pt wider than the card
                // its numpad fills).
                header
                    .frame(
                        width: CGFloat(max(0, layout.panelWidth - 2 * TypePanelLayout.padding)),
                        height: CGFloat(layout.headerRows) * CGFloat(TypePanelLayout.headerHeight)
                            + CGFloat(max(0, layout.headerRows - 1)) * CGFloat(TypePanelLayout.headerSpacing),
                        alignment: .leading
                    )
            }
            // Every block at the frame Core cut for it from the panel's
            // width and height (OT-11): nothing sized by its content, so
            // nothing is left over. Always all five subviews, in one order:
            // a hidden block gets no size but keeps its identity, so the
            // field never hands the keyboard to a new view (OT-2).
            PanelBodyLayout(layout: layout) {
                fieldColumn
                actionBlock
                arrowCluster
                    // The joystick's trail runs over the field and keys.
                    .zIndex(joystick.isEngaged ? 1 : 0)
                keyBlock
                // One subview either way (the body layout places five).
                if layout.shows(.numpad) {
                    NumpadGrid { key in press(key) }
                } else {
                    Color.clear
                }
            }
        }
        .padding(CGFloat(TypePanelLayout.padding))
        .frame(width: CGFloat(layout.panelWidth), height: CGFloat(layout.panelHeight), alignment: .topLeading)
        // Live text sync: the Mac reads its field's text only while Live
        // is open on screen.
        .onAppear {
            liveSync?.confirmReturn = { send in guardReturn(if: true, send: send) }
            onLiveTextWanted?(presence.mode == .live)
        }
        .onDisappear { onLiveTextWanted?(false) }
        .onChange(of: presence.mode) { _, mode in onLiveTextWanted?(mode == .live) }
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .fill(PixelHandTheme.raised)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
        )
        // Build 30 bug 2: the card itself, measured by the walks (a
        // `.contain` element's frame is built from its children, so
        // `ph.type.panel` can read wider than the card).
        .background {
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .fill(Color.clear)
                .accessibilityElement()
                .accessibilityLabel("Keyboard panel")
                .accessibilityValue("\(Int(layout.panelWidth)) by \(Int(layout.panelHeight)) points")
                .accessibilityIdentifier("ph.type.card")
        }
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

    /// One row: grip, mode, the target chip, numpad, collapse, close. On
    /// narrow panels (`headerRows == 2`) the mode switch and the app's
    /// name take a second row, so neither row is left half empty.
    @ViewBuilder
    private var header: some View {
        if layout.headerRows >= 2 {
            VStack(alignment: .leading, spacing: CGFloat(TypePanelLayout.headerSpacing)) {
                HStack(spacing: PixelHandTheme.Space.xs) {
                    gripHandle
                    targetChip(showsName: false)
                    Spacer(minLength: 0)
                    headerButtons
                }
                .frame(height: CGFloat(TypePanelLayout.headerHeight))
                HStack(spacing: PixelHandTheme.Space.sm) {
                    ModeSwitch(mode: $model.mode)
                    statusText
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: CGFloat(TypePanelLayout.headerHeight))
            }
        } else {
            HStack(spacing: PixelHandTheme.Space.xs) {
                gripHandle
                ModeSwitch(mode: $model.mode)
                targetChip(showsName: layout.showsAppName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                headerButtons
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

    /// Where keys go, shown once (OT-11): the Mac app's icon, its name when
    /// there's room, and a small magnifier. Tapping it zooms to the Mac's
    /// focused field (OT-12, Pro); without a loupe it only names the app.
    @ViewBuilder
    private func targetChip(showsName: Bool) -> some View {
        let caption = TypingTargetGuard.caption(frontApp: target.frontApp)
        let label = HStack(spacing: PixelHandTheme.Space.xs) {
            Group {
                if let targetIcon {
                    targetIcon.resizable().interpolation(.high).scaledToFit()
                } else {
                    PHGlyph(glyph: PixelGlyphs.keyboard, pitch: CGFloat(PixelPitch.badge), stepsWithType: true)
                }
            }
            .frame(width: 24, height: 24)
            if showsName {
                statusText
            }
            if zoom != nil {
                PHGlyph(glyph: PixelGlyphs.find, pitch: 1.4)
                    .foregroundStyle(zoom?.isOn == true ? PixelHandTheme.accentInk : PixelHandTheme.ink2)
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.sm)
        .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.secondary)
        .background(Capsule().fill(zoom?.isOn == true ? PixelHandTheme.accentTint : PixelHandTheme.fill))
        .frame(height: PixelHandTheme.ControlHeight.hit)
        .contentShape(Rectangle())

        if let zoom {
            Button {
                GestureHaptic.selection.trigger()
                zoom.toggle()
            } label: { label }
                .buttonStyle(ChipPressStyle())
                .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.secondary / 2)
                .accessibilityLabel("\(caption). Zoom to the input")
                .accessibilityValue(zoom.isOn ? "Shown" : "Hidden")
                .accessibilityAddTraits(zoom.isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("ph.type.target")
                .requiresPro(.mirror, badge: .capsule(.bottomTrailing))
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(caption)
                .accessibilityIdentifier("ph.type.target")
        }
    }

    /// The app's name, or what the last paste did for a moment (S10), in
    /// the header: one line, no separate clipboard row eating the panel's
    /// height.
    private var statusText: some View {
        Text(clipboard?.pasteStatus ?? (target.frontApp ?? "Mac"))
            .font(.caption.weight(.medium))
            .foregroundStyle(PixelHandTheme.ink2)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityHidden(true)
    }

    /// The numpad replaces the key rows or goes away (OT-7, OT-11).
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

    /// The field fills its frame (as tall as the arrows beside it, two
    /// lines when there's room). Without the header (short room), the grip
    /// and close sit beside it. Hidden in Live with the numpad on, but
    /// kept in the tree.
    private var fieldColumn: some View {
        HStack(spacing: PixelHandTheme.Space.xs) {
            if !layout.showsHeader { gripHandle }
            // No header (iPhone landscape, keyboard up): the target chip
            // comes with the grip, so the app (and the loupe's button) is
            // still shown once (build 27 bug 5, VQ-105).
            if layout.targetPlace == .fieldRow { targetChip(showsName: false) }
            field
            if !layout.showsHeader { closeButton }
        }
        .opacity(layout.shows(.field) ? 1 : 0)
        .allowsHitTesting(layout.shows(.field))
    }

    private var field: some View {
        LiveTypingField(
            mode: presence.mode,
            // The target chip names the app, in the header or, with no
            // header, beside the field (`targetPlace`): the placeholder
            // stays neutral, so the target shows exactly once.
            // Blind Live says why it can't show the Mac's text ("Password
            // field: the text stays on the Mac").
            placeholder: (presence.mode == .live ? liveSync?.reasonLine : nil) ?? presence.mode.placeholder,
            latchedModifiers: presence.modifiers.held,
            draft: $model.draft,
            wantsFocus: presence.wantsFocus || layout.body == .keysOnly,
            focusRequest: presence.focusRequest,
            composeLines: layout.fieldLines,
            fillsHeight: true,
            onEdit: { edit in
                onActivity()
                guardReturn(if: edit.insert.contains("\n")) {
                    Task { await sender.sendTypingEdit(edit) }
                }
            },
            onKey: { key, modifiers in
                onActivity()
                guardReturn(if: key == .return) {
                    sendKeys(key.chord(with: modifiers))
                }
            },
            onChord: { keys in
                onActivity()
                sendKeys(keys)
            },
            onModifiersUsed: { _ = model.presence.modifiers.consume() },
            onSubmit: { sendDraft() },
            onFocus: { model.presence.fieldFocused() },
            sync: liveSync
        )
        .padding(.horizontal, PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if presence.mode == .live, let liveSync {
                SyncBadgeView(badge: liveSync.badge, reason: liveSync.reasonLine)
                    .padding(PixelHandTheme.Space.xs)
            }
        }
        // Build 29 bug 9: when the Mac can't put its caret where an edit
        // goes it types nothing (never at a guessed place) and says so.
        .overlay(alignment: .bottomLeading) {
            if presence.mode == .live, let note = liveSync?.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(PixelHandTheme.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.badge, style: .continuous)
                            .fill(PixelHandTheme.warningTint)
                    )
                    .padding(PixelHandTheme.Space.xs)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("ph.type.syncNote")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(PixelHandTheme.fill)
        )
    }

    // MARK: Actions (OT-11, OT-13)

    /// Beside the field: Live has Accept (Tab, which takes the Mac app's
    /// inline suggestion) and Paste; Compose has +⏎ and Send. A column of
    /// two next to the inverted T, a row of two next to the one-row arrows.
    private var actionBlock: some View {
        let grid = layout.grid(.actions)
        return KeyGrid(grid: grid) {
            ForEach(layout.actionCells, id: \.action) { cell in
                actionButton(cell.action)
                    .keyCell(column: cell.column, row: cell.row, rowSpan: cell.rowSpan)
            }
        }
        .opacity(grid == nil ? 0 : 1)
        .allowsHitTesting(grid != nil)
        .accessibilityHidden(grid == nil)
    }

    @ViewBuilder
    private func actionButton(_ action: TypePanelLayout.Action) -> some View {
        switch action {
        case .accept: acceptButton
        case .paste: pasteButton
        case .sendReturn: sendReturnToggle
        case .send: sendButton
        }
    }

    /// Accept (⇥): presses Tab on the Mac, which is how Claude, Xcode,
    /// Mail and most editors take their grey inline suggestion. The loupe
    /// shows the suggestion; this makes taking it one obvious tap (OT-13).
    /// With live text sync the accepted text then shows in the field from
    /// the Mac's next value change (no edit is sent for it).
    private var acceptButton: some View {
        Button {
            onActivity()
            GestureHaptic.light.trigger()
            let modifiers = model.presence.modifiers.consume()
            target.guardrail.typed(into: target.frontApp)
            sendKeys(TypeKey.remote(.tab).chord(with: modifiers))
        } label: {
            KeyCap(legend: .stacked(symbol: "⇥", word: "ACCEPT"), style: .tint)
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
        .accessibilityLabel("Accept suggestion")
        .accessibilityHint("Presses Tab on the Mac, which takes the app's inline suggestion.")
        .accessibilityIdentifier("ph.type.accept")
    }

    /// Paste this device's clipboard on the Mac (the clipboard feature's
    /// setting decides whether it lands at the Mac's cursor or on its
    /// clipboard). Compose's field is local, so the system's own Paste
    /// works in it; the button is Live's.
    private var pasteButton: some View {
        PasteToMacControl(iconOnly: true) { text in
            onActivity()
            clipboard?.pasteToMac(text, paste: settings.pasteRightAway, sender: sender)
        }
        .padding(CGFloat(TypePanelLayout.keyGap) / 2)
        .accessibilityHint(settings.pasteRightAway ? "Pastes at the Mac’s cursor" : "Puts the text on the Mac’s clipboard")
        .accessibilityIdentifier("ph.type.paste")
        .requiresPro(.sharing)
    }

    private var sendReturnToggle: some View {
        let isOn = model.sendsReturn
        return Button {
            GestureHaptic.selection.trigger()
            model.sendsReturn.toggle()
        } label: {
            KeyCap(legend: .text("+⏎"), style: isOn ? .tint : .plain)
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
        .accessibilityLabel("Press Return after sending")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("ph.type.sendReturn")
    }

    private var sendButton: some View {
        let enabled = ComposeSend.canSend(draft: model.draft, withReturn: model.sendsReturn)
        return Button(action: sendDraft) {
            KeyCap(legend: .dots("SEND"), style: enabled ? .accent : .plain)
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(ChipPressStyle())
        .disabled(!enabled)
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
        .accessibilityLabel(model.sendsReturn ? "Send, then press Return" : "Send")
        .accessibilityIdentifier("ph.type.send")
    }

    // MARK: Arrows and keys (OT-7, OT-11)

    /// The inverted T (↑ over ← ↓ →), or one row (← ↑ ↓ →) at the
    /// shortest; cells as big as the panel gives them. Hold an arrow, then
    /// drag: the arrow joystick (`ArrowJoystick.swift`).
    private var arrowCluster: some View {
        let terminal = target.isTerminal
        return KeyGrid(grid: layout.grid(.arrows)) {
            CaretStepperElement(
                model: joystick,
                isTerminal: terminal,
                held: { model.presence.modifiers.held },
                send: { step in sendJoystickStep(step) }
            )
            ForEach(ArrowCluster.cells(for: layout.arrowShape), id: \.key) { cell in
                arrowButton(cell.key, terminal: terminal)
                    .keyCell(column: cell.column, row: cell.row)
            }
            ArrowJoystickOverlay(model: joystick)
            ArrowJoystickQAProbe(model: joystick)
        }
        .onDisappear { joystick.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Arrow keys")
        .accessibilityIdentifier("ph.type.arrows")
    }

    /// Two rows across the panel's width: ⌘ ⌥ ⌃ ⇧ esc tab / ⌫ ⏎ home end
    /// pg↑ pg↓ fn. With fn on, the second row's keys give way to a strip of
    /// F1–F12. Gone while the numpad shows (OT-11).
    private var keyBlock: some View {
        let fnOn = presence.showsFunctionKeys
        let grid = layout.grid(.keys)
        return KeyGrid(grid: grid) {
            ForEach(TypeKeyBlock.cells.filter { !(fnOn && $0.row == 1 && $0.item != .fn) }, id: \.item) { cell in
                blockItem(cell.item)
                    .keyCell(column: cell.column, row: cell.row, columnSpan: cell.columnSpan)
            }
            if fnOn {
                functionStrip
                    .keyCell(column: 0, row: 1, columnSpan: TypeKeyBlock.functionStripColumns)
            }
        }
        .opacity(grid == nil ? 0 : 1)
        .allowsHitTesting(grid != nil)
        .accessibilityHidden(grid == nil)
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
        let cell = layout.grid(.keys).map { CGSize(width: $0.cellWidth, height: $0.cellHeight) }
            ?? CGSize(width: TypePanelLayout.keyPitch, height: TypePanelLayout.keyPitch)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(TypeKeysRow.functionKeys) { key in
                    keyButton(key)
                        .frame(width: cell.width, height: cell.height)
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

    private func keyButton(_ key: TypeKey, style: KeyCap.Style? = nil, legend: KeyCap.Legend? = nil) -> some View {
        Button {
            press(key)
        } label: {
            KeyCap(legend: legend ?? KeyCap.Legend(key), style: style ?? (key.isReturn ? .accent : .plain))
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd)
        .accessibilityLabel(key.spokenName)
        .accessibilityIdentifier("ph.type.key.\(key.wireName)")
    }

    /// An arrow cap: a key button that is also the joystick's handle.
    /// While the joystick runs, the held cap is lit (accent, centre dot),
    /// the cap it's moving toward is tinted, and in a terminal ↑/↓ read
    /// HISTORY.
    @ViewBuilder
    private func arrowButton(_ key: TypeKey, terminal: Bool) -> some View {
        if case let .remote(arrow) = key, let cell = ArrowCluster.cells(for: layout.arrowShape).first(where: { $0.key == key }) {
            let style = arrowStyle(arrow)
            let vertical = arrow == .up || arrow == .down
            keyButton(key, style: style, legend: arrowLegend(key, arrow: arrow, terminal: terminal))
                .animation(PixelHandMotion.reduced(PixelHandMotion.quick, reduceMotion: reduceMotion), value: style)
                .arrowJoystick(key: arrow, column: cell.column, row: cell.row, model: joystick) {
                    ArrowJoystickModel.Context(
                        held: model.presence.modifiers.held,
                        isTerminal: target.isTerminal,
                        tap: { _ in press(key) },
                        engaged: {
                            onActivity()
                            target.guardrail.typed(into: target.frontApp)
                        },
                        send: { step in sendJoystickStep(step) },
                        finished: { _ = model.presence.modifiers.consume() }
                    )
                }
                .accessibilityActions {
                    // Terminals have no paragraphs: ⌥↑ is no use there.
                    if !(terminal && vertical) {
                        Button(vertical ? "Move by paragraphs" : "Move by words") {
                            sendJoystickStep(CaretJoystick.Step(key: arrow, modifiers: [.option]))
                        }
                    }
                }
        } else {
            keyButton(key)
        }
    }

    private func arrowStyle(_ arrow: RemoteKey) -> KeyCap.Style {
        guard joystick.isEngaged else { return .plain }
        if joystick.heldKey == arrow { return .lit }
        if joystick.engine.readout?.key == arrow { return .tint }
        return .plain
    }

    /// While the joystick runs, the held cap gives its glyph up to the
    /// centre dot (the stick, drawn by the overlay), and in a terminal
    /// ↑/↓ read HISTORY.
    private func arrowLegend(_ key: TypeKey, arrow: RemoteKey, terminal: Bool) -> KeyCap.Legend? {
        guard joystick.isEngaged else { return nil }
        if joystick.heldKey == arrow { return .dots("") }
        guard terminal, arrow == .up || arrow == .down, let glyph = KeyCap.arrowGlyph(arrow) else { return nil }
        return .glyphWord(glyph, word: "HISTORY", label: key.spokenName)
    }

    /// One joystick or caret-stepper press.
    private func sendJoystickStep(_ step: CaretJoystick.Step) {
        sendKeys(step.chord)
    }

    /// A key cap's press: sends the key with the latched modifiers
    /// (holding a Return that would land in another app).
    private func press(_ key: TypeKey) {
        onActivity()
        GestureHaptic.light.trigger()
        let modifiers = model.presence.modifiers.consume()
        guardReturn(if: key.isReturn) {
            sendKeys(key.chord(with: modifiers))
        }
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

    /// The live field shows the Mac's text: keys go through its queue.
    private var syncedLive: LiveTextSync? {
        guard model.presence.mode == .live, let liveSync, liveSync.isSynced else { return nil }
        return liveSync
    }

    /// A key chord for the Mac's caret. In synced Live it waits behind the
    /// edit typed before it (build 29 bug 9: Accept ⇥ overtook the text);
    /// otherwise it goes at once, as before.
    private func sendKeys(_ keys: [String]) {
        if let syncedLive {
            syncedLive.sendRaw(.keys(keys))
        } else {
            Task { await sender.sendShortcut(keys) }
        }
    }

    /// Text typed at the Mac's caret (the numpad), in the same order.
    private func sendText(_ text: String) {
        if let syncedLive {
            syncedLive.sendRaw(.text(text))
        } else {
            Task { await sender.typeText(text) }
        }
    }

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
                sendText(text)
            } else if KeyTable.keyCode(for: text) != nil {
                sendKeys(KeyModifier.pressOrder.filter(modifiers.contains).map(\.wireName) + [text])
            } else {
                sendText(text)
            }
        case let .key(name):
            guardReturn(if: key == .enter) {
                sendKeys(KeyModifier.pressOrder.filter(modifiers.contains).map(\.wireName) + [name])
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

/// The header's zoom switch (OT-12): whether the loupe shows, and how to
/// flip it. The host owns the state.
struct TypePanelZoom {
    var isOn: Bool
    var toggle: () -> Void
}

// MARK: - Sync badge (live text sync)

/// The Live field's sync badge, dot-matrix in its top-trailing corner:
/// SYNC with a mint pixel (live), SENDING with a glow pixel (an edit in
/// flight), MAC WINS in amber for 1.4 s after a conflict, BLIND dim when
/// the field can't be read. Decorative for touch (it takes none); VoiceOver
/// reads the state and, when blind, the reason.
struct SyncBadgeView: View {
    let badge: SyncBadge
    var reason: String?

    var body: some View {
        HStack(spacing: 3) {
            Rectangle()
                .fill(pixelColor)
                .frame(width: 3, height: 3)
                .shadow(color: badge == .sending ? PixelHandTheme.Brand.glow : .clear, radius: 2)
            DotMatrixText(badge.label, pitch: 1.3, label: badge.spokenLabel, glows: false, stepsWithType: false)
                .foregroundStyle(wordColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.badge, style: .continuous)
                .fill(badge == .macWins ? PixelHandTheme.warningTint : PixelHandTheme.fill2)
        )
        .opacity(badge == .blind ? 0.6 : 1)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: badge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.spokenLabel)
        .accessibilityValue(badge == .blind ? (reason ?? "") : "")
        .accessibilityIdentifier("ph.type.sync")
    }

    private var pixelColor: Color {
        switch badge {
        case .sync: PixelHandTheme.Brand.mint
        case .sending: PixelHandTheme.Brand.phosphor
        case .macWins: PixelHandTheme.warning
        case .blind: PixelHandTheme.ink3
        }
    }

    private var wordColor: Color {
        switch badge {
        case .macWins: PixelHandTheme.warning
        case .blind: PixelHandTheme.ink3
        default: PixelHandTheme.ink2
        }
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

/// Places the field, the actions, the arrows, the key rows and the numpad
/// at the frames `TypePanelLayout` cut from the panel (OT-11). A `Layout`,
/// so the five keep their identity when the arrangement changes and the
/// field never loses the keyboard to a reflow; a block the layout doesn't
/// show gets a zero frame.
private struct PanelBodyLayout: Layout {
    let layout: TypePanelLayout

    private static let order: [TypePanelLayout.Block] = [.field, .actions, .arrows, .keys, .numpad]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = layout.bodySize
        return CGSize(width: size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let block = index < Self.order.count ? Self.order[index] : .numpad
            guard let rect = layout.grid(block)?.rect else {
                subview.place(at: bounds.origin, proposal: .zero)
                continue
            }
            subview.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                proposal: ProposedViewSize(width: rect.width, height: rect.height)
            )
        }
    }
}

// MARK: - Key caps

/// The cell size of the grid a key sits in (Core's `Grid`: 44 pt and up,
/// wider than tall in the key rows).
private struct TypeKeyCellKey: EnvironmentKey {
    static let defaultValue = CGSize(width: TypePanelLayout.keyPitch, height: TypePanelLayout.keyPitch)
}

extension EnvironmentValues {
    var typeKeyCell: CGSize {
        get { self[TypeKeyCellKey.self] }
        set { self[TypeKeyCellKey.self] = newValue }
    }
}

/// A grid of key cells at a Core block's size: each key fills its cell's
/// touch target and draws a cap 4 pt smaller inside it.
private struct KeyGrid<Content: View>: View {
    let grid: TypePanelLayout.Grid?
    @ViewBuilder let content: Content

    var body: some View {
        let cell = CGSize(width: grid?.cellWidth ?? 0, height: grid?.cellHeight ?? 0)
        ZStack(alignment: .topLeading) {
            // A block the layout doesn't show (the key rows and the
            // actions in numpad mode, OT-11) draws nothing at all: build
            // 28 bug 7 had the ⌘⌥⌃⇧ row and the key rows still on screen
            // and hittable beside the numpad, zero-sized caps overflowing
            // their empty frame. Only the field has to keep its identity
            // (OT-2), and it isn't in a grid.
            if grid != nil {
                content
            }
        }
        .frame(width: CGFloat(grid?.rect.width ?? 0), height: CGFloat(grid?.rect.height ?? 0), alignment: .topLeading)
        .environment(\.typeKeyCell, cell)
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

    @Environment(\.typeKeyCell) private var cell

    func body(content: Content) -> some View {
        content
            .frame(width: CGFloat(columnSpan) * cell.width, height: CGFloat(rowSpan) * cell.height)
            .offset(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height)
    }
}

/// How much bigger than a 44 pt cell this one is (legends grow with the
/// keys, up to 1.5×).
private func legendScale(_ cell: CGSize) -> CGFloat {
    let side = min(cell.width, cell.height)
    guard side > 0 else { return 1 }
    return min(1.5, max(0.8, side / CGFloat(TypePanelLayout.keyPitch)))
}

/// One key cap inside its cell, the legend in the dot-matrix font (words),
/// a pixel glyph (arrows) or the rounded chord face (⌘ ⌥ ⌃ ⇧ ⌫ ⏎), scaled
/// with the cell.
private struct KeyCap: View {
    enum Legend {
        case dots(String)
        case glyph(GlyphBitmap, label: String)
        case text(String)
        /// A symbol over a small dot-matrix word (Accept ⇥).
        case stacked(symbol: String, word: String)
        /// A pixel glyph over a small dot-matrix word (↑ HISTORY in a
        /// terminal, while the joystick runs).
        case glyphWord(GlyphBitmap, word: String, label: String)

        init(_ key: TypeKey) {
            if let legend = key.dotMatrixLegend {
                self = .dots(legend)
                return
            }
            if case let .remote(arrow) = key, let glyph = KeyCap.arrowGlyph(arrow) {
                self = .glyph(glyph, label: key.spokenName)
            } else {
                self = .text(key.cap)
            }
        }
    }

    /// The pixel glyph for an arrow key.
    static func arrowGlyph(_ key: RemoteKey) -> GlyphBitmap? {
        switch key {
        case .up: PixelGlyphs.keyUp
        case .down: PixelGlyphs.keyDown
        case .left: PixelGlyphs.keyLeft
        case .right: PixelGlyphs.keyRight
        default: nil
        }
    }

    enum Style {
        case plain, accent, lit, tint
    }

    let legend: Legend
    var style: Style = .plain
    var isLocked = false

    @Environment(\.typeKeyCell) private var cell

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
        let scale = legendScale(cell)
        ZStack {
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                .fill(plate)
            switch legend {
            case let .dots(text):
                DotMatrixText(text, pitch: 1.4 * scale, label: text, glows: false, stepsWithType: false)
            case let .glyph(glyph, label):
                PHGlyph(glyph: glyph, pitch: 1.6 * scale)
                    .accessibilityLabel(label)
            case let .text(text):
                Text(text)
                    .font(.system(size: 16 * scale, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case let .glyphWord(glyph, word, label):
                VStack(spacing: 2 * scale) {
                    PHGlyph(glyph: glyph, pitch: 1.2 * scale)
                    DotMatrixText(word, pitch: 0.9 * scale, label: word, glows: false, stepsWithType: false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
            case let .stacked(symbol, word):
                VStack(spacing: 2 * scale) {
                    Text(symbol)
                        .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
                    DotMatrixText(word, pitch: 0.9 * scale, label: word, glows: false, stepsWithType: false)
                }
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
/// 1 2 3 − / 0 . = +, Enter three rows tall in the last column, cells as
/// big as the panel gives them (OT-11). Operators in accent ink; Enter on
/// the accent.
struct NumpadGrid: View {
    let onPress: (NumpadKey) -> Void

    var body: some View {
        GeometryReader { proxy in
            let cell = CGSize(
                width: proxy.size.width / CGFloat(NumpadKey.columns),
                height: proxy.size.height / CGFloat(NumpadKey.rows)
            )
            ZStack(alignment: .topLeading) {
                ForEach(NumpadKey.allCases) { key in
                    let place = key.cell
                    NumpadKeyButton(key: key) { onPress(key) }
                        .keyCell(column: place.column, row: place.row, columnSpan: place.columnSpan, rowSpan: place.rowSpan)
                }
            }
            .environment(\.typeKeyCell, cell)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Numpad")
        .accessibilityIdentifier("ph.type.numpad")
    }
}

private struct NumpadKeyButton: View {
    let key: NumpadKey
    let action: () -> Void

    @Environment(\.typeKeyCell) private var cell

    var body: some View {
        let scale = legendScale(cell)
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                    .fill(key == .enter ? PixelHandTheme.accent : PixelHandTheme.fill)
                if key == .delete {
                    Text("⌫")
                        .font(.system(size: 16 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(PixelHandTheme.ink)
                } else if key == .enter {
                    // Three cells tall: the word stands up the key.
                    DotMatrixText("ENT", pitch: 1.4 * scale, label: key.spokenName, glows: false, stepsWithType: false)
                        .foregroundStyle(Color.white)
                } else {
                    DotMatrixText(key.cap, pitch: 2 * scale, label: key.spokenName, glows: false, stepsWithType: false)
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
    @Environment(\.entitlements) private var entitlements
    @State private var placement = TypePanelPlacement.initial
    @State private var loadedKey: String?
    /// The panel's (or pill's) measured size.
    @State private var measured: CGSize = .zero
    /// A drag or resize in flight: where it started and where it is.
    @State private var gestureStart: PanelRect?
    @State private var liveFrame: PanelRect?
    /// The loupe on the Mac's focused field is open (OT-12).
    @State private var showsLoupe = false

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
            // OT-11: the panel's height is the person's too; the layout
            // cuts every block from width × height, and shrinks to the
            // free room when the keyboard leaves less.
            let layout = panelLayout(width: width, height: liveFrame?.height ?? geometry.height(for: placement), room: geometry.room.height)
            let pill = (
                width: measured == .zero ? 200 : Double(measured.width),
                height: measured == .zero ? 44 : Double(measured.height)
            )
            // Build 28 bug 6: whatever the frame came from (the remembered
            // place, a drag or resize in flight, a size from before the
            // keyboard came up or the window turned), it is kept in the
            // free room above the keyboard, moved and never resized.
            let frame = geometry.kept(
                liveFrame.map { PanelRect(x: $0.x, y: $0.y, width: $0.width, height: layout.panelHeight) }
                    ?? geometry.frame(for: placement, size: model.isCollapsed ? pill : (width: width, height: layout.panelHeight))
            )
            let handles = panelChrome(geometry: geometry, frame: frame)

            ZStack(alignment: .topLeading) {
                if model.isShown, let sender = session.sender {
                    Group {
                        if model.isCollapsed {
                            TypePanelPill(model: model, chrome: handles)
                        } else {
                            TypePanel(
                                sender: sender,
                                clipboard: session.clipboard,
                                model: model,
                                layout: layout,
                                chrome: handles,
                                targetIcon: session.activeBundleID.flatMap { id in
                                    DeckAppIcons.image(for: id, in: Dictionary(session.installedApps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first }))
                                },
                                zoom: TypePanelZoom(isOn: showsLoupe) { showsLoupe.toggle() },
                                liveSync: session.liveText,
                                onLiveTextWanted: { session.setLiveTextWanted($0) }
                            )
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
                // OT-12: the loupe on the Mac's focused field, attached to
                // the panel (above it, or below when it's parked at the
                // top). Pro, like the mirror it cuts from.
                if model.isShown, !model.isCollapsed, showsLoupe, entitlements.allows(.mirror),
                   let loupe = geometry.loupeFrame(panel: frame) {
                    FocusLoupeView(session: session)
                        .frame(width: CGFloat(loupe.width), height: CGFloat(loupe.height))
                        .offset(x: CGFloat(loupe.x) - container.minX, y: CGFloat(loupe.y) - container.minY)
                        .transition(.opacity)
                }
            }
            .frame(width: container.width, height: container.height, alignment: .topLeading)
            .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: model.isShown)
            .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: model.isCollapsed)
            .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: showsLoupe)
        }
        // The panel places itself against the keyboard; it must not be
        // pushed up by the keyboard's safe area as well.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Build 30 bug 1 (P1): a second reading of the keyboard, from
        // UIKit's keyboard layout guide in a full-window view, merged with
        // the notifications' (`TypePanelModel.keyboardGuideChanged`), so a
        // keyboard the notifications lost (iPad portrait, when Live's
        // field took focus) still keeps the panel above it.
        .background {
            KeyboardGuideReader { reading, inset in
                model.keyboardGuideChanged(reading, bottomInset: inset)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // Build 25 bug 1: a keyboard frame reported mid-rotation is read
        // again against the turned window, so the free room ends above the
        // keyboard in the new orientation and the panel (and its close
        // button) stays in view.
        .onChange(of: windowSize) { _, _ in
            // A drag or resize in flight belongs to the old window.
            liveFrame = nil
            gestureStart = nil
            DispatchQueue.main.async { model.refreshKeyboard() }
            // Build 28 bug 6: once the rotation has settled, read the
            // keyboard again (its Did notification can be the only one
            // with the new frame, and can come late).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.refreshKeyboard() }
        }
        // Closing the panel closes the loupe (and stops the Mac following
        // the focus).
        .onChange(of: model.isShown) { _, shown in
            if !shown { showsLoupe = false }
        }
        .onChange(of: storageKey, initial: true) { _, key in
            guard loadedKey != key else { return }
            loadedKey = key
            placement = TypePanelPlacement.restored(UserDefaults.standard.data(forKey: key)) ?? .initial
        }
    }

    /// The layout for a width and a wanted height in this window.
    private func panelLayout(width: Double, height: Double?, room: Double?) -> TypePanelLayout {
        TypePanelLayout(
            width: Double(windowSize.width),
            height: Double(windowSize.height),
            keyboard: model.keyboard,
            keyboardOverlap: model.keyboardOverlap,
            panelWidth: width,
            panelHeight: height,
            roomHeight: room,
            showsNumpad: model.presence.tab == .numpad,
            mode: model.presence.mode
        )
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

    /// The bottom corners resize in both directions (OT-6, OT-11): sideways
    /// the other edge holds, down and up the top holds. The 44 pt
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
                        liveFrame = geometry.resized(
                            start, edge: edge,
                            translation: Double(value.translation.width), Double(value.translation.height),
                            heights: heights
                        )
                    }
                    .onEnded { value in
                        let start = gestureStart ?? frame
                        let end = geometry.resized(
                            start, edge: edge,
                            translation: Double(value.translation.width), Double(value.translation.height),
                            heights: heights
                        )
                        settle(geometry.placement(resizedTo: end, keeping: placement, keepsHeight: true))
                    }
            )
            .hoverEffect(.highlight)
            .accessibilityElement()
            .accessibilityLabel(edge == .leading ? "Resize from the left corner" : "Resize from the right corner")
            .accessibilityValue("\(Int(frame.width)) by \(Int(frame.height)) points")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 40.0 : -40.0
                var next = placement
                next.width = geometry.clampWidth(frame.width + step)
                // Taller with wider, within the new width's range.
                let range = heights(next.width ?? frame.width)
                next.height = min(range.upperBound, max(range.lowerBound, frame.height + step / 2))
                settle(next)
            }
            .accessibilityIdentifier("ph.type.resize.\(edge.rawValue)")
    }

    /// The heights the panel may take at a width (the layout's range).
    private func heights(_ width: Double) -> ClosedRange<Double> {
        panelLayout(width: width, height: nil, room: nil).heightRange
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
