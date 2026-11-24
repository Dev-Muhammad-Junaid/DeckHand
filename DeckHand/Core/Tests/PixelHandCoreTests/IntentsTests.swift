//
//  IntentsTests.swift
//  PixelHandCoreTests
//
//  D6 App Intents: command gating and mapping, the pending queue, the
//  widget snapshot and recent Macs.
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("Remote commands")
struct RemoteCommandTests {
    private let free = Entitlement(status: .unknown, evaluatedAt: Date(timeIntervalSince1970: 0))

    @Test("Typing, system actions, media keys and opening the trackpad are free")
    func freeCommands() {
        let freeOnes: [RemoteCommand] = [
            .typeText("hi"), .media(.playPause), .open(.trackpad),
        ] + SystemCommand.allCases.map { .system($0) }
        for command in freeOnes {
            #expect(command.feature.tier == .free, "\(command.kindName)")
            #expect(command.isAllowed(by: free), "\(command.kindName)")
        }
    }

    @Test("Deck keys, screenshots and the mirror need Pro")
    func proCommands() {
        let pro: [RemoteCommand] = [.runKey(keyID: "k"), .screenshot, .mirror(.start), .mirror(.stop), .mirror(.toggle)]
        for command in pro {
            #expect(command.feature.tier == .pro, "\(command.kindName)")
            #expect(!command.isAllowed(by: free), "\(command.kindName)")
        }
    }

    @Test("System commands map onto existing actions; Lock Screen is ⌃⌘Q")
    func systemActions() {
        #expect(SystemCommand.missionControl.action == .system(action: .missionControl))
        #expect(SystemCommand.showDesktop.action == .system(action: .showDesktop))
        #expect(SystemCommand.lockScreen.action == .shortcut(keys: ["ctrl", "cmd", "q"]))
        #expect(RemoteCommand.system(.launchpad).action == .system(action: .launchpad))
        #expect(RemoteCommand.media(.next).action == .media(key: .next))
        #expect(RemoteCommand.typeText("x").action == nil)
    }

    @Test("Every system action passes the Mac's input validation")
    func systemActionsAreAcceptable() {
        for command in SystemCommand.allCases {
            #expect(RemoteInputValidation.isAcceptable(command.action), "\(command)")
        }
    }

    @Test("Every system glyph is in the pixel set")
    func glyphsExist() {
        for command in SystemCommand.allCases {
            #expect(PixelGlyphs.named(command.glyphName) != nil, "\(command.glyphName)")
        }
    }

    @Test("Typed text and key IDs are bounded")
    func validation() {
        #expect(RemoteCommand.typeText("").validationIssue == .emptyText)
        #expect(RemoteCommand.typeText(String(repeating: "a", count: RemoteCommandLimits.maxTypedCharacters)).validationIssue == nil)
        #expect(RemoteCommand.typeText(String(repeating: "a", count: RemoteCommandLimits.maxTypedCharacters + 1)).validationIssue == .textTooLong)
        #expect(RemoteCommand.runKey(keyID: "").validationIssue == .badKeyID)
        #expect(RemoteCommand.runKey(keyID: String(repeating: "k", count: 513)).validationIssue == .badKeyID)
        #expect(RemoteCommand.runKey(keyID: "home.1").validationIssue == nil)
    }

    @Test("Log names never carry typed text")
    func kindNameIsPayloadFree() {
        #expect(RemoteCommand.typeText("secret password").kindName == "typeText")
        #expect(RemoteCommand.runKey(keyID: "abc").kindName == "runKey")
    }

    @Test("Mirror modes toggle only when needed")
    func mirrorModes() {
        #expect(MirrorIntentMode.start.shouldToggle(isRunning: false))
        #expect(!MirrorIntentMode.start.shouldToggle(isRunning: true))
        #expect(MirrorIntentMode.stop.shouldToggle(isRunning: true))
        #expect(!MirrorIntentMode.stop.shouldToggle(isRunning: false))
        #expect(MirrorIntentMode.toggle.shouldToggle(isRunning: true))
        #expect(MirrorIntentMode.toggle.shouldToggle(isRunning: false))
    }

    @Test("Commands round-trip through JSON")
    func coding() throws {
        let all: [RemoteCommand] = [
            .runKey(keyID: "k1"), .system(.lockScreen), .media(.previous), .typeText("héllo ✓"),
            .screenshot, .mirror(.toggle), .open(.trackpad),
        ]
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode([RemoteCommand].self, from: data) == all)
    }
}

