//
//  TransferSheet.swift
//  DeckHandiOS – Transfer
//
//  S2: Send and Inbox in one sheet, opened from the header's Send button
//  (`TransferHeaderButton`). Redrawn in the pixel identity for the owner's
//  build 26 test (OT-9): a compact Send | Inbox switch (selection by colour
//  and fill only, like the Type panel's Live | Compose), equal source chips,
//  one design-system field, compact device cards with live state, and a
//  sheet as tall as what it holds (`SendSheetLayout`).
//
//  Send: pick photos, files, the clipboard, or type text or a link; the
//  picked items sit in a tray. Tap a Mac card, or drag an item (or anything
//  from another app on iPad) onto one, to send. The focused Mac sends at
//  once; another Mac gets it when you switch to it ("Switch to Studio" does
//  that). While it goes, a dot beam runs from this device's glyph to the
//  Mac's, fills with progress, turns mint when the Mac says it saved it,
//  and collapses into a check. Waiting items list below with Cancel.
//  Offline Macs sit small and muted under the cards with "Seen 2 h ago"
//  (`SendTargetPlan`).
//
//  Inbox: what Macs sent, newest first. Links open, text copies, photos
//  save to Photos, anything shares through the share sheet; Files sees
//  the same folder ("On My iPhone › Pixel Hand › Pixel Hand Inbox").
//

import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TransferSheet: View {
    enum Tab: String, CaseIterable { case send = "Send", inbox = "Inbox" }

    @State private var tab: Tab
    /// The Send tab's measured content height; `nil` until laid out.
    @State private var sendContentHeight: CGFloat?
    @State private var sheetWidth: CGFloat = 0
    /// The window's height; read on appear and on rotation.
    @State private var containerHeight: CGFloat = 800
    @Environment(\.dismiss) private var dismiss
    private let center = TransferCenter.shared
    private let switcher = MacSwitcher.shared

    init(tab: Tab = .send) {
        _tab = State(initialValue: tab)
    }

    private var margin: CGFloat {
        CGFloat(LayoutMetrics(width: Double(sheetWidth), height: Double(containerHeight)).margin)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch tab {
                case .send:
                    SendPanel(margin: margin) { height in
                        if SendSheetLayout.isNewHeight(Double(height), comparedWith: sendContentHeight.map(Double.init)) {
                            sendContentHeight = height
                        }
                    }
                case .inbox:
                    InboxPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(PixelHandTheme.canvas)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            sheetWidth = width
        }
        .modifier(TransferSheetSizing(
            height: CGFloat(SendSheetLayout.sheetHeight(content: Double(contentHeight), container: Double(containerHeight))),
            allowsLarge: SendSheetLayout.overflows(content: Double(contentHeight), container: Double(containerHeight))
        ))
        .onAppear {
            center.refresh()
            containerHeight = Self.windowHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            containerHeight = Self.windowHeight()
        }
        .transferPromptAlert()
        .transferNoticeAlert()
    }

    // MARK: Header

    /// Switch · Done, 44 pt with 8 above and below (`SendSheetLayout
    /// .headerHeight`). The switch names the tab; no navigation title.
    private var header: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            SendInboxSwitch(tab: $tab, unseen: center.inbox.unseenCount)
            Spacer(minLength: PixelHandTheme.Space.sm)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.accent)
                    .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
            .accessibilityIdentifier("ph.send.done")
        }
        .frame(minHeight: PixelHandTheme.ControlHeight.standard)
        .padding(.horizontal, margin)
        .padding(.vertical, PixelHandTheme.Space.sm)
    }

    // MARK: Sizing

    /// The open tab's content height: measured for Send once laid out,
    /// otherwise estimated from what's in it.
    private var contentHeight: CGFloat {
        let width = Double(max(0, sheetWidth - 2 * margin))
        switch tab {
        case .send:
            if let sendContentHeight { return sendContentHeight }
            let (cards, offline) = SendTargetPlan.targets(listings: switcher.listings, outgoing: [])
            return CGFloat(SendSheetLayout.estimatedSendHeight(
                .init(cardCount: cards.count, offlineCount: offline.count, waitingCount: center.outbox.items.count),
                width: width
            ))
        case .inbox:
            let arriving = center.activities.values.filter { $0.direction == .incoming && $0.isActive }.count
            return CGFloat(SendSheetLayout.estimatedInboxHeight(arriving: arriving, items: center.inbox.items.count))
        }
    }

    /// The window the sheet sits in (Stage Manager and Split View aware).
    static func windowHeight() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return window?.bounds.height ?? 800
    }
}

