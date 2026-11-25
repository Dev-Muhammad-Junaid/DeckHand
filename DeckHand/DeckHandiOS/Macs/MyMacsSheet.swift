//
//  MyMacsSheet.swift
//  DeckHandiOS – Macs
//
//  My Macs (UX-030; board `v2Macs`): what the Mac pill opens. Every Mac
//  this device knows, as cards with their glance tier, in the list's fixed
//  order (⌘1–⌘4 on the first four). Tap a Mac to switch to it; the focused
//  Mac's card says so. A Mac the free plan doesn't cover carries the PRO
//  badge, and picking it opens the paywall (Store lane's `admitMac`).
//  A dashed "Add another Mac" card fills the grid; Disconnect is a plain
//  row at the foot.
//

import SwiftUI

struct MyMacsSheet: View {
    let currentMacName: String
    let currentSubtitle: String
    let isLive: Bool
    let onDisconnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private let switcher = MacSwitcher.shared

    private var columns: [GridItem] {
        let count = typeSize.typeBand >= .large ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: PixelHandTheme.Space.md, alignment: .top), count: count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.xl) {
                    LazyVGrid(columns: columns, spacing: PixelHandTheme.Space.lg) {
                        ForEach(switcher.listings) { listing in
                            Button {
                                pick(listing)
                            } label: {
                                MacCard(listing: listing, activeSubtitle: currentSubtitle)
                                    .padding(4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityHint(hint(for: listing))
                            .accessibilityAddTraits(listing.isActive ? .isSelected : [])
                            .accessibilityIdentifier("ph.macs.card")
                            .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip + 4)
                            .contextMenu { menu(for: listing) }
                        }
                        // A ghost card fills the grid and says how another
                        // Mac joins (VQ-057).
                        addAnotherCard
                    }

                    if let notice = switcher.notice {
                        PHToast(message: notice, isFailure: true)
                            .transition(.opacity)
                    }

                    if let helpText {
                        HStack(alignment: .top, spacing: PixelHandTheme.Space.md) {
                            PHGlyph(glyph: PixelGlyphs.mac, pitch: PixelPitch.chip)
                                .foregroundStyle(PixelHandTheme.accent)
                            Text(helpText)
                                .font(.subheadline)
                                .foregroundStyle(PixelHandTheme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // A plain secondary row, never the sheet's loudest
                    // control (VQ-057).
                    Button(role: .destructive, action: onDisconnect) {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PixelHandTheme.danger)
                            .frame(minHeight: PixelHandTheme.ControlHeight.hit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Disconnect from \(currentMacName)")
                    .accessibilityIdentifier("ph.macs.disconnect")
                }
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .padding(.vertical, PixelHandTheme.Space.sm)
                .animation(.easeOut(duration: 0.22), value: switcher.notice)
            }
            .background(PixelHandTheme.elevated)
            .navigationTitle("My Macs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The dashed "Add another Mac" card: same size as a Mac card, with
    /// the one step it takes.
    private var addAnotherCard: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            PHGlyph(glyph: PixelGlyphs.add, pitch: PixelPitch.chip)
                .foregroundStyle(PixelHandTheme.accent)
            Text("Add another Mac")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PixelHandTheme.ink)
            Text("Open Pixel Hand on it, on the same Wi-Fi or a cable.")
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .strokeBorder(PixelHandTheme.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        )
        .padding(4)
        .accessibilityElement(children: .combine)
    }

    /// How to switch, once there's another Mac; the ghost card covers
    /// adding one.
    private var helpText: String? {
        let hasOthers = switcher.listings.contains { !$0.isActive }
        guard hasOthers else { return nil }
        return "Tap a Mac to switch. Swipe the Mac pill, swipe three fingers sideways on the trackpad, or press ⌘1–⌘4 with a keyboard."
    }

    private func pick(_ listing: MacListing) {
        if listing.isActive {
            dismiss()
            return
        }
        GestureHaptic.selection.trigger()
        switcher.request(listing.deviceID)
        // Stay open when the switch can't start, so the reason shows here;
        // the paywall presents over the root either way.
        if switcher.machine.dialingDeviceID == listing.deviceID {
            dismiss()
        }
    }

    private func hint(for listing: MacListing) -> String {
        if listing.isActive { return "The Mac you're using." }
        if !listing.isReachable { return "Not in reach now." }
        return "Switches to \(listing.name)."
    }

    @ViewBuilder
    private func menu(for listing: MacListing) -> some View {
        if !listing.isActive {
            Button {
                pick(listing)
            } label: {
                Label("Switch to \(listing.name)", systemImage: "arrow.left.arrow.right")
            }
            .disabled(!listing.isReachable)
            if switcher.memory(for: listing.deviceID) != nil, !listing.isPaired {
                Button(role: .destructive) {
                    switcher.forget(listing.deviceID)
                } label: {
                    Label("Remove from My Macs", systemImage: "minus.circle")
                }
            }
        }
    }
}
