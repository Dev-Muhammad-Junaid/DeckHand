//
//  SendSheetTests.swift
//  PixelHandCoreTests
//
//  The Send sheet (owner testing, build 26, OT-9): the "Send to" cards'
//  states and order, the offline "seen … ago" copy, the sheet's height
//  from its content, and the source glyphs.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct SendSheetTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let studio = UUID()
    static let air = UUID()
    static let mini = UUID()
    static let old = UUID()

    static func listing(
        _ id: UUID,
        _ name: String,
        active: Bool = false,
        reachable: Bool = false,
        nearby: Bool = true,
        paired: Bool = true,
        connecting: Bool = false,
        locked: Bool = false,
        seen: TimeInterval? = nil
    ) -> MacListing {
        MacListing(
            deviceID: id,
            name: name,
            isActive: active,
            isConnecting: connecting,
            isReachable: reachable || active,
            isNearby: nearby,
            isPaired: paired,
            glance: (seen != nil || locked) ? MacGlance(lockState: locked ? .screenLocked : nil, updatedAt: now.addingTimeInterval(-(seen ?? 0))) : nil
        )
    }

    // MARK: States

    @Test("The focused Mac is ready; a reachable one says to switch; an unreachable one is offline")
    func basicStates() {
        let ready = SendTargetPlan.state(for: Self.listing(Self.studio, "Studio", active: true), outgoing: [])
        #expect(ready == .ready)
        #expect(ready.light == .live)

        let near = SendTargetPlan.state(for: Self.listing(Self.air, "Air", reachable: true), outgoing: [])
        #expect(near == .inReach(nearby: true))
        #expect(SendTargetCopy.statusLine(for: near, now: Self.now) == "Nearby · switch to send")
        let remote = SendTargetPlan.state(for: Self.listing(Self.air, "Air", reachable: true, nearby: false), outgoing: [])
        #expect(SendTargetCopy.statusLine(for: remote, now: Self.now) == "Remote · switch to send")

        let gone = SendTargetPlan.state(for: Self.listing(Self.mini, "Mini", seen: 2 * 3600), outgoing: [])
        #expect(gone == .offline(lastSeen: Self.now.addingTimeInterval(-7200)))
        #expect(gone.isCompact)
        #expect(gone.light == .off)
    }

    @Test("Items moving to the focused Mac show sending progress by bytes")
    func sendingProgress() {
        let items = [
            SendTargetPlan.Outgoing(targetDeviceID: Self.studio, isMoving: true, bytes: 30, totalBytes: 100),
            SendTargetPlan.Outgoing(targetDeviceID: nil, isMoving: true, bytes: 12, totalBytes: 100),
        ]
        let state = SendTargetPlan.state(for: Self.listing(Self.studio, "Studio", active: true), outgoing: items)
        #expect(state == .sending(count: 2, fraction: 0.21))
        let target = SendTarget(listing: Self.listing(Self.studio, "Studio", active: true), state: state)
        #expect(target.readout == "21%")
        #expect(target.statusLine(now: Self.now) == "Sending 2 items")
        #expect(target.spoken(now: Self.now) == "Sending 2 items, 21 percent")

        let one = SendTargetPlan.state(for: Self.listing(Self.studio, "Studio", active: true), outgoing: [items[0]])
        #expect(SendTargetCopy.statusLine(for: one, now: Self.now) == "Sending 1 item")
    }

    @Test("Before any byte moves, a send reads as waiting for the Mac to accept")
    func waitingToAccept() {
        let items = [SendTargetPlan.Outgoing(targetDeviceID: Self.studio, isMoving: true, bytes: 0, totalBytes: 100)]
        let state = SendTargetPlan.state(for: Self.listing(Self.studio, "Studio", active: true), outgoing: items)
        #expect(state == .sending(count: 1, fraction: nil))
        #expect(SendTargetCopy.statusLine(for: state, now: Self.now) == "Waiting to accept")
        #expect(SendTarget(listing: Self.listing(Self.studio, "Studio", active: true), state: state).readout == nil)
    }

    @Test("A locked focused Mac or one sending to this device is busy")
    func busy() {
        let locked = SendTargetPlan.state(for: Self.listing(Self.studio, "Studio", active: true, locked: true), outgoing: [])
        #expect(locked == .busy(.locked))
        #expect(locked.light == .needsYou)
        #expect(SendTargetCopy.statusLine(for: locked, now: Self.now) == "Locked · unlock to receive")

        let receiving = SendTargetPlan.state(for: Self.listing(Self.studio, "Studio", active: true), outgoing: [], incomingCount: 2)
        #expect(receiving == .busy(.receiving(count: 2)))
        #expect(SendTargetCopy.statusLine(for: receiving, now: Self.now) == "Busy · sending you 2 items")
        #expect(SendTargetCopy.statusLine(for: .busy(.receiving(count: 1)), now: Self.now) == "Busy · sending you 1 item")
    }

    @Test("Items queued for a Mac that isn't focused wait for the switch")
    func queuedForOtherMac() {
        let items = [
            SendTargetPlan.Outgoing(targetDeviceID: Self.air, isMoving: false),
            SendTargetPlan.Outgoing(targetDeviceID: Self.air, isMoving: false),
        ]
        let state = SendTargetPlan.state(for: Self.listing(Self.air, "Air", reachable: true), outgoing: items)
        #expect(state == .waiting(count: 2))
        #expect(SendTargetCopy.statusLine(for: state, now: Self.now) == "2 waiting · switch to send")
        #expect(SendTarget(listing: Self.listing(Self.air, "Air", reachable: true), state: state).readout == "2")
    }

    @Test("A Mac being dialled reads Connecting")
    func connecting() {
        let state = SendTargetPlan.state(for: Self.listing(Self.air, "Air", connecting: true), outgoing: [])
        #expect(state == .connecting)
        #expect(SendTargetCopy.statusLine(for: state, now: Self.now) == "Connecting…")
    }

    // MARK: Order

    @Test("Cards keep the roster order; offline Macs go apart, most recently seen first")
    func order() {
        let listings = [
            Self.listing(Self.old, "Old", seen: 3 * 86_400),
            Self.listing(Self.air, "Air", reachable: true),
            Self.listing(Self.mini, "Mini", seen: 2 * 3600),
            Self.listing(Self.studio, "Studio", active: true),
            Self.listing(UUID(), "Never"),
            Self.listing(UUID(), "Stranger", reachable: true, paired: false),
        ]
        let (cards, offline) = SendTargetPlan.targets(listings: listings, outgoing: [])
        #expect(cards.map(\.listing.name) == ["Air", "Studio"])
        #expect(offline.map(\.listing.name) == ["Mini", "Old", "Never"])
        #expect(offline.allSatisfy { $0.state.isCompact })
    }

    @Test("Items for the next Mac count toward the focused one, not the others")
    func nextMacItems() {
        let listings = [
            Self.listing(Self.studio, "Studio", active: true),
            Self.listing(Self.air, "Air", reachable: true),
        ]
        let items = [SendTargetPlan.Outgoing(targetDeviceID: nil, isMoving: true, bytes: 50, totalBytes: 100)]
        let (cards, _) = SendTargetPlan.targets(listings: listings, outgoing: items)
        #expect(cards[0].state == .sending(count: 1, fraction: 0.5))
        #expect(cards[1].state == .inReach(nearby: true))
    }

    // MARK: Copy

    @Test("Offline Macs say when they were last seen, in My Macs' words")
    func seenAgo() {
        let now = Self.now
        #expect(SendTargetCopy.offlineLine(lastSeen: now.addingTimeInterval(-20), now: now) == "Seen just now")
        #expect(SendTargetCopy.offlineLine(lastSeen: now.addingTimeInterval(-300), now: now) == "Seen 5 min ago")
        #expect(SendTargetCopy.offlineLine(lastSeen: now.addingTimeInterval(-7200), now: now) == "Seen 2 h ago")
        #expect(SendTargetCopy.offlineLine(lastSeen: now.addingTimeInterval(-3 * 86_400), now: now) == "Seen 3 d ago")
        #expect(SendTargetCopy.offlineLine(lastSeen: nil, now: now) == "Offline")
        // A clock that moved backwards never reads as the future.
        #expect(SendTargetCopy.offlineLine(lastSeen: now.addingTimeInterval(60), now: now) == "Seen just now")
        let target = SendTarget(listing: Self.listing(Self.mini, "Mini", seen: 7200), state: .offline(lastSeen: now.addingTimeInterval(-7200)))
        #expect(target.spoken(now: now) == "Seen 2 h ago")
    }

    // MARK: Layout

    @Test("Cards take two columns at iPhone width, up to three on iPad, one when narrow")
    func columns() {
        #expect(SendSheetLayout.columns(width: 402 - 32) == 2)
        #expect(SendSheetLayout.columns(width: 375 - 32) == 2)
        #expect(SendSheetLayout.columns(width: 300) == 1)
        #expect(SendSheetLayout.columns(width: 580 - 48) == 3)
        #expect(SendSheetLayout.columns(width: 1180) == 3)
        #expect(SendSheetLayout.columns(width: 0) == 1)
        #expect(SendSheetLayout.rows(count: 5, columns: 2) == 3)
        #expect(SendSheetLayout.rows(count: 0, columns: 2) == 0)
    }

    @Test("The sheet grows with its content: tray items, cards and the beam each add height")
    func estimateGrows() {
        let width = 370.0
        let base = SendSheetLayout.SendContent(cardCount: 1)
        let h0 = SendSheetLayout.estimatedSendHeight(base, width: width)
        var more = base
        more.stagedCount = 2
        #expect(SendSheetLayout.estimatedSendHeight(more, width: width) == h0 + 20 + 8 + 2 * 52 + 8 + 16)
        more = base
        more.cardCount = 3 // two columns: a second row
        #expect(SendSheetLayout.estimatedSendHeight(more, width: width) == h0 + 64 + 12)
        more = base
        more.showsBeam = true
        #expect(SendSheetLayout.estimatedSendHeight(more, width: width) == h0 + 148 + 16)
    }

    @Test("An offline Mac costs less height than a card")
    func offlineIsCompact() {
        let width = 300.0 // one column
        let asCard = SendSheetLayout.estimatedSendHeight(.init(cardCount: 2), width: width)
        let asOffline = SendSheetLayout.estimatedSendHeight(.init(cardCount: 1, offlineCount: 1), width: width)
        #expect(asOffline < asCard)
        #expect(SendSheetLayout.offlineHeight < SendSheetLayout.cardHeight)
    }

    @Test("The base Send sheet is header, chips, field and one row of cards")
    func baseHeight() {
        let content = SendSheetLayout.estimatedSendHeight(.init(cardCount: 2), width: 370)
        // chips 44 + 16 + field 52 + 16 + label 20 + 8 + card 64 + bottom 16.
        #expect(content == 236)
        #expect(SendSheetLayout.sheetHeight(content: content, container: 1180) == 296)
    }

    @Test("The sheet height stays between the minimum and the window, on the 4 pt grid")
    func sheetClamp() {
        #expect(SendSheetLayout.sheetHeight(content: 10, container: 1180) == SendSheetLayout.minimumHeight)
        #expect(SendSheetLayout.sheetHeight(content: 5000, container: 820) == 772)
        #expect(SendSheetLayout.sheetHeight(content: 301, container: 1180).truncatingRemainder(dividingBy: 4) == 0)
        #expect(SendSheetLayout.overflows(content: 5000, container: 820))
        #expect(!SendSheetLayout.overflows(content: 300, container: 820))
        // A tiny window still gets the minimum.
        #expect(SendSheetLayout.sheetHeight(content: 600, container: 200) == SendSheetLayout.minimumHeight)
    }

    @Test("Sub-grid changes in the measured height don't resize the sheet")
    func resizeHysteresis() {
        #expect(SendSheetLayout.isNewHeight(300, comparedWith: nil))
        #expect(!SendSheetLayout.isNewHeight(300.5, comparedWith: 299.7))
        #expect(SendSheetLayout.isNewHeight(320, comparedWith: 300))
    }

    @Test("The Inbox is sized by its rows, or the empty state")
    func inboxHeight() {
        let empty = SendSheetLayout.estimatedInboxHeight(arriving: 0, items: 0)
        #expect(empty == SendSheetLayout.inboxEmptyHeight + SendSheetLayout.bottomPadding)
        let three = SendSheetLayout.estimatedInboxHeight(arriving: 0, items: 3)
        let four = SendSheetLayout.estimatedInboxHeight(arriving: 0, items: 4)
        #expect(four - three == SendSheetLayout.inboxRowHeight + SendSheetLayout.rowGap)
        #expect(SendSheetLayout.estimatedInboxHeight(arriving: 1, items: 3) > three)
    }

    @Test("Every size is on the 4 pt grid")
    func grid() {
        let sizes = [
            SendSheetLayout.headerHeight, SendSheetLayout.chipHeight, SendSheetLayout.fieldHeight,
            SendSheetLayout.cardHeight, SendSheetLayout.offlineHeight, SendSheetLayout.trayRowHeight,
            SendSheetLayout.waitingRowHeight, SendSheetLayout.beamHeight, SendSheetLayout.labelHeight,
            SendSheetLayout.inboxRowHeight, SendSheetLayout.sectionGap, SendSheetLayout.rowGap,
            SendSheetLayout.cardGap, SendSheetLayout.minimumHeight,
        ]
        for size in sizes { #expect(size.truncatingRemainder(dividingBy: 4) == 0, "\(size)") }
    }

    // MARK: Glyphs

    @Test("Transfer glyphs follow the glyph rules: 9 × 9, one-dot strokes, lit accent, unique names")
    func glyphs() {
        let others = Set((PixelGlyphs.all + CaptureGlyphs.all).map(\.name))
        #expect(Set(TransferGlyphs.all.map(\.name)).count == TransferGlyphs.all.count)
        for glyph in TransferGlyphs.all {
            #expect(!others.contains(glyph.name), "\(glyph.name) clashes")
            #expect(glyph.rows.count == 9)
            #expect(glyph.thickStrokeBlocks.isEmpty, "\(glyph.name): \(glyph.thickStrokeBlocks)")
            #expect(!glyph.isSolid)
            #expect(glyph.accent != nil)
            if let accent = glyph.accent { #expect(glyph.isOn(accent.x, accent.y)) }
        }
    }
}