/// Sizes the sheet to its content: a height detent from `SendSheetLayout`
/// (plus Large when the content is taller than the window allows), and
/// on iPad (iOS 18) a form sheet fitted to that height instead of the
/// fixed-size form sheet. Sheet radius 36 (`07-Polish-Spec.md` §3).
private struct TransferSheetSizing: ViewModifier {
    let height: CGFloat
    let allowsLarge: Bool
    @State private var selection: PresentationDetent

    init(height: CGFloat, allowsLarge: Bool) {
        self.height = height
        self.allowsLarge = allowsLarge
        _selection = State(initialValue: .height(height))
    }

    func body(content: Content) -> some View {
        let detent = PresentationDetent.height(height)
        let detents: Set<PresentationDetent> = allowsLarge ? [detent, .large] : [detent]
        sized(content)
            .presentationDetents(detents, selection: $selection)
            .presentationCornerRadius(PixelHandTheme.Radius.sheet)
            .presentationBackground(PixelHandTheme.canvas)
            .onChange(of: height) { _, newHeight in
                // Follow the content unless the person pulled it to Large.
                if selection != .large { selection = .height(newHeight) }
            }
            .onChange(of: allowsLarge) { _, allows in
                if !allows, selection == .large { selection = detent }
            }
    }

    @ViewBuilder
    private func sized(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                content
                    .frame(idealHeight: height)
                    .presentationSizing(.form.fitted(horizontal: false, vertical: true))
            } else {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Switch

/// Send | Inbox: a 36 pt capsule, the selected side accent with white
/// text, the other ink2 on nothing (selection by colour and fill only,
/// `06-Pixel-Identity.md` §5; the Type panel's Live | Compose). Unseen
/// Inbox items are a dot-matrix count.
private struct SendInboxSwitch: View {
    @Binding var tab: TransferSheet.Tab
    let unseen: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TransferSheet.Tab.allCases, id: \.self) { item in
                let isOn = tab == item
                Button {
                    guard tab != item else { return }
                    GestureHaptic.selection.trigger()
                    tab = item
                } label: {
                    HStack(spacing: 6) {
                        Text(item.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if item == .inbox, unseen > 0 {
                            DotMatrixText("\(min(unseen, 99))", pitch: 1.4, label: "\(unseen) new", stepsWithType: false)
                        }
                    }
                    .foregroundStyle(isOn ? Color.white : PixelHandTheme.ink2)
                    .padding(.horizontal, PixelHandTheme.Space.md)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(isOn ? PixelHandTheme.accent : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .phosphorFocusable(cornerRadius: 16)
                .accessibilityLabel(item == .inbox && unseen > 0 ? "Inbox, \(unseen) new" : item.rawValue)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("ph.send.tab.\(item.rawValue.lowercased())")
            }
        }
        .padding(2)
        .background(PixelHandTheme.fill, in: Capsule())
        .frame(minHeight: PixelHandTheme.ControlHeight.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.transfer.tab")
    }
}

// MARK: - Send

/// Something picked but not sent yet.
struct StagedTransferItem: Identifiable, Equatable {
    enum Payload: Equatable {
        /// A private copy in the temporary folder; moved into the outbox on send.
        case file(url: URL, kind: TransferKind, contentType: String?)
        case text(String)
    }

    let id = UUID()
    let payload: Payload

    var title: String {
        switch payload {
        case let .file(url, _, _): url.lastPathComponent
        case let .text(text): TransferInlineText.title(for: text, limit: 40)
        }
    }

    var subtitle: String {
        switch payload {
        case let .file(url, kind, _):
            let size = TransferCenter.fileSize(url).map(TransferProgressMeter.size) ?? ""
            return kind == .photo ? "Photo · \(size)" : size
        case let .text(text):
            return TransferInlineText.webLink(text) != nil ? "Link" : "Text"
        }
    }

    var glyph: GlyphBitmap {
        switch payload {
        case let .file(_, kind, _): kind == .photo ? TransferGlyphs.photos : TransferGlyphs.files
        case let .text(text): TransferInlineText.webLink(text) != nil ? TransferGlyphs.link : PixelGlyphs.type
        }
    }
}

private struct SendPanel: View {
    /// The sheet's class margin (16 · 20 · 24).
    let margin: CGFloat
    /// Reports the content's height, for the sheet's detent.
    let onContentHeight: (CGFloat) -> Void

    @State private var staged: [StagedTransferItem] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsFileImporter = false
    @State private var typedText = ""
    /// The items of the last send, for the beam.
    @State private var lastSent: [UUID] = []
    @State private var lastTarget: MacListing?
    @State private var loadingPhotos = false
    /// A passing line under the field ("The clipboard is empty.").
    @State private var fieldNote: String?
    @State private var contentWidth: CGFloat = 0

    private let center = TransferCenter.shared
    private let switcher = MacSwitcher.shared

    init(margin: CGFloat, onContentHeight: @escaping (CGFloat) -> Void) {
        self.margin = margin
        self.onContentHeight = onContentHeight
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.lg) {
                sources
                field
                if !staged.isEmpty { tray }
                targets
                if !lastSent.isEmpty, let lastTarget { beam(to: lastTarget) }
                waitingList
            }
            .padding(.horizontal, margin)
            .padding(.bottom, PixelHandTheme.Space.lg)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                contentWidth = max(0, size.width - 2 * margin)
                onContentHeight(size.height)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            for url in urls { stageFile(url) }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            loadPhotos(items)
        }
    }

    // MARK: Picking

    /// Photos · Files · Clipboard: three chips of one size, glyph + label.
    private var sources: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                SendSourceChipLabel(glyph: TransferGlyphs.photos, title: "Photos")
            }
            .buttonStyle(ChipPressStyle())
            .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
            .accessibilityLabel("Photos")
            .accessibilityIdentifier("ph.send.source.photos")