@Suite("Pending command queue")
struct PendingCommandQueueTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("Drains in order for any Mac and empties")
    func drainOrder() {
        var queue = PendingCommandQueue()
        queue.enqueue(PendingCommand(command: .system(.missionControl), queuedAt: t0), now: t0)
        queue.enqueue(PendingCommand(command: .media(.next), queuedAt: t0 + 1), now: t0 + 1)
        let ready = queue.drain(forMac: "mac-a", now: t0 + 2)
        #expect(ready.map(\.command) == [.system(.missionControl), .media(.next)])
        #expect(queue.isEmpty)
    }

    @Test("Expired commands are dropped, not run late")
    func expiry() {
        var queue = PendingCommandQueue()
        queue.enqueue(PendingCommand(command: .system(.lockScreen), queuedAt: t0), now: t0)
        let ready = queue.drain(forMac: nil, now: t0 + PendingCommandQueue.lifetime + 1)
        #expect(ready.isEmpty)
        #expect(queue.isEmpty)
    }

    @Test("A command for another Mac waits")
    func otherMac() {
        var queue = PendingCommandQueue()
        queue.enqueue(PendingCommand(command: .screenshot, macID: "mac-b", queuedAt: t0), now: t0)
        let forA = queue.drain(forMac: "mac-a", now: t0 + 1)
        #expect(forA.isEmpty)
        let forB = queue.drain(forMac: "mac-b", now: t0 + 2)
        #expect(forB.map(\.command) == [.screenshot])
    }

    @Test("Capacity keeps the newest; invalid commands are refused")
    func capacity() {
        var queue = PendingCommandQueue()
        for i in 0..<(PendingCommandQueue.capacity + 3) {
            queue.enqueue(PendingCommand(command: .runKey(keyID: "k\(i)"), queuedAt: t0), now: t0)
        }
        #expect(queue.items.count == PendingCommandQueue.capacity)
        #expect(queue.items.first?.command == .runKey(keyID: "k3"))
        let accepted = queue.enqueue(PendingCommand(command: .typeText(""), queuedAt: t0), now: t0)
        #expect(!accepted)
    }

    @Test("A command dated in the future is dropped")
    func futureDate() {
        var queue = PendingCommandQueue()
        queue.enqueue(PendingCommand(command: .screenshot, queuedAt: t0 + 3600), now: t0)
        let ready = queue.drain(forMac: nil, now: t0)
        #expect(ready.isEmpty)
    }

    @Test("Round-trips; damaged data is an empty queue")
    func coding() throws {
        var queue = PendingCommandQueue()
        queue.enqueue(PendingCommand(command: .typeText("abc"), macID: "m", queuedAt: t0), now: t0)
        let data = try PendingCommandQueue.encode(queue)
        #expect(PendingCommandQueue.decode(data) == queue)
        #expect(PendingCommandQueue.decode(Data("nope".utf8)).isEmpty)
        #expect(PendingCommandQueue.decode(nil).isEmpty)
    }
}

