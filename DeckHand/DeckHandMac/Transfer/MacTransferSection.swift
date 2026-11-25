//
//  MacTransferSection.swift
//  DeckHandMac – Transfer
//
//  S1/S2: the menu-bar panel's Send section. One row per paired, connected
//  iPhone or iPad with Send › File and Clipboard, a drop target (drag
//  files, text or a link onto the device row), incoming prompts, and one
//  summary line for transfers ("3 files sending · 42 %") that opens the
//  Transfers tab (OR-13), where each transfer has its dot beam, progress,
//  Cancel and Show in Finder.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacTransferSection: View {
    @ObservedObject private var service = MacTransferService.shared
    /// Opens the Transfers tab (the summary row's action).
    var onOpenTransfers: () -> Void = {}

    var body: some View {
        if !service.targets.isEmpty || !service.prompts.isEmpty || summary != nil {
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                Rectangle()
                    .fill(PixelHandTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, PixelHandTheme.Space.lg)
                    .accessibilityHidden(true)
                MacSectionLabel(text: "Send")
                    .padding(.horizontal, PixelHandTheme.Space.lg)

                ForEach(service.prompts) { prompt in
                    MacTransferPromptRow(prompt: prompt)
                }
                ForEach(service.targets.sorted(by: { $0.value < $1.value }), id: \.key) { target in
                    MacSendTargetRow(connectionID: target.key, name: target.value)
                }
                // One line instead of a row per file (OR-13): six files used
                // to push everything else off the panel.
                if let summary {
                    MacTransferSummaryRow(summary: summary, fraction: fraction, onOpen: onOpenTransfers)
                }
            }
            .padding(.vertical, PixelHandTheme.Space.md)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ph.mac.transferSection")
        }
        Color.clear.frame(height: 0)
            .onAppear { service.refreshTargets() } // pairing may have changed
    }

    private var summary: String? {
        TransferPanelPlan.summary(service.panelItems, at: Date())
    }

    private var fraction: Double? {
        TransferPanelPlan.overallFraction(service.panelItems, at: Date())
    }
}

/// "3 files sending · 42 %" with the overall beam; opens the Transfers tab.
private struct MacTransferSummaryRow: View {
    let summary: String
    let fraction: Double?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: PixelHandTheme.Space.md) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .foregroundStyle(PixelHandTheme.ink2)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
                    Text(summary)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(PixelHandTheme.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                    if let fraction {
                        MacDotBeam(lit: TransferBeamPhase.sending(fraction: fraction).litDots(of: 20), total: 20, dot: 4, gap: 3)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .padding(.vertical, PixelHandTheme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show transfers")
        .accessibilityLabel(summary)
        .accessibilityHint("Shows the Transfers tab")
        .accessibilityIdentifier("ph.mac.transferSummary")
    }
}

/// The Transfers tab (OR-13): under way first, then the last hour's
/// finished ones, each with its beam, Cancel or Show in Finder.
struct MacTransfersTab: View {
    @ObservedObject private var service = MacTransferService.shared

    var body: some View {
        let now = Date()
        let groups = TransferPanelPlan.groups(service.panelItems, at: now)
        let rowsByID = Dictionary(service.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            ForEach(service.prompts) { prompt in
                MacTransferPromptRow(prompt: prompt)
            }
            ForEach(groups.map { $0.group }, id: \.self) { group in
                let items = groups.first(where: { $0.group == group })?.items ?? []
                HStack {
                    MacSectionLabel(text: group.title)
                    Spacer()
                    if group == .finished {
                        Button("Clear") { service.clearFinished() }
                            .buttonStyle(.macQuiet)
                            .accessibilityLabel("Clear finished transfers")
                            .accessibilityIdentifier("ph.mac.clearTransfers")
                    }
                }
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .padding(.top, PixelHandTheme.Space.xs)
                ForEach(items) { item in
                    if let row = rowsByID[item.id] {
                        MacTransferRowView(row: row)
                    }
                }
            }
            if groups.isEmpty && service.prompts.isEmpty {
                Text("Nothing moving. Finished transfers stay here for an hour.")
                    .font(.callout)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .padding(.horizontal, PixelHandTheme.Space.lg)
            }
        }
        .padding(.vertical, PixelHandTheme.Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.transfersTab")
    }
}

/// A device to send to; also a drop target.
private struct MacSendTargetRow: View {
    let connectionID: UUID
    let name: String
    @State private var isTargeted = false

    init(connectionID: UUID, name: String) {
        self.connectionID = connectionID
        self.name = name
    }

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            Image(systemName: "iphone.and.arrow.forward")
                .foregroundStyle(isTargeted ? PixelHandTheme.accent : PixelHandTheme.ink2)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(isTargeted ? "Drop to send to \(name)" : name)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer()
            Menu("Send") {
                Button("File") { chooseFiles() }
                Button("Clipboard") { MacTransferService.shared.sendClipboard(to: connectionID) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Send to \(name)")
            .accessibilityIdentifier("ph.mac.sendMenu")
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.vertical, PixelHandTheme.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.sendTargetRow")
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                .strokeBorder(isTargeted ? PixelHandTheme.accent : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(.horizontal, PixelHandTheme.Space.sm)
        )
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $isTargeted) { providers in
            receive(providers)
            return true
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Send"
        panel.message = "Send to \(name)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        MacTransferService.shared.send(files: panel.urls, to: connectionID)
    }

    private func receive(_ providers: [NSItemProvider]) {
        let id = connectionID
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in MacTransferService.shared.send(files: [url], to: id) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in MacTransferService.shared.send(text: url.absoluteString, to: id) }
                }
            } else {
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String, !text.isEmpty else { return }
                    Task { @MainActor in MacTransferService.shared.send(text: text, to: id) }
                }
            }
        }
    }
}