            Button { showsFileImporter = true } label: {
                SendSourceChipLabel(glyph: TransferGlyphs.files, title: "Files")
            }
            .buttonStyle(ChipPressStyle())
            .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
            .accessibilityLabel("Files")
            .accessibilityIdentifier("ph.send.source.files")

            Button(action: stageClipboard) {
                SendSourceChipLabel(glyph: PixelGlyphs.paste, title: "Clipboard")
            }
            .buttonStyle(ChipPressStyle())
            .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
            .accessibilityLabel("Paste text or a link")
            .accessibilityIdentifier("ph.send.source.clipboard")
        }
    }

    /// One field for text or a link, with its Add button inside: the Ask
    /// field's shape (raised, radius 24, hairline, 52 pt).
    private var field: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                TextField("Type text or a link", text: $typedText, axis: .vertical)
                    .lineLimit(1...4)
                    .submitLabel(.done)
                    .font(.body)
                    .foregroundStyle(PixelHandTheme.ink)
                    .accessibilityIdentifier("ph.send.field")
                Button(action: addTyped) {
                    PHGlyph(glyph: PixelGlyphs.add, pitch: PixelPitch.chip, accent: .white)
                        .foregroundStyle(Color.white)
                        .frame(width: PixelHandTheme.ControlHeight.secondary, height: PixelHandTheme.ControlHeight.secondary)
                        .background(canAdd ? PixelHandTheme.accent : PixelHandTheme.ink3, in: Circle())
                        .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                        .contentShape(Circle())
                }
                .buttonStyle(ChipPressStyle())
                .disabled(!canAdd)
                .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.hit / 2)
                .accessibilityLabel("Add")
                .accessibilityHint("Adds the text or link to send.")
                .accessibilityIdentifier("ph.send.add")
            }
            .padding(.leading, PixelHandTheme.Space.lg)
            .padding(.trailing, PixelHandTheme.Space.xs)
            .frame(minHeight: PixelHandTheme.ControlHeight.primary)
            .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                    .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
            )
            if loadingPhotos {
                DotBeam(state: .progress(0.3)).accessibilityLabel("Getting photos")
            }
            if let fieldNote {
                Text(fieldNote)
                    .font(.footnote)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .transition(.opacity)
            }
        }
    }

    private var canAdd: Bool {
        !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            SendSectionLabel("To send · tap a Mac below, or drag an item onto it")
            ForEach(staged) { item in
                HStack(spacing: PixelHandTheme.Space.md) {
                    PHGlyph(glyph: item.glyph, pitch: PixelPitch.chip)
                        .foregroundStyle(PixelHandTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text(item.subtitle).font(.caption).foregroundStyle(PixelHandTheme.ink2)
                    }
                    Spacer(minLength: PixelHandTheme.Space.sm)
                    Button {
                        unstage(item)
                    } label: {
                        PHGlyph(glyph: PixelGlyphs.close, pitch: 1.6)
                            .foregroundStyle(PixelHandTheme.ink3)
                            .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ChipPressStyle())
                    .accessibilityLabel("Remove \(item.title)")
                }
                .padding(.leading, PixelHandTheme.Space.md)
                .frame(minHeight: CGFloat(SendSheetLayout.trayRowHeight))
                .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                        .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
                )
                .draggable(StagedItemReference(id: item.id.uuidString))
                .accessibilityIdentifier("ph.send.trayItem")
            }
        }
    }

    // MARK: Macs

    private var targetPlan: (cards: [SendTarget], offline: [SendTarget]) {
        let outgoing = center.outbox.items.map { item in
            let meter = center.activities[item.id]?.meter
            return SendTargetPlan.Outgoing(
                targetDeviceID: item.targetDeviceID,
                isMoving: item.state == .sending,
                bytes: meter?.bytes ?? 0,
                totalBytes: meter?.totalBytes ?? item.byteCount
            )
        }
        let incoming = center.activities.values.filter { $0.direction == .incoming && $0.isActive }.count
        return SendTargetPlan.targets(listings: switcher.listings, outgoing: outgoing, incomingCount: incoming)
    }

    /// "Send to": the device cards in a grid of equal columns, then the
    /// offline Macs small and muted in the same columns.
    private var targets: some View {
        let plan = targetPlan
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: CGFloat(SendSheetLayout.cardGap), alignment: .top),
            count: SendSheetLayout.columns(width: Double(contentWidth))
        )
        return VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            SendSectionLabel("Send to")
            if plan.cards.isEmpty && plan.offline.isEmpty {
                Text("Pair a Mac to send to it.")
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.ink2)
            } else {
                // The "seen … ago" lines move on by themselves.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: CGFloat(SendSheetLayout.cardGap)) {
                        if !plan.cards.isEmpty {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: CGFloat(SendSheetLayout.cardGap)) {
                                ForEach(plan.cards) { target in
                                    dropTarget(target, now: context.date)
                                }
                            }
                        }
                        if !plan.offline.isEmpty {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: CGFloat(SendSheetLayout.rowGap)) {
                                ForEach(plan.offline) { target in
                                    dropTarget(target, now: context.date)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func dropTarget(_ target: SendTarget, now: Date) -> some View {
        SendTargetButton(target: target, now: now, canSend: !staged.isEmpty) {
            send(staged, to: target.listing)
        } onDropStaged: { ids in
            send(staged.filter { ids.contains($0.id.uuidString) }, to: target.listing)
        } onDropExternal: { items in
            send(items, to: target.listing)
        }
    }

    private func beam(to listing: MacListing) -> some View {
        let activities = lastSent.compactMap { center.activities[$0] }
        let fraction = activities.isEmpty ? 0 : activities.map(\.meter.fraction).reduce(0, +) / Double(activities.count)
        let isSaved: (TransferCenter.Activity) -> Bool = { if case .saved? = $0.status { true } else { false } }
        let phase: TransferBeamPhase
        if !activities.isEmpty, activities.allSatisfy(isSaved) {
            phase = .delivered
        } else if activities.contains(where: { !isSaved($0) && $0.status?.isFinal == true }) {
            phase = .stopped
        } else {
            phase = TransferBeamPhase.phase(status: activities.first?.status, fraction: activities.contains(where: \.isActive) ? fraction : nil)
        }
        let caption = activities.count == 1 ? activities[0].caption : (phase == .delivered ? "Delivered to \(listing.name)" : TransferCopy.sending(to: listing.name))
        return TransferBeamRow(phase: phase, macName: listing.name, caption: caption, onCancel: phase == .delivered || phase == .stopped ? nil : {
            for id in lastSent { center.cancel(id) }
        }, onSwitch: listing.isActive ? nil : { switcher.request(listing.deviceID) })
    }

    private var waitingList: some View {
        let waiting = center.outbox.items
        return Group {
            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    SendSectionLabel("Waiting")
                    ForEach(waiting) { item in
                        HStack(spacing: PixelHandTheme.Space.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fileName).font(.subheadline).lineLimit(1).truncationMode(.middle)
                                Text(center.activities[item.id]?.caption ?? TransferCopy.waiting(for: item.targetName))
                                    .font(.caption).foregroundStyle(PixelHandTheme.ink2)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: PixelHandTheme.Space.sm)
                            Button("Cancel", role: .destructive) { center.cancel(item.id) }
                                .buttonStyle(.ph(.destructive, size: .small))
                                .accessibilityIdentifier("ph.send.waiting.cancel")
                        }
                        .frame(minHeight: CGFloat(SendSheetLayout.waitingRowHeight))
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func send(_ items: [StagedTransferItem], to listing: MacListing) {
        guard !items.isEmpty else { return }
        var ids: [UUID] = []
        for item in items {
            switch item.payload {
            case let .file(url, kind, type):
                if let id = center.send(fileAt: url, kind: kind, contentType: type, to: listing.deviceID, macName: listing.name, moveFile: true) { ids.append(id) }
            case let .text(text):
                if let id = center.send(text: text, to: listing.deviceID, macName: listing.name) { ids.append(id) }
            }
        }
        staged.removeAll { item in items.contains(item) }
        lastSent = ids
        lastTarget = listing
        GestureHaptic.selection.trigger()
    }

    private func addTyped() {
        stageText(typedText)
        typedText = ""
    }

    /// The Clipboard chip: a link first, then text. Reading the pasteboard
    /// is the person's own tap, so iOS may ask once to allow pasting.
    private func stageClipboard() {
        let board = UIPasteboard.general
        guard board.hasURLs || board.hasStrings else {
            showFieldNote("The clipboard has no text or link.")
            return
        }
        if let url = board.url, !url.isFileURL {
            stageText(url.absoluteString)
        } else if let text = board.string {
            stageText(text)
        } else {
            showFieldNote("The clipboard has no text or link.")
        }
    }

    private func showFieldNote(_ note: String) {
        withAnimation(.easeOut(duration: 0.18)) { fieldNote = note }
        AccessibilityNotification.Announcement(note).post()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.18)) { if fieldNote == note { fieldNote = nil } }
        }
    }

    private func stageText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fieldNote = nil
        staged.append(StagedTransferItem(payload: .text(trimmed)))
    }

    private func stageFile(_ url: URL) {
        if let copy = Self.privateCopy(of: url) {
            let type = UTType(filenameExtension: copy.pathExtension)
            let kind: TransferKind = (type?.conforms(to: .image) == true || type?.conforms(to: .movie) == true) ? .photo : .file
            staged.append(StagedTransferItem(payload: .file(url: copy, kind: kind, contentType: type?.identifier)))
        }
    }

    private func unstage(_ item: StagedTransferItem) {
        if case let .file(url, _, _) = item.payload { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        staged.removeAll { $0 == item }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        loadingPhotos = true
        Task {
            for item in items {
                if let picked = try? await item.loadTransferable(type: PickedPhotoFile.self) {
                    staged.append(StagedTransferItem(payload: .file(url: picked.url, kind: .photo, contentType: picked.contentType)))
                }
            }
            photoSelection = []
            loadingPhotos = false
        }
    }

    /// Copies a picked or dropped file into its own temporary folder (the
    /// original may be security-scoped or vanish when the picker closes).
    static func privateCopy(of url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString)", isDirectory: true)
        let destination = folder.appendingPathComponent(TransferFileName.sanitized(url.lastPathComponent, kind: .file))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

// MARK: - Pieces

/// A section label: footnote semibold, ink2, 20 pt.
private struct SendSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PixelHandTheme.ink2)
            .lineLimit(2)
            .frame(minHeight: CGFloat(SendSheetLayout.labelHeight), alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A source chip's face: glyph + label, 44 pt, the full third of the row,
/// raised with a hairline (the context chip's look, `ContextChip`).
private struct SendSourceChipLabel: View {
    let glyph: GlyphBitmap
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            PHGlyph(glyph: glyph, pitch: PixelPitch.chip)
                .foregroundStyle(PixelHandTheme.accent)
            Text(title)
                .font(.phChip)
                .foregroundStyle(PixelHandTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, PixelHandTheme.Space.sm)
        .frame(maxWidth: .infinity, minHeight: CGFloat(SendSheetLayout.chipHeight))
        .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
    }
}

