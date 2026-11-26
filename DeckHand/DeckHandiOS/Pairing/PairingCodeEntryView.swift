//
//  PairingCodeEntryView.swift
//  DeckHandiOS
//
//  Pair with the code the Mac shows (S4): type the eight digits or scan the
//  QR code. One format everywhere (VQ-005, VQ-029): two groups of four,
//  grouped as you type and drawn in dot-matrix numerals. The field is
//  focused when the sheet opens (VQ-031) and the code goes out by itself
//  once all eight digits pass the check digit, so the number pad never has
//  to be dismissed to reach a button (VQ-030). The check digit is verified
//  as you type, so a typo is caught here and never costs one of the Mac's
//  five tries.
//
//  Sent through the live session (`PairedMacsStore.submit`). Without one
//  (opened from the picker, or the Mac dropped or refused the request) the
//  code is held and this device connects to the Mac first; the session
//  sends it once the Mac answers (`PairedMacsStore.pendingCode`, VQ-003,
//  VQ-037). The Mac's answer comes back as `pairing.codeResult`.
//

import SwiftUI
import UIKit

struct PairingCodeEntryView: View {
    /// A Mac this sheet can pair with.
    struct Target: Identifiable, Hashable {
        var id: UUID
        var name: String
    }

    let macName: String
    /// The Mac's Loom device ID, when known: lets the sheet reconnect to it
    /// if there is no live session.
    var macDeviceID: UUID?
    /// Opened from the picker: the Macs in reach a code could be for. With
    /// more than one, a labelled "Pair with" row names the Mac and the
    /// person must choose unless Core finds a default (VQ-100).
    var choices: [PairingTargetCandidate] = []
    /// The Mac that asked: the one last tapped in the picker (its Allow
    /// prompt is what sends people here).
    var askingDeviceID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var text = ""
    @State private var isScanning = false
    /// The Mac picked on the "Pair with" row.
    @State private var chosenID: UUID?
    /// The last complete code sent automatically, so the same digits
    /// aren't sent twice after a wrong answer.
    @State private var autoSubmitted: String?
    /// Bumped once the number pad has settled, to scroll the footer above
    /// it (VQ-100).
    @State private var footerScrollTick = 0
    @FocusState private var isFieldFocused: Bool
    private let store = PairedMacsStore.shared

    private static let footerID = "ph.pairing.footerAnchor"

    private var parse: PairingCode.ParseResult { PairingCode.parse(text) }

    private var validCode: PairingCode? {
        if case let .valid(code) = parse { return code }
        return nil
    }

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// The Mac the code goes to. From the picker it is never the first in
    /// the list by default: Core picks the Mac that asked, the only Mac,
    /// or the only paired or recently used Mac, or nothing (VQ-100).
    private var target: Target? {
        if !choices.isEmpty {
            if let chosenID, let chosen = choices.first(where: { $0.deviceID == chosenID }) {
                return Target(id: chosen.deviceID, name: chosen.name)
            }
            let asking = askingDeviceID ?? macDeviceID ?? store.liveMac?.deviceID
            guard let id = PairingTargetChoice.defaultTarget(among: choices, askingDeviceID: asking, now: Date()),
                  let match = choices.first(where: { $0.deviceID == id }) else { return nil }
            return Target(id: match.deviceID, name: match.name)
        }
        if let macDeviceID { return Target(id: macDeviceID, name: macName) }
        if let live = store.liveMac { return Target(id: live.deviceID, name: macName) }
        if let last = store.lastMacDeviceID { return Target(id: last, name: macName) }
        return nil
    }

    /// The target's name; `nil` while the person still has to choose.
    private var chosenName: String? {
        if let target { return target.name }
        return choices.isEmpty ? macName : nil
    }

    private var targetName: String { chosenName ?? "your Mac" }

    private var showsChooser: Bool { PairingTargetChoice.showsChooser(among: choices) }

    /// A live session with the target Mac: the code goes out now.
    private var isConnected: Bool {
        guard let target else { return false }
        return store.canSendNow(to: target.id)
    }

