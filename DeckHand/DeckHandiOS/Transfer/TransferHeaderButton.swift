//
//  TransferHeaderButton.swift
//  DeckHandiOS – Transfer
//
//  S2: the shell header's Send button (one announced line in
//  `ShellHeader`). Opens Send and Inbox; a dot shows unseen Inbox items.
//  Sharing is Pixel Hand Pro, so the button is gated; the incoming prompt
//  and notices hang off it so they show on the main screen too, and the
//  App Group drops from the Share extension are taken in whenever the app
//  comes to the front.
//

import SwiftUI

struct TransferHeaderButton: View {
    /// Bumped by the header's More menu when this circle is folded into it
    /// (build 18 QA, VQ-032/VQ-081): opens the sheet as a tap would.
    var openRequest = 0
    @State private var showsSheet = false
    @State private var startTab: TransferSheet.Tab = .send
    @Environment(\.scenePhase) private var scenePhase
    private let center = TransferCenter.shared

    var body: some View {
        GlassCircleButton(
            glyph: PixelGlyphs.send,
            label: center.inbox.unseenCount > 0 ? "Send and Inbox, \(center.inbox.unseenCount) new" : "Send and Inbox"
        ) {
            startTab = center.inbox.unseenCount > 0 ? .inbox : .send
            showsSheet = true
        }
        .overlay(alignment: .topTrailing) {
            if center.inbox.unseenCount > 0 {
                // The unseen dot is the app's one kind of dot: a rounded
                // square (`06-Pixel-Identity.md` §0).
                RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                    .fill(PixelHandTheme.accent)
                    .frame(width: 8, height: 8)
                    .offset(x: -4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("ph.transfer.send")
        .requiresPro(.sharing)
        .sheet(isPresented: $showsSheet) {
            // Sized to its content by the sheet itself (`TransferSheetSizing`,
            // owner testing build 26, OT-9); it was a fixed medium detent.
            TransferSheet(tab: startTab)
        }
        .background {
            // Outside the Pro gate so it isn't disabled with the button.
            Color.clear
                .transferPromptAlert(enabled: !showsSheet)
                .transferNoticeAlert(enabled: !showsSheet)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { center.refresh() }
        }
        .onAppear { center.refresh() }
        .onChange(of: openRequest) { _, _ in
            startTab = center.inbox.unseenCount > 0 ? .inbox : .send
            showsSheet = true
        }
    }
}