/// A tray item dragged onto a Mac card: its id as text with a prefix, so
/// no custom type has to be declared in Info.plist.
struct StagedItemReference: Transferable {
    static let prefix = "pixelhand-staged-item:"
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { prefix + $0.id })
    }

    /// The id in dropped text, when it is a tray item.
    static func id(in text: String) -> String? {
        text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : nil
    }
}

/// A photo or video from the picker, copied to a temporary file.
struct PickedPhotoFile: Transferable {
    let url: URL
    let contentType: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try Self(copying: received.file, type: .image)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try Self(copying: received.file, type: .movie)
        }
    }

    init(url: URL, contentType: String?) {
        self.url = url
        self.contentType = contentType
    }

    init(copying file: URL, type: UTType) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(TransferFileName.sanitized(file.lastPathComponent, kind: .photo))
        try FileManager.default.copyItem(at: file, to: destination)
        self.init(url: destination, contentType: UTType(filenameExtension: destination.pathExtension)?.identifier ?? type.identifier)
    }
}

/// A send target that sends on tap and takes drops: tray items, or files,
/// photos, links and text from other apps (iPad drag and drop). A Mac
/// that can take a send is a compact device card; an offline one is a
/// small muted row (`SendTargetState.isCompact`). Either one queues a send
/// for its Mac, as before.
private struct SendTargetButton: View {
    let target: SendTarget
    let now: Date
    let canSend: Bool
    let onTap: () -> Void
    let onDropStaged: ([String]) -> Void
    let onDropExternal: ([StagedTransferItem]) -> Void
    @State private var isTargeted = false

