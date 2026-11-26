//
//  InboxPanel.swift
//  DeckHandiOS – Transfer
//
//  S2: the Inbox. Items arriving now (progress, Cancel) on top, then what
//  Macs sent, newest first, with an unseen dot. Tap: a link opens, text
//  copies, a file opens the share sheet. The menu adds Save to Photos for
//  images and movies, Copy, Share and Delete.
//
//  Also: the incoming prompt (`transferPromptAlert`) and passing notices
//  (`transferNoticeAlert`), used by the sheet and the header button so a
//  prompt shows wherever the person is.
//

import Photos
import SwiftUI
import UIKit

struct InboxPanel: View {
    private let center = TransferCenter.shared
    @Environment(\.openURL) private var openURL
    @State private var shareURL: URL?
    @State private var saveMessage: String?

    var body: some View {
        let arriving = center.activities.values.filter { $0.direction == .incoming && $0.isActive }.sorted { $0.name < $1.name }
        List {
            if !arriving.isEmpty {
                Section("Arriving") {
                    ForEach(arriving) { activity in
                        VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
                            HStack {
                                Text(activity.name).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button("Cancel", role: .destructive) { center.cancel(activity.id) }
                                    .buttonStyle(.ph(.destructive, size: .small))
                            }
                            DotBeam(state: .progress(activity.meter.fraction), count: 16)
                            Text("From \(activity.macName) · \(activity.meter.caption)")
                                .font(.caption)
                                .foregroundStyle(PixelHandTheme.ink2)
                        }
                        .padding(.vertical, PixelHandTheme.Space.xs)
                        .listRowBackground(PixelHandTheme.raised)
                    }
                }
            }
            if center.inbox.items.isEmpty {
                Section {
                    PHEmptyState(
                        glyph: PixelGlyphs.send,
                        title: "Nothing yet",
                        message: TransferCopy.emptyInbox
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(center.inbox.items) { item in
                        InboxRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(item.link != nil ? "Opens the link" : (item.text != nil ? "Copies the text" : "Opens the share sheet"))
                            .accessibilityIdentifier("ph.inbox.row")
                            .listRowBackground(PixelHandTheme.raised)
                            .contextMenu { menu(for: item) }
                            .swipeActions {
                                Button("Delete", role: .destructive) { center.deleteInboxItem(item.id) }
                            }
                    }
                } footer: {
                    Text("Also in Files: On My \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") › Pixel Hand.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("ph.inbox")
        .sheet(item: Binding(get: { shareURL.map(ShareTarget.init) }, set: { shareURL = $0?.url })) { target in
            ShareSheet(items: [target.url])
        }
        .alert(saveMessage ?? "", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onDisappear { center.markAllSeen() }
    }

    @ViewBuilder
    private func menu(for item: TransferInboxItem) -> some View {
        if let link = item.link {
            Button { openURL(link); center.markSeen(item.id) } label: { Label("Open link", systemImage: "safari") }
        }
        if let text = item.text {
            Button { UIPasteboard.general.string = text; center.markSeen(item.id) } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        if item.isPhotoLibraryCompatible {
            Button { saveToPhotos(item) } label: { Label("Save to Photos", systemImage: "photo.badge.plus") }
        }
        Button { shareURL = center.inboxURL(for: item); center.markSeen(item.id) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { center.deleteInboxItem(item.id) } label: { Label("Delete", systemImage: "trash") }
    }

    private func open(_ item: TransferInboxItem) {
        center.markSeen(item.id)
        if let link = item.link {
            openURL(link)
        } else if let text = item.text {
            UIPasteboard.general.string = text
            saveMessage = "Copied."
        } else {
            shareURL = center.inboxURL(for: item)
        }
    }

    private func saveToPhotos(_ item: TransferInboxItem) {
        let url = center.inboxURL(for: item)
        let isMovie = ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) || (item.contentType?.contains("movie") ?? false)
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveMessage = "Allow Pixel Hand to add photos in Settings › Privacy › Photos."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: isMovie ? .video : .photo, fileURL: url, options: nil)
                }
                center.markSeen(item.id)
                saveMessage = "Saved to Photos."
            } catch {
                saveMessage = "Couldn't save it to Photos."
            }
        }
    }
}

private struct InboxRow: View {
    let item: TransferInboxItem

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            // The unseen mark is the app's dot: a rounded square.
            RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                .fill(item.isSeen ? Color.clear : PixelHandTheme.accent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            PHGlyph(glyph: glyph, pitch: PixelPitch.chip)
                .foregroundStyle(PixelHandTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                // "seen … ago" words from Core, the same as the Mac cards.
                Text("From \(item.senderName) · \(MacGlanceCopy.age(from: item.receivedAt, to: Date()))\(item.kind.isInline ? "" : " · " + TransferProgressMeter.size(item.byteCount))")
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: PixelHandTheme.ControlHeight.standard)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isSeen ? "" : "New")
    }

    private var glyph: GlyphBitmap {
        switch item.kind {
        case .link: TransferGlyphs.link
        case .text: PixelGlyphs.type
        case .photo: TransferGlyphs.photos
        case .file: item.isPhotoLibraryCompatible ? TransferGlyphs.photos : TransferGlyphs.files
        }
    }
}

private struct ShareTarget: Identifiable {
    let url: URL
    var id: URL { url }
}

// The share sheet is `ShareSheet` (ScreenshotPreviewView.swift).

// MARK: - Prompts and notices

extension View {
    /// Accept / Decline for an incoming item that needs asking.
    /// `enabled: false` while another presenter (the sheet) shows it.
    func transferPromptAlert(enabled: Bool = true) -> some View {
        modifier(TransferPromptAlert(enabled: enabled))
    }

    /// A passing line about a transfer ("Studio is locked…").
    func transferNoticeAlert(enabled: Bool = true) -> some View {
        modifier(TransferNoticeAlert(enabled: enabled))
    }
}

private struct TransferPromptAlert: ViewModifier {
    let enabled: Bool
    private let center = TransferCenter.shared

    func body(content: Content) -> some View {
        let prompt = enabled ? center.prompts.first : nil
        content.alert(
            "Receive from your Mac?",
            isPresented: Binding(get: { prompt != nil }, set: { _ in }),
            presenting: prompt
        ) { prompt in
            Button(TransferCopy.accept) { center.answer(prompt.id, accept: true) }
            if prompt.canAlwaysAccept {
                Button(TransferCopy.alwaysFromDevice) { center.answer(prompt.id, accept: true, always: true) }
            }
            Button(TransferCopy.decline, role: .cancel) { center.answer(prompt.id, accept: false) }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}

private struct TransferNoticeAlert: ViewModifier {
    let enabled: Bool
    private let center = TransferCenter.shared

    func body(content: Content) -> some View {
        content.alert(
            center.notice ?? "",
            isPresented: Binding(get: { enabled && center.notice != nil }, set: { if !$0 { center.notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}