/// Accept / Decline for an incoming item.
struct MacTransferPromptRow: View {
    let prompt: MacTransferService.Prompt

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            Text(prompt.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PixelHandTheme.Space.sm) {
                Button(TransferCopy.accept) { MacTransferService.shared.answer(prompt.id, accept: true) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("ph.mac.acceptTransfer")
                Button(TransferCopy.decline) { MacTransferService.shared.answer(prompt.id, accept: false) }
                    .accessibilityIdentifier("ph.mac.declineTransfer")
                if prompt.canAlwaysAccept {
                    Spacer()
                    Button(TransferCopy.alwaysFromDevice) { MacTransferService.shared.answer(prompt.id, accept: true, always: true) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .accessibilityLabel("Accept, and always accept from this device")
                        .accessibilityIdentifier("ph.mac.alwaysAcceptTransfer")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.transferPrompt")
        .padding(PixelHandTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                .fill(PixelHandTheme.warningTint)
        )
        .padding(.horizontal, PixelHandTheme.Space.lg)
    }
}

/// One transfer: kind glyph, name, beam, caption, Cancel / Show in Finder.
private struct MacTransferRowView: View {
    let row: MacTransferService.Row

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                Image(systemName: row.direction == .incoming ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(PixelHandTheme.ink2)
                    .accessibilityHidden(true)
                Text(row.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityValue(row.caption)
                Spacer()
                if row.isActive {
                    Button {
                        if row.direction == .incoming {
                            MacTransferService.shared.cancelIncoming(row.id)
                        } else {
                            MacTransferService.shared.cancelOutgoing(row.id)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .accessibilityLabel("Cancel \(row.name)")
                    .accessibilityIdentifier("ph.mac.cancelTransfer")
                } else if let url = row.savedURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .accessibilityLabel("Show \(row.name) in Finder")
                        .accessibilityIdentifier("ph.mac.showInFinder")
                }
            }
            let phase = row.beam
            MacDotBeam(
                lit: phase.litDots(of: 20),
                total: 20,
                dot: 4,
                gap: 3,
                color: phase == .delivered ? PixelHandTheme.Brand.mint : (phase == .stopped ? PixelHandTheme.danger : PixelHandTheme.accent)
            )
            .accessibilityHidden(true)
            Text(row.caption)
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink2)
                .lineLimit(2)
                .accessibilityHidden(true) // spoken as the name's value
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        // Contain, not combine, so Cancel and Show in Finder stay separate buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.transferRow")
    }
}

/// A small floating panel for incoming prompts while the menu-bar panel
/// is closed. Non-activating, top right, hidden when nothing waits.
@MainActor
final class MacTransferPromptPanel {
    static let shared = MacTransferPromptPanel()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
                styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                backing: .buffered,
                defer: true
            )
            panel.title = "Pixel Hand"
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: MacTransferPromptList())
            self.panel = panel
        }
        guard let panel else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 360, y: frame.maxY - 12))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct MacTransferPromptList: View {
    @ObservedObject private var service = MacTransferService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            ForEach(service.prompts) { prompt in
                MacTransferPromptRow(prompt: prompt)
            }
        }
        .padding(.vertical, PixelHandTheme.Space.md)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(PixelHandTheme.elevated)
    }
}

/// Finder › Services › "Send to iPhone or iPad with Pixel Hand" (the
/// `NSServices` entry in the Mac `Info.plist`). Sends to the paired device
/// when there is one; with several, to the one connected most recently.
@MainActor
final class MacTransferServicesProvider: NSObject {
    static let shared = MacTransferServicesProvider()

    @objc func sendToDevice(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let service = MacTransferService.shared
        service.refreshTargets()
        guard let target = service.targets.keys.first else {
            error.pointee = "Connect a paired iPhone or iPad to Pixel Hand first." as NSString
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            service.send(files: urls, to: target)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            service.send(text: text, to: target)
        }
    }
}