    init(target: SendTarget, now: Date, canSend: Bool, onTap: @escaping () -> Void, onDropStaged: @escaping ([String]) -> Void, onDropExternal: @escaping ([StagedTransferItem]) -> Void) {
        self.target = target
        self.now = now
        self.canSend = canSend
        self.onTap = onTap
        self.onDropStaged = onDropStaged
        self.onDropExternal = onDropExternal
    }

    private var radius: CGFloat {
        target.state.isCompact ? PixelHandTheme.Radius.chip : PixelHandTheme.Radius.card
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if target.state.isCompact {
                    SendOfflineRow(target: target, now: now)
                } else {
                    SendTargetCard(target: target, now: now)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(PixelHandTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .opacity(isTargeted ? 1 : 0)
            }
        }
        .buttonStyle(ChipPressStyle())
        .disabled(!canSend && !isTargeted)
        .accessibilityLabel("Send to \(target.listing.name)")
        .accessibilityValue(target.spoken(now: now))
        .accessibilityHint(canSend ? "" : "Pick something to send first.")
        .accessibilityIdentifier(target.state.isCompact ? "ph.send.offlineCard" : "ph.transfer.macCard")
        .phosphorFocusable(cornerRadius: radius)
        .onDrop(of: [.fileURL, .image, .movie, .url, .plainText], isTargeted: $isTargeted) { providers in
            receive(providers)
            return true
        }
    }

    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in onDropExternal([StagedTransferItem(payload: .text(url.absoluteString))]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String else { return }
                    Task { @MainActor in
                        if let id = StagedItemReference.id(in: text) {
                            onDropStaged([id]) // a tray item
                        } else {
                            onDropExternal([StagedTransferItem(payload: .text(text))])
                        }
                    }
                }
            } else {
                let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) || $0.conforms(to: .movie) }) ?? .item
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                    guard let url, let copy = SendPanelFiles.copy(url) else { return }
                    let fileType = UTType(filenameExtension: copy.pathExtension)
                    let kind: TransferKind = (fileType?.conforms(to: .image) == true || fileType?.conforms(to: .movie) == true) ? .photo : .file
                    Task { @MainActor in onDropExternal([StagedTransferItem(payload: .file(url: copy, kind: kind, contentType: fileType?.identifier))]) }
                }
            }
        }
    }
}

