//
//  SettingsPairingSection.swift
//  DeckHandiOS
//
//  Settings › Paired Macs (S4): the Macs this device is paired with, each
//  with Forget. Forgetting the connected Mac tells it at once and ends the
//  session; a Mac that's away is told the next time it connects. Pairing
//  lane.
//

import SwiftUI

struct SettingsPairingSection: View {
    private let store = PairedMacsStore.shared
    @State private var confirming: PairedDevice?

    var body: some View {
        Section {
            if store.macs.isEmpty {
                // UX-018: the glyph empty state on navy.
                PixelSurface(cornerRadius: PixelHandTheme.Radius.card) {
                    PHEmptyState(glyph: PixelGlyphs.mac, title: "No paired Macs", message: "Open Pixel Hand on your Mac, then choose it here to pair.")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.macs) { mac in
                    row(mac)
                }
            }
        } header: {
            Text("Paired Macs")
        } footer: {
            Text(footer)
        }
        .confirmationDialog(
            confirming.map { "Forget \($0.name)?" } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { mac in
            Button("Forget", role: .destructive) {
                Task { await store.forget(mac.ref) }
            }
        } message: { mac in
            Text(store.liveMac?.ref == mac.ref
                ? "This ends the session. Next time, \(mac.name) asks you to allow this device again."
                : "Next time, \(mac.name) asks you to allow this device again.")
        }
    }

    private func row(_ mac: PairedDevice) -> some View {
        let isLive = store.liveMac?.ref == mac.ref
        return HStack(spacing: 12) {
            Image(systemName: mac.kind.systemImage)
                .foregroundStyle(PixelHandTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name)
                Text(isLive ? "Connected" : "Paired \(mac.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Forget", role: .destructive) { confirming = mac }
                .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Forget") { confirming = mac }
    }

    private var footer: String {
        var text = "A paired Mac connects without asking. Pair from the waiting screen with the code your Mac shows, or scan its QR code from the Mac list."
        if !store.pendingForgets.isEmpty {
            let count = store.pendingForgets.count
            text += count == 1
                ? " One forgotten Mac will be told the next time it connects."
                : " \(count) forgotten Macs will be told the next time they connect."
        }
        return text
    }
}
