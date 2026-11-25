//
//  MacPanelOwnerReviewTests.swift
//  PixelHandCoreTests
//
//  The Mac panel after the owner's review of build 18: one Devices list
//  (OR-08), fades instead of flows (OR-09), the QR's centre tile (OR-10),
//  one code format at full brightness (OR-11), no "…" on buttons (OR-12)
//  and the Transfers tab (OR-13).
//

import Foundation
import Testing
@testable import PixelHandCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func id(_ n: UInt8) -> UUID {
    UUID(uuid: (n, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

@Suite("Mac panel: one Devices list (OR-08)")
struct MacDeviceListPlanTests {
    typealias Plan = MacDeviceListPlan

    @Test("Requests first, then live sessions newest first, then paired devices that are away")
    func order() {
        let rows = Plan.rows(
            asking: [.init(connectionID: id(1), name: "iPhone 17 Pro", requestedAt: t0)],
            live: [
                .init(connectionID: id(2), name: "iPad Pro", connectedAt: t0, pairedKey: "k-ipad"),
                .init(connectionID: id(3), name: "iPad mini", connectedAt: t0.addingTimeInterval(60)),
            ],
            paired: [
                .init(key: "k-ipad", name: "iPad Pro", lastSeenAt: t0),
                .init(key: "k-old", name: "Old iPhone", lastSeenAt: t0.addingTimeInterval(-86_400)),
                .init(key: "k-air", name: "iPad Air", lastSeenAt: t0.addingTimeInterval(-60)),
            ]
        )
        #expect(rows.map(\.name) == ["iPhone 17 Pro", "iPad mini", "iPad Pro", "iPad Air", "Old iPhone"])
        #expect(rows.map(\.state) == [.asking, .connected, .connected, .pairedAway, .pairedAway])
        #expect(rows.map(\.state) == rows.map(\.state).sorted())
    }

    @Test("A paired device that is connected shows once, as connected and paired")
    func mergesPairedAndLive() {
        let rows = Plan.rows(
            asking: [],
            live: [.init(connectionID: id(2), name: "iPad Pro", connectedAt: t0, pairedKey: "k")],
            paired: [.init(key: "k", name: "iPad Pro", lastSeenAt: t0)]
        )
        #expect(rows.count == 1)
        #expect(rows[0].state == .connected)
        #expect(rows[0].isPaired)
        #expect(rows[0].pairedKey == "k")
        #expect(rows[0].connectionID == id(2))
    }

    @Test("Only a request has buttons on the row; Forget and Disconnect live in the menu")
    func actions() {
        let rows = Plan.rows(
            asking: [.init(connectionID: id(1), name: "A")],
            live: [
                .init(connectionID: id(2), name: "B", connectedAt: t0, pairedKey: "kb"),
                .init(connectionID: id(3), name: "C", connectedAt: t0),
            ],
            paired: [.init(key: "kb", name: "B", lastSeenAt: t0), .init(key: "kd", name: "D", lastSeenAt: t0)]
        )
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        #expect(byName["A"]?.buttons == [.deny, .pair, .allow])
        #expect(byName["A"]?.menu == [])
        #expect(byName["B"]?.buttons == [])
        #expect(byName["B"]?.menu == [.disconnect, .forget])
        // Allowed for this session only: offer to pair it, never Forget.
        #expect(byName["C"]?.menu == [.pair, .disconnect])
        #expect(byName["D"]?.menu == [.forget])
        for row in rows where row.state != .asking {
            #expect(row.buttons.isEmpty)
        }
    }

    @Test("A live session whose paired record was just forgotten isn't shown as paired")
    func staleKey() {
        let rows = Plan.rows(
            asking: [],
            live: [.init(connectionID: id(2), name: "B", connectedAt: t0, pairedKey: "gone")],
            paired: []
        )
        #expect(rows.count == 1)
        #expect(!rows[0].isPaired)
        #expect(rows[0].menu == [.pair, .disconnect])
    }

    @Test("A request that has since been allowed shows only as connected")
    func requestThenLive() {
        let rows = Plan.rows(
            asking: [.init(connectionID: id(4), name: "iPad")],
            live: [.init(connectionID: id(4), name: "iPad", connectedAt: t0)],
            paired: []
        )
        #expect(rows.map(\.state) == [.connected])
    }

    @Test("Row ids are stable per state and unique")
    func ids() {
        let rows = Plan.rows(
            asking: [.init(connectionID: id(1), name: "A")],
            live: [.init(connectionID: id(2), name: "B", connectedAt: t0)],
            paired: [.init(key: "k", name: "C", lastSeenAt: t0)]
        )
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.id) == ["ask-\(id(1).uuidString)", "live-\(id(2).uuidString)", "paired-k"])
    }

    @Test("Each state's second line")
    func detailCopy() {
        let rel: (Date) -> String = { _ in "2 min ago" }
        #expect(Plan.detailText(.asking(since: t0), relative: rel) == "Wants to control this Mac · 2 min ago")
        #expect(Plan.detailText(.asking(since: nil), relative: rel) == "Wants to control this Mac")
        #expect(Plan.detailText(.connected(since: t0, isPaired: true), relative: rel) == "Connected · paired")
        #expect(Plan.detailText(.connected(since: t0, isPaired: false), relative: rel) == "Connected for this session")
        #expect(Plan.detailText(.pairedAway(lastSeen: t0), relative: rel) == "Paired · not connected · last seen 2 min ago")
        #expect(Plan.spokenState(.pairedAway) == "paired, not connected")
    }

    @Test("The hint under the list shows only while nothing is live or asking")
    func hint() {
        #expect(Plan.hint(rows: [], macName: "Studio")?.contains("choose Studio") == true)
        let away = Plan.rows(asking: [], live: [], paired: [.init(key: "k", name: "iPad", lastSeenAt: t0)])
        #expect(Plan.hint(rows: away, macName: "Studio") == "Open Pixel Hand on one of them and choose Studio.")
        let live = Plan.rows(asking: [], live: [.init(connectionID: id(1), name: "iPad", connectedAt: t0)], paired: [])
        #expect(Plan.hint(rows: live, macName: "Studio") == nil)
        let asking = Plan.rows(asking: [.init(connectionID: id(1), name: "iPad")], live: [], paired: [])
        #expect(Plan.hint(rows: asking, macName: "Studio") == nil)
    }

    @Test("Forget asks in the row first, and says when it also disconnects")
    func forgetPrompt() {
        #expect(Plan.forgetPrompt(name: "iPad", isConnected: true).contains("disconnects now"))
        #expect(!Plan.forgetPrompt(name: "iPad", isConnected: false).contains("disconnects"))
    }
}

@Suite("Mac panel: no trailing ellipsis on buttons (OR-12)")
struct MacPanelEllipsisTests {
    @Test("Row actions, Pair a device and the turned-away buttons carry no “…”")
    func noEllipsis() {
        var labels = MacDeviceListPlan.Action.allCases.map(\.title)
        labels.append(MacDeviceListPlan.pairButton)
        for reason in [AuthRefusal.notPairedRemote, .timedOut, .unverified] {
            if let copy = MacPanelCopy.turnedAway(name: "iPad", reason: reason) { labels.append(copy.action) }
        }
        for label in labels {
            #expect(!label.hasSuffix("…") && !label.hasSuffix("..."), "\(label)")
        }
        #expect(MacDeviceListPlan.pairButton == "Pair a device")
        #expect(MacDeviceListPlan.Action.forget.title == "Forget")
    }
}

@Suite("Mac panel: one code format at full brightness (OR-11)")
struct MacPanelCodeFormatTests {
    @Test("The example on onboarding and the Mac's format: eight digits, “4821 0934”, valid")
    func example() throws {
        let code = try #require(PairingCode("48210934"))
        #expect(code.formatted == "4821 0934")
        #expect(PairingCode.length == 8)
        #expect(PairingCode.grouped("48210934") == "4821 0934")
    }

    @Test("The Mac draws two groups of four, the same as the entry field groups them")
    func groups() throws {
        let code = try #require(PairingCode("48210934"))
        let groups = PairingCodeDisplay.groups(code)
        #expect(groups.map(\.text) == ["4821", "0934"])
        #expect(groups.map(\.text).joined(separator: " ") == PairingCode.grouped(code.digits))
    }
}

@Suite("Mac panel: fades, not flows (OR-09)")
struct MacPanelMotionTests {
    @Test("The fade is 150–200 ms, and Reduce Motion changes at once")
    func fade() {
        #expect((0.15...0.2).contains(MacPanelMotion.fadeDuration))
        #expect(MacPanelMotion.fade(reduceMotion: false) == MacPanelMotion.fadeDuration)
        #expect(MacPanelMotion.fade(reduceMotion: true) == nil)
        #expect(MacPanelMotion.breathDim > 0 && MacPanelMotion.breathDim < 1)
    }
}

@Suite("Pair window: centre tile on the QR's centre module (OR-10)")
struct QRCentreTileTests {
    @Test("The tile is an odd number of whole modules inside the cleared square")
    func sides() {
        for n in stride(from: 21, through: 77, by: 4) {
            let side = QRCentreTile.sideModules(modules: n)
            #expect(side % 2 == 1, "n=\(n)")
            #expect(side > 0 && side < QRDotPlan.clearedSide(modules: n), "n=\(n)")
        }
    }

    @Test("The tile's centre is the centre module's centre, for every QR size")
    func centred() throws {
        for n in stride(from: 21, through: 77, by: 4) {
            let module = 184.0 / Double(n + 4)
            let frame = try #require(QRCentreTile.frame(modules: n, moduleSide: module, quietModules: 2))
            let centre = QRCentreTile.centreModuleCentre(modules: n, moduleSide: module, quietModules: 2)
            #expect(abs(frame.x + frame.side / 2 - centre) < 1e-9, "n=\(n)")
            #expect(abs(frame.y + frame.side / 2 - centre) < 1e-9, "n=\(n)")
            // …which is also the drawing's centre: the code is symmetric.
            #expect(abs(centre - 92) < 1e-9, "n=\(n)")
            // Every tile module is cleared, so the tile never hides data.
            let start = (n - QRCentreTile.sideModules(modules: n)) / 2
            #expect(QRDotPlan.isCleared(x: start, y: start, modules: n))
        }
    }

    @Test("The hand's lit dots are 16 × 18 on a 17 × 18 canvas: half a pitch right centres it")
    func handInk() throws {
        let box = try #require(GlyphInkCentring.box(rows: MenuBarHand.handRows))
        #expect(box.width == 16 && box.height == 18)
        let offset = GlyphInkCentring.offset(box: box, columns: 17, rows: 18, pitch: 2)
        #expect(offset.x == 1)
        #expect(offset.y == 0)
    }

    @Test("The pointer glyph's lit dots centre too")
    func pointerInk() throws {
        let box = try #require(GlyphInkCentring.box(glyph: PixelGlyphs.pointer))
        #expect(box.minX == 0 && box.maxX == 5 && box.height == 9)
        let offset = GlyphInkCentring.offset(box: box, columns: 9, rows: 9, pitch: 2)
        #expect(offset.x == 3)
        #expect(offset.y == 0)
    }

    @Test("The pitch fits the lit box inside the tile, in half points")
    func pitchFits() throws {
        let box = try #require(GlyphInkCentring.box(rows: MenuBarHand.handRows))
        for side in [24.0, 30, 36, 44, 96] {
            let pitch = GlyphInkCentring.pitch(fitting: box, in: side, margin: 4)
            #expect(Double(box.height) * pitch <= side - 8 + 1e-9, "side=\(side)")
            #expect((pitch * 2).rounded() == pitch * 2)
        }
    }
}

@Suite("Mac panel: Transfers tab (OR-13)")
struct TransferPanelPlanTests {
    typealias Plan = TransferPanelPlan
    typealias Item = TransferPanelPlan.Item

    /// Six files, three each way. One outgoing is cancelled, one incoming
    /// fails; the rest are under way at `t0 + 30 s`.
    static func sixFiles(cancelledAt: Date? = t0.addingTimeInterval(20), failedAt: Date? = t0.addingTimeInterval(25)) -> [Item] {
        let mb: UInt64 = 1_000_000
        return [
            Item(id: id(1), direction: .outgoing, outcome: .underWay, bytes: 50 * mb, totalBytes: 100 * mb, startedAt: t0),
            Item(id: id(2), direction: .outgoing, outcome: .underWay, bytes: 10 * mb, totalBytes: 100 * mb, startedAt: t0.addingTimeInterval(1)),
            Item(id: id(3), direction: .outgoing, outcome: .cancelled, bytes: 5 * mb, totalBytes: 100 * mb, startedAt: t0.addingTimeInterval(2), finishedAt: cancelledAt),
            Item(id: id(4), direction: .incoming, outcome: .underWay, bytes: 66 * mb, totalBytes: 100 * mb, startedAt: t0.addingTimeInterval(3)),
            Item(id: id(5), direction: .incoming, outcome: .underWay, bytes: 0, totalBytes: 100 * mb, startedAt: t0.addingTimeInterval(4)),
            Item(id: id(6), direction: .incoming, outcome: .failed, bytes: 40 * mb, totalBytes: 100 * mb, startedAt: t0.addingTimeInterval(5), finishedAt: failedAt),
        ]
    }

    @Test("Six files both ways, with a cancel and a failure: the tab, badge, summary and groups")
    func sixFileScenario() {
        let now = t0.addingTimeInterval(30)
        let items = Self.sixFiles()
        #expect(Plan.showsTab(items, at: now))
        #expect(Plan.badge(items, at: now) == 4)
        // 50 + 10 + 66 + 0 of 400 MB = 31.5 %, shown 31 %.
        #expect(Plan.summary(items, at: now) == "4 files moving · 31 %")

        let groups = Plan.groups(items, at: now)
        #expect(groups.map(\.group) == [.underWay, .finished])
        #expect(groups[0].items.map(\.id) == [id(5), id(4), id(2), id(1)])
        #expect(groups[1].items.map(\.id) == [id(6), id(3)])

        // The two still sending finish; the receiving ones too.
        let done = items.map { item -> Item in
            guard item.isUnderWay else { return item }
            return Item(id: item.id, direction: item.direction, outcome: .saved, bytes: item.totalBytes,
                        totalBytes: item.totalBytes, startedAt: item.startedAt, finishedAt: t0.addingTimeInterval(90))
        }
        let later = t0.addingTimeInterval(120)
        #expect(Plan.summary(done, at: later) == "4 saved · 1 cancelled · 1 failed")
        #expect(Plan.badge(done, at: later) == 6)
        #expect(Plan.groups(done, at: later).map(\.group) == [.finished])
        #expect(Plan.nextExpiry(done, at: later) == t0.addingTimeInterval(20 + 3600))

        // An hour after the cancel, it and the failure drop out; the rest an
        // hour after they finished; then the tab goes.
        let afterFirst = t0.addingTimeInterval(25 + 3600)
        #expect(Plan.listed(done, at: afterFirst).count == 4)
        #expect(Plan.summary(done, at: afterFirst) == "4 saved")
        let afterAll = t0.addingTimeInterval(90 + 3600)
        #expect(!Plan.showsTab(done, at: afterAll))
        #expect(Plan.badge(done, at: afterAll) == nil)
        #expect(Plan.summary(done, at: afterAll) == nil)
        #expect(Plan.nextExpiry(done, at: afterAll) == nil)
    }

    @Test("One direction says sending or receiving; one file is singular")
    func wording() {
        let mb: UInt64 = 1_000_000
        let out = [
            Item(id: id(1), direction: .outgoing, outcome: .underWay, bytes: 42 * mb, totalBytes: 100 * mb, startedAt: t0),
            Item(id: id(2), direction: .outgoing, outcome: .underWay, bytes: 42 * mb, totalBytes: 100 * mb, startedAt: t0),
            Item(id: id(3), direction: .outgoing, outcome: .underWay, bytes: 42 * mb, totalBytes: 100 * mb, startedAt: t0),
        ]
        #expect(Plan.summary(out, at: t0) == "3 files sending · 42 %")
        let one = [Item(id: id(4), direction: .incoming, outcome: .underWay, bytes: 8, totalBytes: 100, startedAt: t0)]
        #expect(Plan.summary(one, at: t0) == "1 file receiving · 8 %")
        // Sizes unknown: no percent.
        let unknown = [Item(id: id(5), direction: .incoming, outcome: .underWay, bytes: 0, totalBytes: 0, startedAt: t0)]
        #expect(Plan.summary(unknown, at: t0) == "1 file receiving")
    }

    @Test("Percent rounds down, so it never reads 100 % before the end")
    func percent() {
        #expect(Plan.percent(0.999) == 99)
        #expect(Plan.percent(1) == 100)
        #expect(Plan.percent(0) == 0)
    }

    @Test("A waiting Accept shows the tab and counts in the badge")
    func prompts() {
        #expect(Plan.showsTab([], waitingPrompts: 1, at: t0))
        #expect(Plan.badge([], waitingPrompts: 1, at: t0) == 1)
        #expect(Plan.summary([], waitingPrompts: 1, at: t0) == "1 waiting for you")
        #expect(!Plan.showsTab([], at: t0))
        #expect(Plan.summary([], at: t0) == nil)
    }

    @Test("A finished item with no end time stays listed until cleared")
    func noEndTime() {
        let item = Item(id: id(1), direction: .incoming, outcome: .saved, bytes: 1, totalBytes: 1, startedAt: t0)
        #expect(Plan.listed([item], at: t0.addingTimeInterval(10_000)).count == 1)
    }

    @Test("Statuses map to outcomes: a cancel is its own outcome")
    func outcomes() {
        #expect(Plan.outcome(status: nil, isActive: true) == .underWay)
        #expect(Plan.outcome(status: .awaitingApproval, isActive: true) == .underWay)
        #expect(Plan.outcome(status: .awaitingApproval, isActive: false) == .failed)
        #expect(Plan.outcome(status: nil, isActive: false) == .saved)
        #expect(Plan.outcome(status: .saved(landing: .downloads), isActive: false) == .saved)
        #expect(Plan.outcome(status: .failed(reason: .cancelled), isActive: false) == .cancelled)
        #expect(Plan.outcome(status: .failed(reason: .interrupted), isActive: false) == .failed)
        #expect(Plan.outcome(status: .refused(reason: .declined), isActive: false) == .failed)
    }
}