/// A compact device card, 64 pt: a 44 pt navy tile with the Mac glyph
/// (lit while the Mac is talking; the lock while locked; the dot wave
/// while connecting), the name over one status line, and at the trailing
/// edge the dot-matrix readout (`42%`, a waiting count) or the status
/// light. The focused Mac gets the 2 pt cobalt ring. Card radius 24 with
/// a 10 pt inset → tile radius 14 (`07-Polish-Spec.md` §3).
private struct SendTargetCard: View {
    let target: SendTarget
    let now: Date

    private var listing: MacListing { target.listing }

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(target.statusLine(now: now))
                    .font(.caption)
                    .foregroundStyle(target.state.light == .needsYou ? PixelHandTheme.warning : PixelHandTheme.ink2)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: CGFloat(SendSheetLayout.cardHeight), alignment: .leading)
        .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .strokeBorder(
                    listing.isActive ? PixelHandTheme.accent : PixelHandTheme.hairline,
                    lineWidth: listing.isActive ? PixelHandTheme.Stroke.selection : PixelHandTheme.Stroke.hairline
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: target.state)
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
            .fill(PixelHandTheme.Brand.screenSurface)
            .frame(width: PixelHandTheme.ControlHeight.standard, height: PixelHandTheme.ControlHeight.standard)
            .overlay {
                if target.state == .connecting {
                    DotWave(pitch: 2, label: "Connecting to \(listing.name)")
                } else {
                    PHGlyph(
                        glyph: target.state == .busy(.locked) ? PixelGlyphs.lock : PixelGlyphs.mac,
                        pitch: PixelPitch.chip,
                        accent: PixelHandTheme.Brand.glow
                    )
                    .foregroundStyle(target.state.light == .off ? PixelHandTheme.Brand.dotOff : PixelHandTheme.Brand.phosphor)
                }
            }
            .pixelOnNavy()
            .freeMacBadge(deviceID: listing.deviceID) // Store lane: PRO on a Mac the free plan doesn't cover
    }

    @ViewBuilder
    private var trailing: some View {
        if let readout = target.readout {
            DotMatrixText(readout, pitch: 1.6, label: target.spoken(now: now))
                .foregroundStyle(PixelHandTheme.accent)
                .accessibilityHidden(true)
        } else {
            switch target.state.light {
            case .live: LivePixel(color: PixelHandTheme.success, size: 8)
            case .needsYou: StatusPixel(state: .needsYou, size: 8)
            case .off: StatusPixel(state: .off, size: 8)
            }
        }
    }
}