    private var isKeypadUp: Bool { isFieldFocused }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                sheetScroll(scroller)
            }
            .background(PixelHandTheme.brandBackground().ignoresSafeArea())
            .foregroundStyle(.white)
            .pixelOnNavy()
            // VQ-086: "Pair with Muhammad’s MacBook…" truncated; the Mac's
            // name is in the heading under it.
            .navigationTitle("Pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // VQ-086: no second Pair button on the keyboard's bar; it
                // floated over the footer on iPhone. The one under the
                // field stays above the number pad (VQ-030), and a full
                // code sends itself.
            }
            .defaultFocus($isFieldFocused, true)
            .task {
                // A sheet's field can't take focus until the sheet has
                // settled; asking once on appear was ignored (VQ-031).
                try? await Task.sleep(for: .milliseconds(350))
                isFieldFocused = true
            }
            .onChange(of: store.codeResultCount) {
                if store.lastCodeResult == .accepted {
                    dismiss()
                } else {
                    text = ""
                    autoSubmitted = nil
                    isFieldFocused = true
                }
            }
            .sheet(isPresented: $isScanning) {
                PairingQRScannerSheet { invite in
                    scanned(invite)
                }
            }
        }
    }

    /// The sheet's scrolling column. `scroller` keeps the footer above the
    /// number pad (VQ-100).
    private func sheetScroll(_ scroller: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: CGFloat(PairingSheetLayout.sectionSpacing(isPhone: isPhone, isKeypadUp: isKeypadUp))) {
                // VQ-100: dropped while the number pad is up on iPhone, so
                // the button and the whole footer fit above it.
                if PairingSheetLayout.showsLockTile(isPhone: isPhone, isKeypadUp: isKeypadUp) {
                    GlyphTile(glyph: PixelGlyphs.lock, side: 56, pitch: 4)
                        .padding(.top, PixelHandTheme.Space.lg)
                        .transition(.opacity)
                }

                VStack(spacing: PixelHandTheme.Space.sm) {
                    Text(PairingTargetChoice.heading(targetName: chosenName))
                        .phText(.display)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    DotMatrixText("\(PairingCode.length) DIGITS", pitch: 1.6, label: "\(PairingCode.length) digits")
                        .foregroundStyle(PixelHandTheme.Brand.phosphor)
                }

                if showsChooser {
                    macChooser
                }

                codeField

                // VQ-108: on iPad the number pad floats over the sheet and
                // covered the heading while typing; the line under the
                // field says again where the code comes from.
                if PairingSheetLayout.showsFieldCaption(isPhone: isPhone, isKeypadUp: isKeypadUp) {
                    Text(PairingSheetLayout.fieldCaption(targetName: chosenName))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                        .accessibilityIdentifier("ph.pairing.fieldCaption")
                }

                // Right under the field, so it stays above the number pad
                // on iPhone (VQ-030).
                actions

                Text(footerLine.text)
                    .foregroundStyle(footerLine.color)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(Self.footerID)

                Button {
                    isScanning = true
                } label: {
                    HStack(spacing: PixelHandTheme.Space.sm) {
                        PHGlyph(glyph: PixelGlyphs.region, pitch: CGFloat(PixelPitch.chip), stepsWithType: true)
                        Text("Scan the QR code instead")
                    }
                }
                .buttonStyle(.ph(.secondary, size: .regular, fullWidth: true))
                .accessibilityIdentifier("ph.pairing.scanQR")
            }
            .padding(.horizontal, PixelHandTheme.Space.xl)
            .padding(.bottom, PixelHandTheme.Space.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.never)
        .animation(.easeOut(duration: 0.2), value: isKeypadUp)
        // VQ-100: the footer ran under the number pad after its first line.
        // Keep its last line above the pad when the pad comes up and when
        // the line changes.
        .onChange(of: isKeypadUp) { _, up in
            guard PairingSheetLayout.keepsFooterVisible(isKeypadUp: up, band: typeSize.typeBand) else { return }
            Task {
                // After the keyboard's own animation.
                try? await Task.sleep(for: .milliseconds(400))
                footerScrollTick += 1
            }
        }
        .onChange(of: footerScrollTick) {
            withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(Self.footerID, anchor: .bottom) }
        }
        .onChange(of: footerLine.text) {
            guard PairingSheetLayout.keepsFooterVisible(isKeypadUp: isKeypadUp, band: typeSize.typeBand) else { return }
            withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(Self.footerID, anchor: .bottom) }
        }
    }

    // MARK: - Pieces

    /// The labelled "Pair with" row (VQ-100): names the Mac the code goes
    /// to, or asks for a choice. Was a lone ⌃⌄ defaulting to the first Mac.
    private var macChooser: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
        let needsChoice = target == nil
        let rowLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PixelHandTheme.Space.xs))
            : AnyLayout(HStackLayout(spacing: PixelHandTheme.Space.md))
        return Menu {
            Picker(PairingTargetChoice.rowLabel, selection: Binding<UUID?>(
                get: { target?.id },
                set: { chosenID = $0 }
            )) {
                ForEach(choices) { choice in
                    Text(choice.name).tag(Optional(choice.deviceID))
                }
            }
        } label: {
            rowLayout {
                Text(PairingTargetChoice.rowLabel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: PixelHandTheme.Space.sm)
                }
                HStack(spacing: PixelHandTheme.Space.sm) {
                    Text(PairingTargetChoice.rowValue(targetName: target?.name))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(needsChoice ? PixelHandTheme.warning : .white)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .padding(.vertical, PixelHandTheme.Space.md)
            .frame(maxWidth: .infinity, minHeight: PixelHandTheme.ControlHeight.hit, alignment: .leading)
            .background(shape.fill(PixelHandTheme.Brand.screen))
            .overlay {
                shape.strokeBorder(needsChoice ? PixelHandTheme.warning.opacity(0.8) : PixelHandTheme.Brand.tileStroke, lineWidth: needsChoice ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PairingTargetChoice.rowAccessibilityLabel(targetName: target?.name))
        .accessibilityHint("Chooses the Mac that shows the code")
        .accessibilityIdentifier("ph.pairing.macChooser")
    }

    /// The code in dot-matrix numerals on a navy plate, grouped "4821 0934"
    /// as it is typed; unlit cells stand for the digits still to come. A
    /// dotted phosphor ring while it has focus, mint once the check digit
    /// passes. The text field underneath takes the typing and VoiceOver.
    private var codeField: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
        return ZStack {
            TextField("", text: $text)
                .font(.system(.largeTitle, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFieldFocused)
                // The digits are drawn by the dot-matrix layer above.
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel("Pairing code")
                // Read digit by digit ("4 8 2 1, 0 9 3 4"), not as one number.
                .accessibilityValue(text.map { $0.isNumber ? String($0) : "," }.joined(separator: " "))
                .accessibilityIdentifier("ph.pairing.codeField")
                .onChange(of: text) { _, newValue in
                    let grouped = PairingCode.grouped(newValue)
                    if grouped != newValue {
                        text = grouped
                        return
                    }
                    autoSubmitIfComplete()
                }

            // Two groups of four with a gap; unlit cells stand for the
            // digits still to come.
            HStack(spacing: PixelHandTheme.Space.lg) {
                ForEach(Array(displayGroups.enumerated()), id: \.offset) { _, group in
                    DotMatrixText(group, pitch: 3.2, label: nil, showsUnlit: true, glows: true, stepsWithType: true)
                }
            }
            .foregroundStyle(validCode != nil ? PixelHandTheme.Brand.mint : PixelHandTheme.Brand.phosphor)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .padding(.vertical, PixelHandTheme.Space.lg)
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .frame(maxWidth: .infinity)
        .background(shape.fill(PixelHandTheme.Brand.screen))
        .overlay {
            if validCode != nil {
                shape.strokeBorder(PixelHandTheme.Brand.mint.opacity(0.8), lineWidth: 2)
            } else if isFieldFocused {
                shape.strokeBorder(
                    PixelHandTheme.Brand.phosphor.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5])
                )
            } else {
                shape.strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: 1)
            }
        }
        .contentShape(shape)
        .onTapGesture { isFieldFocused = true }
    }

    /// What's typed so far in groups of four, padded with blanks where
    /// digits are still to come so the plate keeps its width.
    private var displayGroups: [String] {
        let digits = text.filter(\.isNumber)
        let padded = digits + String(repeating: " ", count: max(0, PairingCode.length - digits.count))
        let size = PairingCode.groupSize
        return stride(from: 0, to: PairingCode.length, by: size).map { start in
            String(padded.dropFirst(start).prefix(size))
        }
    }

    @ViewBuilder
    private var actions: some View {
        if store.isAwaitingCodeResult {
            VStack(spacing: PixelHandTheme.Space.sm) {
                DotWave(pitch: 4, label: "Pairing")
                Text(isConnected ? "Pairing…" : "Connecting to \(targetName)…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(minHeight: PixelHandTheme.ControlHeight.primary)
        } else if isConnected {
            Button("Pair") { submit(validCode) }
                .buttonStyle(.ph(.primary, fullWidth: true))
                .disabled(validCode == nil)
                .accessibilityIdentifier("ph.pairing.pair")
        } else {
            // No live session with this Mac (it dropped or refused the
            // request, or this sheet came from the picker): connect, then
            // send the code (VQ-037).
            Button("Connect and pair") { submit(validCode) }
                .buttonStyle(.ph(.primary, fullWidth: true))
                .disabled(validCode == nil || target == nil)
                .accessibilityHint("Connects to \(targetName), then sends the code")
                .accessibilityIdentifier("ph.pairing.reconnect")
        }
    }

    /// The line under the button, as text so the sheet can keep it in view
    /// above the number pad when it changes (VQ-100).
    private var footerLine: (text: String, color: Color) {
        if let notice = store.notice {
            return (notice, PixelHandTheme.danger)
        }
        if let result = store.lastCodeResult, let line = ApprovalStatusCopy.codeResult(result, peerName: targetName) {
            return (line, PixelHandTheme.danger)
        }
        if let hint = ApprovalStatusCopy.codeEntryHint(parse) {
            return (hint, PixelHandTheme.warning)
        }
        if target == nil, showsChooser {
            return (PairingTargetChoice.chooseNotice, PixelHandTheme.warning)
        }
        if !isConnected, target != nil {
            return ("Not connected to \(targetName) now. Pixel Hand connects again and sends the code.", .white.opacity(0.7))
        }
        return ("No code on \(targetName)? Choose “Pair a device” in Pixel Hand’s menu bar there. A paired \(isPhone ? "iPhone" : "iPad") connects without asking.", .white.opacity(0.7))
    }

    // MARK: - Sending

    private func autoSubmitIfComplete() {
        guard let code = validCode, autoSubmitted != code.digits,
              !store.isAwaitingCodeResult, target != nil else { return }
        autoSubmitted = code.digits
        submit(code)
    }

    private func submit(_ code: PairingCode?) {
        guard let code else { return }
        if isConnected {
            Task {
                let sent = await store.submit(code)
                if !sent {
                    // The session ended between the check and the send.
                    holdAndConnect(code)
                }
            }
        } else {
            holdAndConnect(code)
        }
    }

    /// Keeps the code and connects to the Mac; the session sends it.
    private func holdAndConnect(_ code: PairingCode) {
        guard let target else {
            store.notice = PairingTargetChoice.chooseNotice
            return
        }
        store.holdForNextConnection(code, macDeviceID: target.id, macName: target.name)
        MacSwitcher.shared.connectForPairing(target.id)
        dismiss()
    }

    private func scanned(_ invite: PairingInvite) {
        if let mac = store.liveMac {
            guard invite.macDeviceID == mac.deviceID,
                  invite.macIdentityKeyID == mac.identityKeyID else {
                store.notice = "That QR code is from a different Mac. Scan the one \(targetName) shows."
                return
            }
            Task { await store.submit(invite.code) }
        } else {
            // Not connected: the invite carries the Mac and its key.
            store.pendingInvite = invite
            MacSwitcher.shared.connectForPairing(invite.macDeviceID)
            dismiss()
        }
    }
}
