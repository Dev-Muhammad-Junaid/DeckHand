//
//  TransferSheet.swift
//  DeckHandiOS – Transfer
//
//  S2: Send and Inbox in one sheet, opened from the header's Send button
//  (`TransferHeaderButton`).
//
//  Send: pick photos, files, or type / paste text or a link; the picked
//  items sit in a tray. Tap a Mac card, or drag an item (or anything from
//  another app on iPad) onto one, to send. The focused Mac sends at once;
//  another Mac gets it when you switch to it ("Switch to Studio" does
//  that). While it goes, a dot beam runs from this device's glyph to the
//  Mac's, fills with progress, turns mint when the Mac says it saved it,
//  and collapses into a check. Waiting items list below with Cancel.
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
    @Environment(\.dismiss) private var dismiss
    private let center = TransferCenter.shared

    init(tab: Tab = .send) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab == .inbox && center.inbox.unseenCount > 0 ? "Inbox (\(center.inbox.unseenCount))" : tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ph.transfer.tab")
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .padding(.bottom, PixelHandTheme.Space.sm)
                switch tab {
                case .send: SendPanel()
                case .inbox: InboxPanel()
                }
            }
            .background(PixelHandTheme.canvas)
            .navigationTitle(tab == .send ? "Send" : "Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { center.refresh() }
        .transferPromptAlert()
        .transferNoticeAlert()
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

    var systemImage: String {
        switch payload {
        case let .file(_, kind, _): kind == .photo ? "photo" : "doc"
        case let .text(text): TransferInlineText.webLink(text) != nil ? "link" : "text.alignleft"
        }
    }
}

private struct SendPanel: View {
    @State private var staged: [StagedTransferItem] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsFileImporter = false
    @State private var typedText = ""
    /// The items of the last send, for the beam.
    @State private var lastSent: [UUID] = []
    @State private var lastTarget: MacListing?
    @State private var loadingPhotos = false

    private let center = TransferCenter.shared
    private let switcher = MacSwitcher.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.lg) {
                pickers
                if !staged.isEmpty { tray }
                macRow
                if !lastSent.isEmpty, let lastTarget { beam(to: lastTarget) }
                waitingList
            }
            .padding(PixelHandTheme.Space.lg)
        }
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

    private var pickers: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.ph(.secondary, size: .regular))
                Button { showsFileImporter = true } label: {
                    Label("Files", systemImage: "folder")
                }
                .buttonStyle(.ph(.secondary, size: .regular))
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.joined(separator: "\n")
                    Task { @MainActor in stageText(text) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Paste text or a link")
            }
            HStack {
                TextField("Type text or a link", text: $typedText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                Button("Add") {
                    stageText(typedText)
                    typedText = ""
                }
                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if loadingPhotos {
                DotBeam(state: .progress(0.3)).accessibilityLabel("Getting photos")
            }
        }
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            Text("To send — tap a Mac below, or drag an item onto it")
                .font(.footnote)
                .foregroundStyle(PixelHandTheme.ink2)
            ForEach(staged) { item in
                HStack(spacing: PixelHandTheme.Space.md) {
                    Image(systemName: item.systemImage)
                        .frame(width: 28)
                        .foregroundStyle(PixelHandTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text(item.subtitle).font(.caption).foregroundStyle(PixelHandTheme.ink2)
                    }
                    Spacer()
                    Button {
                        unstage(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(PixelHandTheme.ink3)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Remove \(item.title)")
                }
                .padding(.horizontal, PixelHandTheme.Space.md)
                .background(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous).fill(PixelHandTheme.raised))
                .draggable(StagedItemReference(id: item.id.uuidString))
            }
        }
    }

    // MARK: Macs

    private var macRow: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            Text("Send to")
                .font(.headline)
            let listings = switcher.listings.filter { $0.isPaired || $0.isActive }
            if listings.isEmpty {
                Text("Pair a Mac to send to it.")
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.ink2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PixelHandTheme.Space.md) {
                        ForEach(listings) { listing in
                            MacDropCard(listing: listing, canSend: !staged.isEmpty) {
                                send(staged, to: listing)
                            } onDropStaged: { ids in
                                send(staged.filter { ids.contains($0.id.uuidString) }, to: listing)
                            } onDropExternal: { items in
                                send(items, to: listing)
                            }
                        }
                    }
                    .padding(.vertical, PixelHandTheme.Space.sm)
                }
            }
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
                    Text("Waiting").font(.headline)
                    ForEach(waiting) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fileName).font(.subheadline).lineLimit(1).truncationMode(.middle)
                                Text(center.activities[item.id]?.caption ?? TransferCopy.waiting(for: item.targetName))
                                    .font(.caption).foregroundStyle(PixelHandTheme.ink2)
                            }
                            Spacer()
                            Button("Cancel", role: .destructive) { center.cancel(item.id) }
                                .font(.caption)
                        }
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

    private func stageText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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

/// A Mac card that sends on tap and takes drops: tray items, or files,
/// photos, links and text from other apps (iPad drag and drop).
private struct MacDropCard: View {
    let listing: MacListing
    let canSend: Bool
    let onTap: () -> Void
    let onDropStaged: ([String]) -> Void
    let onDropExternal: ([StagedTransferItem]) -> Void
    @State private var isTargeted = false

    init(listing: MacListing, canSend: Bool, onTap: @escaping () -> Void, onDropStaged: @escaping ([String]) -> Void, onDropExternal: @escaping ([StagedTransferItem]) -> Void) {
        self.listing = listing
        self.canSend = canSend
        self.onTap = onTap
        self.onDropStaged = onDropStaged
        self.onDropExternal = onDropExternal
    }

    var body: some View {
        Button(action: onTap) {
            MacCard(listing: listing)
                .frame(width: 150)
                .overlay {
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                        .strokeBorder(PixelHandTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .opacity(isTargeted ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !isTargeted)
        .accessibilityLabel("Send to \(listing.name)")
        .accessibilityHint(canSend ? "" : "Pick something to send first.")
        .accessibilityIdentifier("ph.transfer.macCard")
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip + 4)
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
                PHGlyph(glyph: PixelGlyphs.iPhone, pitch: 2.4)
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
                PHGlyph(glyph: PixelGlyphs.mac, pitch: 2.4)
                    .foregroundStyle(phase == .delivered ? PixelHandTheme.Brand.mint : PixelHandTheme.Brand.phosphor)
            }
            .padding(PixelHandTheme.Space.lg)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous).fill(PixelHandTheme.Brand.screen))
            Text(caption)
                .font(.footnote)
                .foregroundStyle(PixelHandTheme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack {
                if let onSwitch {
                    Button("Switch to \(macName)", action: onSwitch)
                        .buttonStyle(.ph(.secondary, size: .small))
                }
                if let onCancel {
                    Button("Cancel", role: .destructive, action: onCancel)
                        .buttonStyle(.ph(.secondary, size: .small))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sending to \(macName)")
        .accessibilityValue(caption)
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