/// An offline Mac: one 44 pt row, small and muted. The Mac glyph unlit,
/// the name, "Seen 2 h ago". A send to it waits for it in the outbox.
private struct SendOfflineRow: View {
    let target: SendTarget
    let now: Date

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            PHGlyph(glyph: PixelGlyphs.mac, pitch: 1.6)
                .foregroundStyle(PixelHandTheme.ink3)
            Text(target.listing.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PixelHandTheme.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: PixelHandTheme.Space.xs)
            Text(target.statusLine(now: now))
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, minHeight: CGFloat(SendSheetLayout.offlineHeight), alignment: .leading)
        .background(PixelHandTheme.fill, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
    }
}

/// File copies made off the main actor (drop callbacks run on a
/// background queue and the dropped file is deleted when they return).
enum SendPanelFiles {
    nonisolated static func copy(_ url: URL) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString)", isDirectory: true)
        let destination = folder.appendingPathComponent(TransferFileName.sanitized(url.lastPathComponent, kind: .file))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

/// This device's glyph, the dot beam, the Mac's glyph, a caption.
struct TransferBeamRow: View {
    let phase: TransferBeamPhase
    let macName: String
    let caption: String
    var onCancel: (() -> Void)?
    var onSwitch: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(phase: TransferBeamPhase, macName: String, caption: String, onCancel: (() -> Void)? = nil, onSwitch: (() -> Void)? = nil) {
        self.phase = phase
        self.macName = macName
        self.caption = caption
        self.onCancel = onCancel
        self.onSwitch = onSwitch
    }

