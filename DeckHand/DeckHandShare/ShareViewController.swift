//
//  ShareViewController.swift
//  DeckHandShare (iOS Share extension)
//
//  S2: "Pixel Hand" in the share sheet of Photos, Safari, Files and other
//  apps. The extension doesn't connect to the Mac itself (an extension has
//  little memory and may be ended at any time): it copies the items into
//  the App Group's drop folder with the Mac they are for, and Pixel Hand
//  sends them the next time it connects to that Mac, resuming if the
//  connection drops (`TransferSharedContainer`, `TransferCenter`).
//
//  Takes images and movies (as photos), files, one web link, or text.
//  Public APIs only.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        model.load()
    }
}

/// One shared thing, ready to drop.
struct SharedThing: Identifiable {
    enum Payload {
        case file(URL, kind: TransferKind, contentType: String?)
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
}

@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable { case loading, ready, queued, failed(String) }

    var things: [SharedThing] = []
    var macs: [TransferMacEntry] = TransferSharedContainer.pairedMacs()
    var selectedMac: UUID?
    var phase: Phase = .loading
    let sharingAllowed = TransferSharedContainer.sharingAllowed

    private weak var context: NSExtensionContext?
    private let workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)

    init(context: NSExtensionContext?) {
        self.context = context
        selectedMac = macs.count == 1 ? macs[0].deviceID : nil
    }

    var canSend: Bool {
        phase == .ready && !things.isEmpty && sharingAllowed && (selectedMac != nil || macs.count == 1)
    }

    func load() {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task {
            for provider in providers {
                if let thing = await Self.load(provider, into: workFolder) {
                    things.append(thing)
                }
            }
            phase = things.isEmpty ? .failed("Pixel Hand can't send this.") : .ready
        }
    }

    func send() {
        let target = selectedMac ?? macs.first?.deviceID
        let name = macs.first(where: { $0.deviceID == target })?.name
        do {
            for thing in things {
                switch thing.payload {
                case let .file(url, kind, type):
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
                    guard TransferPolicy.canSend(kind: kind, byteCount: size) else { continue }
                    let item = TransferOutboxItem(kind: kind, fileName: url.lastPathComponent, byteCount: size, contentType: type, targetDeviceID: target, targetName: name, createdAt: Date())
                    try TransferSharedContainer.drop(item) { destination in
                        try FileManager.default.moveItem(at: url, to: destination)
                    }
                case let .text(text):
                    let data = Data(text.utf8)
                    let kind: TransferKind = TransferInlineText.webLink(text) != nil ? .link : .text
                    guard TransferPolicy.canSend(kind: kind, byteCount: UInt64(data.count)) else { continue }
                    let item = TransferOutboxItem(kind: kind, fileName: TransferInlineText.fileName(for: text, kind: kind), byteCount: UInt64(data.count), contentType: "public.utf8-plain-text", targetDeviceID: target, targetName: name, createdAt: Date())
                    try TransferSharedContainer.drop(item) { destination in
                        try data.write(to: destination, options: .atomic)
                    }
                }
            }
            phase = .queued
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                self.finish()
            }
        } catch {
            phase = .failed("Couldn't keep it for sending. Try again.")
        }
    }

    func cancel() {
        try? FileManager.default.removeItem(at: workFolder)
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func finish() {
        try? FileManager.default.removeItem(at: workFolder)
        context?.completeRequest(returningItems: nil)
    }

    /// Copies one attachment into the work folder, or reads its text.
    private static func load(_ provider: NSItemProvider, into folder: URL) async -> SharedThing? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            return SharedThing(payload: .text(url.absoluteString))
        }
        // A photo or movie first, else anything file-backed that isn't
        // plain text or a link.
        let fileType = provider.registeredContentTypes.first { $0.conforms(to: .image) || $0.conforms(to: .movie) }
            ?? provider.registeredContentTypes.first { !$0.conforms(to: .plainText) && !$0.conforms(to: .url) }
        if let fileType, let copy = await copyFile(from: provider, type: fileType, into: folder) {
            let copiedType = UTType(filenameExtension: copy.pathExtension) ?? fileType
            let kind: TransferKind = copiedType.conforms(to: .image) || copiedType.conforms(to: .movie) ? .photo : .file
            return SharedThing(payload: .file(copy, kind: kind, contentType: copiedType.identifier))
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
           !text.isEmpty {
            return SharedThing(payload: .text(text))
        }
        return nil
    }

    private static func copyFile(from provider: NSItemProvider, type: UTType, into folder: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                // Each file in its own folder, so equal names don't clash.
                let destinationFolder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let name = TransferFileName.sanitized(provider.suggestedName.map { $0 + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)") } ?? url.lastPathComponent, kind: .file)
                let destination = destinationFolder.appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Sending") {
                    switch model.phase {
                    case .loading:
                        ProgressView()
                    case let .failed(message):
                        Text(message).foregroundStyle(.secondary)
                    case .ready, .queued:
                        ForEach(model.things) { thing in
                            Label(thing.title, systemImage: icon(for: thing))
                                .lineLimit(1)
                        }
                    }
                }
                if !model.sharingAllowed {
                    Section {
                        Text("Sending to your Mac is part of Pixel Hand Pro. Open Pixel Hand to start the free trial.")
                            .foregroundStyle(.secondary)
                    }
                } else if model.macs.isEmpty {
                    Section {
                        Text(TransferCopy.shareExtensionNoMac).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("To", selection: $model.selectedMac) {
                            ForEach(model.macs) { mac in
                                Text(mac.name).tag(Optional(mac.deviceID))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("To")
                    } footer: {
                        Text(model.phase == .queued ? "Queued. \(TransferCopy.shareExtensionQueued)" : TransferCopy.shareExtensionQueued)
                    }
                }
            }
            .navigationTitle("Pixel Hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.phase == .queued ? "Queued" : "Send") { model.send() }
                        .disabled(!model.canSend)
                }
            }
        }
    }

    private func icon(for thing: SharedThing) -> String {
        switch thing.payload {
        case let .file(_, kind, _): kind == .photo ? "photo" : "doc"
        case let .text(text): TransferInlineText.webLink(text) != nil ? "link" : "text.alignleft"
        }
    }
}
