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
import UIKit

struct TransferHeaderButton: View {
    /// Bumped by the header's More menu when this circle is folded into it
    /// (build 18 QA, VQ-032/VQ-081): opens the sheet as a tap would.
    var openRequest = 0
    @State private var showsSheet = false
    @State private var showsFloating = false
    @State private var startTab: TransferSheet.Tab = .send
    @Environment(\.scenePhase) private var scenePhase
    private let center = TransferCenter.shared

    var body: some View {
        let unseen = center.inbox.unseenCount
        GlassCircleButton(
            glyph: PixelGlyphs.send,
            label: unseen > 0 ? "Send and Inbox, \(unseen) new" : "Send and Inbox",
            // The unseen dot on the circle's rim, drawn above the glass
            // (OT-14: as an overlay here it sat under the header's glass
            // group and was cut off).
            badge: unseen > 0 ? .dot : nil
        ) {
            open()
        }
        .accessibilityIdentifier("ph.transfer.send")
        .requiresPro(.sharing, badge: .circle(.bottomTrailing))
        // iPhone: the system sheet, sized to the content. iPad: a card
        // centred on the window (OT-15: the form sheet sat off-centre over
        // the canvas and the right column), drawn by `TransferSheetHost`
        // in a cover with no background of its own.
        .sheet(isPresented: $showsSheet) {
            TransferSheet(tab: startTab)
                .controlBadgeScope()
        }
        .fullScreenCover(isPresented: $showsFloating) {
            TransferSheetHost(tab: startTab) {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { showsFloating = false }
            }
            .controlBadgeScope()
        }
        .background {
            // Outside the Pro gate so it isn't disabled with the button.
            Color.clear
                .transferPromptAlert(enabled: !showsSheet && !showsFloating)
                .transferNoticeAlert(enabled: !showsSheet && !showsFloating)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { center.refresh() }
        }
        .onAppear { center.refresh() }
        .onChange(of: openRequest) { _, _ in
            open()
        }
    }

    private func open() {
        startTab = center.inbox.unseenCount > 0 ? .inbox : .send
        if UIDevice.current.userInterfaceIdiom == .pad {
            // The cover appears without its slide; the host fades the
            // scrim and the card in itself.
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { showsFloating = true }
        } else {
            showsSheet = true
        }
    }
}