    var body: some View {
        VStack(spacing: PixelHandTheme.Space.md) {
            HStack(spacing: PixelHandTheme.Space.md) {
                PHGlyph(glyph: PixelGlyphs.iPhone, pitch: 2.6)
                    .foregroundStyle(PixelHandTheme.Brand.phosphor)
                ZStack {
                    DotBeam(state: beamState, count: 12)
                        .opacity(phase == .delivered && !reduceMotion ? 0 : 1)
                    if phase == .delivered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(PixelHandTheme.Brand.mint)
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    } else if phase == .stopped {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(PixelHandTheme.danger)
                    }
                }
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : PixelHandMotion.spring, value: phase)
                PHGlyph(glyph: PixelGlyphs.mac, pitch: 2.6)
                    .foregroundStyle(phase == .delivered ? PixelHandTheme.Brand.mint : PixelHandTheme.Brand.phosphor)
            }
            .padding(PixelHandTheme.Space.lg)
            .frame(maxWidth: .infinity)
            .background(PixelHandTheme.Brand.screenSurface, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
            .pixelOnNavy()
            Text(caption)
                .font(.footnote)
                .foregroundStyle(PixelHandTheme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if onSwitch != nil || onCancel != nil {
                HStack(spacing: PixelHandTheme.Space.sm) {
                    if let onSwitch {
                        Button("Switch to \(macName)", action: onSwitch)
                            .buttonStyle(.ph(.secondary, size: .small))
                    }
                    if let onCancel {
                        Button("Cancel", role: .destructive, action: onCancel)
                            .buttonStyle(.ph(.destructive, size: .small))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sending to \(macName)")
        .accessibilityValue(caption)
        .accessibilityIdentifier("ph.send.beam")
        .onChange(of: phase) { _, newPhase in
            // The receipt is announced, not only drawn.
            if newPhase == .delivered || newPhase == .stopped { AccessibilityNotification.Announcement(caption).post() }
        }
    }

    private var beamState: DotBeam.Phase {
        switch phase {
        case .idle: .progress(0)
        case .asking: .progress(1.0 / 12.0)
        case let .sending(fraction): .progress(fraction)
        case .delivered: .success
        case .stopped: .failure
        }
    }
}