@Suite("Widget deck snapshot")
struct WidgetDeckSnapshotTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func key(_ id: String, _ label: String, _ action: Action = .shortcut(keys: ["cmd", "s"]), pinned: Bool = false, glyph: KeyGlyph? = nil) -> DeckKey {
        DeckKey(id: id, appearance: KeyAppearance(label: label, glyph: glyph), action: action, pinnedToFirstRow: pinned)
    }

    private var document: DeckDocument {
        DeckDocument(pages: [
            DeckPage(id: "home", title: "Home", kind: .home, keys: [
                key("h1", "Save"),
                key("h2", "Play", .media(key: .playPause)),
                key("h3", "Mission", .system(action: .missionControl), pinned: true),
                key("h4", "Dialog", .contextAction(id: "ok")),
            ]),
            DeckPage(id: "app.com.apple.Safari", title: "Safari", kind: .app(bundleID: "com.apple.Safari"), keys: [
                key("s1", "New Tab"),
            ]),
            DeckPage(id: "c", title: "Studio", kind: .custom, keys: [
                key("c1", "Build", .macShortcut(name: "Build")),
                DeckKey(id: "c2", appearance: KeyAppearance(label: "Quit"), action: .shortcut(keys: ["cmd", "q"]), confirm: true),
            ]),
        ])
    }

    @Test("Widget keys: Home pins first, then Home, then custom pages; no app pages, confirm keys or dialog presses")
    func widgetOrder() {
        let snapshot = WidgetDeckSnapshot.make(from: document, macs: [], isPro: true, now: now)
        #expect(snapshot.widgetKeys.map(\.id) == ["h3", "h1", "h2", "c1"])
        #expect(snapshot.allKeys.map(\.id) == ["h1", "h2", "h3", "s1", "c1", "c2"])
        #expect(snapshot.key(id: "c2")?.confirm == true)
        #expect(snapshot.key(id: "s1")?.pageTitle == "Safari")
        #expect(snapshot.key(id: "h4") == nil)
    }

    @Test("At most eight widget keys")
    func widgetCap() {
        let keys = (0..<20).map { key("k\($0)", "Key \($0)") }
        let doc = DeckDocument(pages: [DeckPage(id: "home", title: "Home", kind: .home, keys: keys)])
        let snapshot = WidgetDeckSnapshot.make(from: doc, macs: [], isPro: false, now: now)
        #expect(snapshot.widgetKeys.count == WidgetDeckSnapshot.maxWidgetKeys)
        #expect(snapshot.allKeys.count == 20)
    }

    @Test("Glyphs: own pixel glyph, else by action, else a monogram")
    func glyphs() {
        #expect(WidgetGlyph.resolve(.pixel(id: "lock"), action: .shortcut(keys: ["a"]), label: "x") == .pixel(name: "lock"))
        #expect(WidgetGlyph.resolve(.pixel(id: "no-such"), action: .system(action: .showDesktop), label: "x") == .pixel(name: "desktop"))
        #expect(WidgetGlyph.resolve(.symbol(name: "star"), action: .shortcut(keys: ["a"]), label: "x") == .symbol(name: "star"))
        #expect(WidgetGlyph.resolve(.appIcon(bundleID: "com.apple.Safari"), action: .launchApp(bundleID: "com.apple.Safari"), label: "Open Safari") == .monogram("OS"))
        #expect(WidgetGlyph.resolve(nil, action: .media(key: .playPause), label: "x") == .pixel(name: "play"))
        let bitmap = PixelGlyphData.blank(size: 9)
        #expect(WidgetGlyph.resolve(.custom(bitmap: bitmap), action: .shortcut(keys: ["a"]), label: "Zip") == .bitmap(bitmap))
    }

    @Test("Every action fallback glyph is in the pixel set")
    func fallbackGlyphsExist() {
        let actions: [Action] = SystemMacro.allCases.map { .system(action: $0) }
            + MediaKey.allCases.map { .media(key: $0) }
            + [.macShortcut(name: "a"), .sequence(steps: [.delay(milliseconds: 1)]), .menuCommand(bundleID: "a", path: ["File"])]
        for action in actions {
            if case let .pixel(name) = WidgetGlyph.resolve(nil, action: action, label: "x") {
                #expect(PixelGlyphs.named(name) != nil, "\(name)")
            } else {
                Issue.record("\(action.kindName) has no pixel glyph")
            }
        }
    }

    @Test("Monograms use letters the dot-matrix font has")
    func monograms() {
        #expect(WidgetGlyph.monogram(for: "Save") == "SA")
        #expect(WidgetGlyph.monogram(for: "new tab") == "NT")
        #expect(WidgetGlyph.monogram(for: "✓✓") == "?")
        #expect(WidgetGlyph.monogram(for: "") == "?")
        for character in WidgetGlyph.monogram(for: "Xcode Build") {
            #expect(DotMatrixFont.characters.contains(character))
        }
    }

    @Test("Round-trips; damaged or newer data reads as empty")
    func coding() throws {
        let macs = [RecentMac(id: "A", name: "Studio", lastConnected: now)]
        let snapshot = WidgetDeckSnapshot.make(from: document, macs: macs, isPro: true, now: now)
        let data = try WidgetDeckSnapshot.encode(snapshot)
        #expect(WidgetDeckSnapshot.decode(data) == snapshot)
        #expect(WidgetDeckSnapshot.decode(Data("{".utf8)) == .empty)
        var newer = snapshot
        newer.version = WidgetDeckSnapshot.currentVersion + 1
        #expect(WidgetDeckSnapshot.decode(try WidgetDeckSnapshot.encode(newer)) == .empty)
        #expect(WidgetDeckSnapshot.decode(nil).currentMac == nil)
    }

    @Test("Key search ignores case and diacritics and matches page titles")
    func search() {
        let snapshot = WidgetDeckSnapshot.make(from: document, macs: [], isPro: true, now: now)
        #expect(snapshot.keys(matching: "save").map(\.id) == ["h1"])
        #expect(snapshot.keys(matching: "SAFARI").map(\.id) == ["s1"])
        #expect(snapshot.keys(matching: "  ").count == snapshot.allKeys.count)
    }

    @Test("Recent Macs: most recent first, deduped, capped, blank names ignored")
    func recentMacs() {
        var macs: [RecentMac] = []
        for i in 0..<10 {
            macs = RecentMac.recording(RecentMac(id: "m\(i)", name: "Mac \(i)", lastConnected: now), in: macs)
        }
        #expect(macs.count == RecentMac.maxRemembered)
        #expect(macs.first?.id == "m9")
        macs = RecentMac.recording(RecentMac(id: "m5", name: " Studio ", lastConnected: now), in: macs)
        #expect(macs.first?.name == "Studio")
        #expect(macs.filter { $0.id == "m5" }.count == 1)
        #expect(RecentMac.recording(RecentMac(id: "x", name: "  ", lastConnected: now), in: macs) == macs)
    }
}
