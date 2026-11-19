//
//  ProtocolContractTests.swift
//  PixelHandCoreTests
//
//  The wire contract between the Mac and every remote. The golden fixtures
//  in `Fixtures/protocol/` are the contract: both apps compile the same
//  Core sources, so they can't drift at build time, but a renamed key or a
//  changed raw value would silently break a Mac and a remote on different
//  builds. These tests pin the format:
//
//  1. Every case has a sample, and every sample encodes to exactly its
//     fixture's bytes and decodes back to an equal value.
//  2. The fixture set is pinned by `MANIFEST` to the protocol version, so a
//     format change can't land without a version bump (see Core/PROTOCOL.md).
//  3. The envelope rejects other versions, unknown or multiple domains, and
//     oversize input.
//
//  To add a message: add the case in its domain file, add it to
//  `caseName(_:)` (the compiler makes you) and `samples`, bump
//  `PixelHandProtocol.version` and Core/PROTOCOL.md, then record:
//
//      PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests
//
//  and review the new JSON files in the diff.
//

import Foundation
import PixelHandCore
import Testing

@Suite(.serialized) struct ProtocolContractTests {

    // MARK: - Samples: at least one per case

    static let samples: [(name: String, message: ControlMessage)] = [
        // input
        ("input.mouseDelta", .input(.mouseDelta(dx: 1.5, dy: -2.25))),
        ("input.mouseScroll", .input(.mouseScroll(dx: 0.5, dy: 12, phase: .begin))),
        ("input.mouseScroll.momentumEnd", .input(.mouseScroll(dx: 0, dy: 0, phase: .momentumEnd))),
        ("input.mouseClick", .input(.mouseClick(button: .left))),
        ("input.mouseDoubleClick", .input(.mouseDoubleClick(button: .right))),
        ("input.keyboardShortcut", .input(.keyboardShortcut(keys: ["cmd", "shift", "p"]))),
        ("input.media", .input(.media(key: .playPause))),
        ("input.mouseDown", .input(.mouseDown(button: .left))),
        ("input.mouseUp", .input(.mouseUp(button: .left))),
        ("input.typeText", .input(.typeText(text: "Héllo, 世界 👋🏽\n"))),
        // system
        ("system.run", .system(.run(action: .showDesktop))),
        ("system.switchSpace", .system(.switchSpace(direction: .next, displayID: nil))),
        ("system.switchSpace.display", .system(.switchSpace(direction: .missionControl, displayID: 1))),
        ("system.displayState", .system(.displayState(layout: DisplayLayout(
            displays: [
                DisplaySpaces(
                    displayID: 2,
                    name: "HP E273",
                    isMain: true,
                    bounds: DisplayBounds(x: 0, y: 0, width: 1920, height: 1080),
                    spaces: [.desktop],
                    currentSpaceIndex: 0
                ),
                DisplaySpaces(
                    displayID: 1,
                    name: "Built-in Retina Display",
                    isMain: false,
                    bounds: DisplayBounds(x: -1728, y: 0, width: 1728, height: 1117),
                    spaces: [.desktop, .desktop, SpaceInfo(kind: .fullScreen, appName: "Safari")],
                    currentSpaceIndex: 1
                ),
            ],
            cursorDisplayID: 1,
            spacesKnown: true,
            separateSpaces: true
        )))),
        ("system.displayState.noSpaces", .system(.displayState(layout: DisplayLayout(
            displays: [
                DisplaySpaces(
                    displayID: 1,
                    name: "Built-in Retina Display",
                    isMain: true,
                    bounds: DisplayBounds(x: 0, y: 0, width: 1512, height: 982),
                    spaces: nil,
                    currentSpaceIndex: nil
                ),
            ],
            cursorDisplayID: nil,
            spacesKnown: false,
            separateSpaces: true
        )))),
        ("system.lockState", .system(.lockState(state: .screenLocked))),
        ("system.lockState.offConsole", .system(.lockState(state: .offConsole))),
        // apps
        ("apps.launchApp", .apps(.launchApp(bundleID: "com.apple.Safari"))),
        ("apps.appShortcut", .apps(.appShortcut(bundleID: "com.todesktop.230313mzl4w4u92", keys: ["cmd", "k"]))),
        ("apps.requestAppList", .apps(.requestAppList)),
        ("apps.triggerContextAction", .apps(.triggerContextAction(id: "00deadbeef00cafe|2|Save"))),
        ("apps.appListResponse", .apps(.appListResponse(apps: [
            InstalledAppInfo(bundleID: "com.apple.dt.Xcode", displayName: "Xcode", iconData: nil),
            InstalledAppInfo(bundleID: "com.apple.mail", displayName: "Mail", iconData: Data([0x01, 0x02])),
        ]))),
        ("apps.runningAppsUpdate", .apps(.runningAppsUpdate(bundleIDs: ["com.apple.Safari", "com.apple.mail"]))),
        ("apps.activeAppUpdate", .apps(.activeAppUpdate(name: "Safari", bundleID: "com.apple.Safari"))),
        ("apps.activeAppUpdate.noBundleID", .apps(.activeAppUpdate(name: "Mystery", bundleID: nil))),
        ("apps.uiContextUpdate.none", .apps(.uiContextUpdate(snapshot: .none))),
        ("apps.uiContextUpdate", .apps(.uiContextUpdate(snapshot: .dialog(DialogContext(
            revision: "00deadbeef00cafe",
            title: "Unsaved Changes",
            message: "Do you want to save?",
            buttons: [
                DialogButton(id: "00deadbeef00cafe|0|Don't Save", title: "Don't Save", isDefault: false, isCancel: false),
                DialogButton(id: "00deadbeef00cafe|1|Cancel", title: "Cancel", isDefault: false, isCancel: true),
                DialogButton(id: "00deadbeef00cafe|2|Save", title: "Save", isDefault: true, isCancel: false),
            ]
        ))))),
        ("apps.uiContextUpdate.textField", .apps(.uiContextUpdate(snapshot: .textField(TextFieldContext(kind: .numeric))))),
        // deck
        ("deck.requestAppMenuShortcuts", .deck(.requestAppMenuShortcuts(bundleID: "com.apple.Safari"))),
        ("deck.appMenuShortcutsResponse", .deck(.appMenuShortcutsResponse(bundleID: "com.apple.Safari", shortcuts: [
            AppShortcutBinding(
                id: "imported.com.apple.Safari.File>New Tab",
                bundleID: "com.apple.Safari",
                displayName: "File › New Tab",
                keys: ["cmd", "t"],
                sfSymbol: "plus.square.on.square",
                isCurated: false,
                category: "File"
            ),
        ]))),
        ("deck.run", .deck(.run(requestID: "cmd-1", action: .appShortcut(bundleID: "com.apple.dt.Xcode", keys: ["cmd", "b"])))),
        ("deck.run.contextAction", .deck(.run(requestID: "cmd-2", action: .contextAction(id: "00deadbeef00cafe|2|Save")))),
        ("deck.run.shortcut", .deck(.run(requestID: "cmd-3", action: .shortcut(keys: ["cmd", "c"])))),
        ("deck.run.launchApp", .deck(.run(requestID: "cmd-4", action: .launchApp(bundleID: "com.apple.Terminal")))),
        ("deck.run.system", .deck(.run(requestID: "cmd-5", action: .system(action: .missionControl)))),
        ("deck.run.media", .deck(.run(requestID: "cmd-6", action: .media(key: .next)))),
        ("deck.receipt", .deck(.receipt(requestID: "cmd-1", outcome: .delivered))),
        ("deck.receipt.refused", .deck(.receipt(requestID: "cmd-2", outcome: .refused(reason: .staleContext)))),
        ("deck.receipt.refused.macLocked", .deck(.receipt(requestID: "cmd-7", outcome: .refused(reason: .macLocked)))),
        ("deck.receipt.failed", .deck(.receipt(requestID: "cmd-3", outcome: .failed(reason: "App not running")))),
        ("deck.receipt.completed", .deck(.receipt(requestID: "cmd-4", outcome: .completed))),
        // mirror
        ("mirror.start", .mirror(.start(fps: 20, maxWidth: 480, displayID: nil, codec: .jpeg, windowID: nil))),
        ("mirror.start.display", .mirror(.start(fps: 20, maxWidth: 480, displayID: 1, codec: .jpeg, windowID: nil))),
        ("mirror.start.hevc", .mirror(.start(fps: 30, maxWidth: 1440, displayID: 2, codec: .hevc, windowID: nil))),
        ("mirror.start.window", .mirror(.start(fps: 20, maxWidth: 960, displayID: 1, codec: .hevc, windowID: 4242))),
        ("mirror.requestKeyFrame", .mirror(.requestKeyFrame)),
        ("mirror.stop", .mirror(.stop)),
        ("mirror.moveCursor", .mirror(.moveCursor(displayID: 2))),
        ("mirror.displayList", .mirror(.displayList(
            displays: [
                DisplayInfo(displayID: 1, name: "Built-in Retina Display", isMain: true, width: 1728, height: 1117),
                DisplayInfo(displayID: 2, name: "Studio Display", isMain: false, width: 5120, height: 2880),
            ],
            selectedDisplayID: 2,
            window: nil
        ))),
        ("mirror.displayList.window", .mirror(.displayList(
            displays: [
                DisplayInfo(displayID: 1, name: "Built-in Retina Display", isMain: true, width: 1728, height: 1117),
            ],
            selectedDisplayID: 1,
            window: MirroredWindow(windowID: 4242, title: "Pixel Hand — Notes", appName: "Notes", width: 900, height: 640)
        ))),
        ("mirror.error", .mirror(.error(message: "Screen Recording is off", fallbackDisplayID: nil))),
        ("mirror.error.windowFallback", .mirror(.error(message: "The Notes window closed. Showing its display instead.", fallbackDisplayID: 1))),
        ("mirror.audio", .mirror(.audio(enabled: true))),
        ("mirror.audio.off", .mirror(.audio(enabled: false))),
        ("mirror.audioError", .mirror(.audioError(message: "The Mac's sound couldn't be captured."))),
        // capture
        ("capture.requestScreenshot", .capture(.requestScreenshot(requestID: "req-1", mode: .fullScreen, quality: .standard))),
        ("capture.requestScreenshot.region", .capture(.requestScreenshot(
            requestID: "req-2",
            mode: .region(x: 0.125, y: 0.25, width: 0.5, height: 0.25),
            quality: .standard
        ))),
        ("capture.requestScreenshot.window", .capture(.requestScreenshot(requestID: "req-3", mode: .window(windowID: 4242), quality: .high))),
        ("capture.requestScreenshot.native", .capture(.requestScreenshot(requestID: "req-4", mode: .fullScreen, quality: .native))),
        ("capture.requestWindowList", .capture(.requestWindowList(requestID: "wl-1"))),
        ("capture.screenshotData", .capture(.screenshotData(requestID: "req-1", data: Data([0xFF, 0xD8, 0xFF])))),
        ("capture.screenshotError", .capture(.screenshotError(requestID: "req-1", message: "TCC denied"))),
        ("capture.windowListResponse", .capture(.windowListResponse(requestID: "wl-1", windows: [
            WindowInfo(windowID: 7, title: "Inbox", appName: "Mail", bundleID: "com.apple.mail", appIconData: nil),
            WindowInfo(windowID: 9, title: "", appName: "Ghost", bundleID: nil, appIconData: Data([0x01])),
        ]))),
        // pairing
        ("pairing.authorizationStatus", .pairing(.authorizationStatus(state: .granted))),
        ("pairing.authorizationStatus.pending", .pairing(.authorizationStatus(state: .pending))),
        ("pairing.authorizationStatus.denied", .pairing(.authorizationStatus(state: .denied))),
        ("pairing.requestAuthorizationStatus", .pairing(.requestAuthorizationStatus)),
        ("pairing.submitCode", .pairing(.submitCode(code: "5724125"))),
        ("pairing.codeResult", .pairing(.codeResult(result: .accepted))),
        ("pairing.codeResult.wrongCode", .pairing(.codeResult(result: .wrongCode(attemptsLeft: 3)))),
        ("pairing.codeResult.lockedOut", .pairing(.codeResult(result: .lockedOut(retryAfter: 60)))),
        ("pairing.codeResult.expired", .pairing(.codeResult(result: .expired))),
        ("pairing.codeResult.noActiveCode", .pairing(.codeResult(result: .noActiveCode))),
        ("pairing.pairedStatus", .pairing(.pairedStatus(paired: true))),
        ("pairing.pairedStatus.false", .pairing(.pairedStatus(paired: false))),
        ("pairing.forget", .pairing(.forget)),
        // session
        ("session.ping", .session(.ping(seq: 7))),
        ("session.pong", .session(.pong(seq: 7))),
        ("session.tick", .session(.tick)),
        ("session.link", .session(.link(kind: .wired))),
        ("session.link.wifi", .session(.link(kind: .wifi))),
        ("session.remoteHosts", .session(.remoteHosts(hosts: ["100.101.102.103", "fd7a:115c:a1e0::1"]))),
        ("session.remoteHosts.empty", .session(.remoteHosts(hosts: []))),
        ("session.hostStatus", .session(.hostStatus(status: HostStatus(
            accessibility: true,
            screenRecording: false,
            features: [.commandReceipts]
        )))),
        ("session.hostStatus.binaryMirror", .session(.hostStatus(status: HostStatus(
            accessibility: true,
            screenRecording: true,
            features: [.binaryMirrorStream, .commandReceipts]
        )))),
        // sharing
        ("sharing.clipboardSync", .sharing(.clipboardSync(enabled: true))),
        ("sharing.setClipboard", .sharing(.setClipboard(text: "Copied on the iPad", paste: true))),
        ("sharing.macClipboard", .sharing(.macClipboard(text: "Copied on the Mac"))),
        // diagnostics
        ("diagnostics.mirrorStats", .diagnostics(.mirrorStats(stats: MirrorHostStats(
            codec: .jpeg,
            width: 1440,
            height: 900,
            capturedFPS: 20,
            sentFPS: 19.5,
            droppedFrames: 3,
            encodeMilliseconds: 6.25,
            kilobitsPerSecond: 1250.5
        )))),
        ("diagnostics.mirrorStats.audio", .diagnostics(.mirrorStats(stats: MirrorHostStats(
            codec: .hevc,
            width: 1440,
            height: 900,
            capturedFPS: 30,
            sentFPS: 30,
            droppedFrames: 0,
            encodeMilliseconds: 3.5,
            kilobitsPerSecond: 4200,
            audio: MirrorAudioHostStats(codec: .aacLC, packetsSent: 47, packetsDropped: 1, kilobitsPerSecond: 131.5)
        )))),
        ("diagnostics.mirrorClientStats", .diagnostics(.mirrorClientStats(stats: MirrorClientStats(
            receivedFPS: 19.5,
            displayedFPS: 19,
            droppedFrames: 1,
            decodeMilliseconds: 4.5,
            kilobitsPerSecond: 1250.5
        )))),
        ("diagnostics.mirrorClientStats.audio", .diagnostics(.mirrorClientStats(stats: MirrorClientStats(
            receivedFPS: 30,
            displayedFPS: 29.5,
            droppedFrames: 0,
            decodeMilliseconds: 2.5,
            kilobitsPerSecond: 4200,
            audio: MirrorAudioClientStats(
                packetsReceived: 46,
                packetsLost: 1,
                packetsLate: 2,
                underruns: 1,
                bufferMilliseconds: 64.5,
                targetMilliseconds: 60,
                jitterMilliseconds: 4.5
            )
        )))),
    ]

    /// Every case's name. The switches have no `default`, so adding a case
    /// to a domain doesn't compile until it is named here.
    static func caseName(_ message: ControlMessage) -> String {
        return switch message {
        case let .input(m):
            switch m {
            case .mouseDelta: "input.mouseDelta"
            case .mouseScroll: "input.mouseScroll"
            case .mouseClick: "input.mouseClick"
            case .mouseDoubleClick: "input.mouseDoubleClick"
            case .keyboardShortcut: "input.keyboardShortcut"
            case .media: "input.media"
            case .mouseDown: "input.mouseDown"
            case .mouseUp: "input.mouseUp"
            case .typeText: "input.typeText"
            }
        case let .system(m):
            switch m {
            case .run: "system.run"
            case .switchSpace: "system.switchSpace"
            case .displayState: "system.displayState"
            case .lockState: "system.lockState"
            }
        case let .apps(m):
            switch m {
            case .launchApp: "apps.launchApp"
            case .appShortcut: "apps.appShortcut"
            case .requestAppList: "apps.requestAppList"
            case .triggerContextAction: "apps.triggerContextAction"
            case .appListResponse: "apps.appListResponse"
            case .runningAppsUpdate: "apps.runningAppsUpdate"
            case .activeAppUpdate: "apps.activeAppUpdate"
            case .uiContextUpdate: "apps.uiContextUpdate"
            }
        case let .deck(m):
            switch m {
            case .requestAppMenuShortcuts: "deck.requestAppMenuShortcuts"
            case .run: "deck.run"
            case .appMenuShortcutsResponse: "deck.appMenuShortcutsResponse"
            case .receipt: "deck.receipt"
            }
        case let .mirror(m):
            switch m {
            case .start: "mirror.start"
            case .stop: "mirror.stop"
            case .moveCursor: "mirror.moveCursor"
            case .requestKeyFrame: "mirror.requestKeyFrame"
            case .displayList: "mirror.displayList"
            case .error: "mirror.error"
            case .audio: "mirror.audio"
            case .audioError: "mirror.audioError"
            }
        case let .capture(m):
            switch m {
            case .requestScreenshot: "capture.requestScreenshot"
            case .requestWindowList: "capture.requestWindowList"
            case .screenshotData: "capture.screenshotData"
            case .screenshotError: "capture.screenshotError"
            case .windowListResponse: "capture.windowListResponse"
            }
        case let .pairing(m):
            switch m {
            case .authorizationStatus: "pairing.authorizationStatus"
            case .requestAuthorizationStatus: "pairing.requestAuthorizationStatus"
            case .submitCode: "pairing.submitCode"
            case .codeResult: "pairing.codeResult"
            case .pairedStatus: "pairing.pairedStatus"
            case .forget: "pairing.forget"
            }
        case let .session(m):
            switch m {
            case .ping: "session.ping"
            case .pong: "session.pong"
            case .hostStatus: "session.hostStatus"
            case .tick: "session.tick"
            case .link: "session.link"
            case .remoteHosts: "session.remoteHosts"
            }
        case let .sharing(m):
            switch m {
            case .clipboardSync: "sharing.clipboardSync"
            case .setClipboard: "sharing.setClipboard"
            case .macClipboard: "sharing.macClipboard"
            }
        case let .diagnostics(m):
            switch m {
            case .mirrorStats: "diagnostics.mirrorStats"
            case .mirrorClientStats: "diagnostics.mirrorClientStats"
            }
        }
    }

    /// Cases in protocol version 11. Bump with every added or removed case.
    static let expectedCaseCount = 55

    /// The current version, for the hand-written JSON below.
    static let v = PixelHandProtocol.version

    // MARK: - Fixture plumbing

    static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/protocol", isDirectory: true)

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["PH_RECORD_FIXTURES"] == "1"
    }

    static func fixtureURL(_ name: String) -> URL {
        fixturesDirectory.appendingPathComponent(name + ".json")
    }

    static func fixtureNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: fixturesDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    /// FNV-1a over every fixture's name and bytes, in name order. Any change
    /// to the fixture set changes it.
    static func fixtureDigest() throws -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ bytes: some Sequence<UInt8>) {
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        for name in try fixtureNames() {
            mix(Array(name.utf8))
            mix([0])
            mix(try Data(contentsOf: fixtureURL(name)))
            mix([0])
        }
        return String(hash, radix: 16)
    }

    static let manifestURL = fixturesDirectory.appendingPathComponent("MANIFEST")

    static func manifestText(digest: String) -> String {
        """
        # Golden fixture manifest. Written by ProtocolContractTests when
        # recording; see Core/PROTOCOL.md. Changing any fixture changes the
        # digest, and the version must match PixelHandProtocol.version.
        version \(PixelHandProtocol.version)
        digest \(digest)

        """
    }

    // MARK: - 1. Every case: sample, fixture, round trip

    @Test("Every case has a sample, and the case count is pinned")
    func everyCaseHasASample() {
        let covered = Set(Self.samples.map { Self.caseName($0.message) })
        #expect(covered.count == Self.expectedCaseCount, "covered: \(covered.sorted())")
        let names = Self.samples.map(\.name)
        #expect(Set(names).count == names.count, "duplicate sample names")
        for sample in Self.samples {
            #expect(sample.name.hasPrefix(Self.caseName(sample.message)), "\(sample.name)")
        }
    }

    @Test("Every sample encodes to its golden fixture and decodes back equal")
    func samplesMatchGoldenFixtures() throws {
        if Self.isRecording {
            try FileManager.default.createDirectory(at: Self.fixturesDirectory, withIntermediateDirectories: true)
            for name in try Self.fixtureNames() {
                try FileManager.default.removeItem(at: Self.fixtureURL(name))
            }
            for sample in Self.samples {
                try ControlMessageCoding.encode(sample.message).write(to: Self.fixtureURL(sample.name))
            }
            try Self.manifestText(digest: Self.fixtureDigest())
                .write(to: Self.manifestURL, atomically: true, encoding: .utf8)
        }
        for sample in Self.samples {
            let fixture = try Data(contentsOf: Self.fixtureURL(sample.name))
            let encoded = try ControlMessageCoding.encode(sample.message)
            #expect(
                encoded == fixture,
                "\(sample.name): encoded \(String(decoding: encoded, as: UTF8.self)), fixture \(String(decoding: fixture, as: UTF8.self))"
            )
            #expect(try ControlMessageCoding.decode(fixture) == sample.message, "\(sample.name)")
        }
    }

    @Test("Every fixture file belongs to a sample")
    func noOrphanFixtures() throws {
        let fixtures = Set(try Self.fixtureNames())
        let samples = Set(Self.samples.map(\.name))
        #expect(fixtures == samples, "orphans: \(fixtures.subtracting(samples).sorted()), missing: \(samples.subtracting(fixtures).sorted())")
    }

    @Test("The fixture set is pinned to the protocol version")
    func manifestMatchesFixturesAndVersion() throws {
        let manifest = try String(contentsOf: Self.manifestURL, encoding: .utf8)
        #expect(manifest == Self.manifestText(digest: try Self.fixtureDigest()),
                "Fixtures changed without updating MANIFEST, or the version moved. Bump PixelHandProtocol.version, note it in Core/PROTOCOL.md, and re-record.")
    }

    @Test("Every message starts with the version and one domain key")
    func envelopeShape() throws {
        for sample in Self.samples {
            let data = try ControlMessageCoding.encode(sample.message)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["v"] as? Int == PixelHandProtocol.version)
            #expect(Set(object.keys) == ["v", sample.message.domain.rawValue], "\(sample.name)")
        }
    }

    // MARK: - 2. Field rules

    @Test("Optional fields are omitted when nil, not encoded as null")
    func nilOptionalsAreOmitted() throws {
        let mirror = try ControlMessageCoding.encode(.mirror(.start(fps: 15, maxWidth: 640, displayID: nil, codec: .jpeg, windowID: nil)))
        #expect(!String(decoding: mirror, as: UTF8.self).contains("displayID"))
        let app = try ControlMessageCoding.encode(.apps(.activeAppUpdate(name: "X", bundleID: nil)))
        #expect(!String(decoding: app, as: UTF8.self).contains("bundleID"))
    }

    @Test("Host status skips feature names this build doesn't know")
    func hostStatusSkipsUnknownFeatures() throws {
        let json = #"{"session":{"hostStatus":{"status":{"accessibility":true,"features":["commandReceipts","teleport"],"screenRecording":true}}},"v":\#(Self.v)}"#
        let decoded = try ControlMessageCoding.decode(Data(json.utf8))
        guard case let .session(.hostStatus(status)) = decoded else {
            Issue.record("decoded \(decoded)")
            return
        }
        #expect(status.features == [.commandReceipts])
        #expect(status.supports(.commandReceipts))
        #expect(!status.supports(.binaryMirrorStream))
    }

    @Test("A run carries its action intact")
    func runCarriesItsAction() throws {
        let message = ControlMessage.deck(.run(requestID: "cmd-9", action: .shortcut(keys: ["cmd", "s"])))
        let decoded = try ControlMessageCoding.decode(ControlMessageCoding.encode(message))
        #expect(decoded == message)
    }

    // MARK: - 3. Hostile and malformed input

    @Test("A message from another protocol version is refused")
    func otherVersionsAreRefused() throws {
        for version in [0, 1, PixelHandProtocol.version + 1] {
            let json = #"{"session":{"ping":{"seq":1}},"v":\#(version)}"#
            #expect(throws: ProtocolError.unsupportedVersion(version)) {
                try ControlMessageCoding.decode(Data(json.utf8))
            }
        }
    }

    @Test("A protocol 1 message without an envelope is refused")
    func versionOneMessagesAreRefused() {
        let legacy = Data(#"{"type":"mouseDelta","dx":1,"dy":2}"#.utf8)
        #expect(throws: (any Error).self) { try ControlMessageCoding.decode(legacy) }
    }

    @Test("Unknown, missing and multiple domains are refused")
    func badDomainsAreRefused() {
        #expect(throws: ProtocolError.unknownDomain) {
            try ControlMessageCoding.decode(Data(#"{"selfDestruct":{"now":{}},"v":\#(Self.v)}"#.utf8))
        }
        #expect(throws: ProtocolError.unknownDomain) {
            try ControlMessageCoding.decode(Data(#"{"v":\#(Self.v)}"#.utf8))
        }
        #expect(throws: ProtocolError.multipleDomains(["input", "session"])) {
            try ControlMessageCoding.decode(Data(#"{"input":{"mouseClick":{"button":"left"}},"session":{"ping":{"seq":1}},"v":\#(Self.v)}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try ControlMessageCoding.decode(Data("{}".utf8))
        }
    }

    @Test("An unknown sharing case is refused")
    func unknownSharingCaseIsRefused() {
        #expect(throws: (any Error).self) {
            try ControlMessageCoding.decode(Data(#"{"sharing":{"clipboard":{}},"v":\#(Self.v)}"#.utf8))
        }
    }

    @Test("Unknown cases and missing fields are refused")
    func unknownCasesAreRefused() {
        #expect(throws: (any Error).self) {
            try ControlMessageCoding.decode(Data(#"{"input":{"selfDestruct":{}},"v":\#(Self.v)}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try ControlMessageCoding.decode(Data(#"{"input":{"mouseDelta":{"dx":1}},"v":\#(Self.v)}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try ControlMessageCoding.decode(Data(#"{"input":{"mouseDelta":{"dx":1,"dy":2},"mouseClick":{"button":"left"}},"v":\#(Self.v)}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try ControlMessageCoding.decode(Data(#"{"system":{"run":{"action":"selfDestruct"}},"v":\#(Self.v)}"#.utf8))
        }
    }

    @Test("A run can't wrap a message, so runs can't nest")
    func runsCantNest() {
        let nested = #"{"deck":{"run":{"action":{"deck":{"run":{"action":{"shortcut":{"keys":["a"]}},"requestID":"b"}}},"requestID":"a"}},"v":\#(Self.v)}"#
        #expect(throws: (any Error).self) { try ControlMessageCoding.decode(Data(nested.utf8)) }
    }

    @Test("Oversize input is refused before parsing")
    func oversizeIsRefused() throws {
        let big = Data(repeating: 0x20, count: ProtocolLimits.maxRemoteMessageBytes + 1)
        #expect(throws: ProtocolError.messageTooLarge(bytes: big.count, limit: ProtocolLimits.maxRemoteMessageBytes)) {
            try ControlMessageCoding.decode(big, maxBytes: ProtocolLimits.maxRemoteMessageBytes)
        }
        let ping = try ControlMessageCoding.encode(.session(.ping(seq: 1)))
        #expect(try ControlMessageCoding.decode(ping, maxBytes: ProtocolLimits.maxRemoteMessageBytes) == .session(.ping(seq: 1)))
    }

    // MARK: - Advertisement

    @Test("The TXT key carries this build's version and parses back")
    func advertisementRoundTrip() {
        let metadata = PixelHandProtocol.advertisementMetadata
        #expect(metadata == ["ph-proto": String(PixelHandProtocol.version)])
        #expect(PixelHandProtocol.advertisedVersion(in: metadata) == PixelHandProtocol.version)
        #expect(PixelHandProtocol.advertisedVersion(in: [:]) == nil)
        #expect(PixelHandProtocol.advertisedVersion(in: ["ph-proto": "x"]) == nil)
        #expect(PixelHandProtocol.advertisedVersion(in: ["ph-proto": "0"]) == nil)
        #expect(PixelHandProtocol.advertisedVersion(in: ["ph-proto": " 3 "]) == 3)
        #expect(PixelHandProtocol.advertisementKey.utf8.count <= 9)
    }
}

// MARK: - UIContextSnapshot

@Suite struct UIContextSnapshotContractTests {

    /// Equality is structural: two snapshots built from the same dialog are
    /// equal, which is what the Mac's rebroadcast dedupe relies on.
    @Test func structurallyEqualDialogsCompareEqual() {
        func make() -> UIContextSnapshot {
            .dialog(DialogContext(
                revision: "abc123",
                title: "T",
                message: "M",
                buttons: [DialogButton(id: "abc123|0|OK", title: "OK", isDefault: true, isCancel: false)]
            ))
        }
        #expect(make() == make())
    }

    @Test func differentRevisionBreaksEquality() {
        let a = UIContextSnapshot.dialog(DialogContext(revision: "r1", title: nil, message: nil, buttons: []))
        let b = UIContextSnapshot.dialog(DialogContext(revision: "r2", title: nil, message: nil, buttons: []))
        #expect(a != b)
    }

    @Test func textFieldKindsRoundTrip() throws {
        for kind in [TextFieldContext.Kind.text, .numeric, .secure] {
            let snapshot = UIContextSnapshot.textField(TextFieldContext(kind: kind))
            let data = try ControlMessageCoding.encoder.encode(snapshot)
            #expect(try ControlMessageCoding.decoder.decode(UIContextSnapshot.self, from: data) == snapshot)
        }
    }

    @Test("Button order is part of the contract: the remote renders in array order")
    func dialogRoundTripPreservesButtonOrder() throws {
        let buttons = (0..<5).map {
            DialogButton(id: "rev|\($0)|B\($0)", title: "B\($0)", isDefault: $0 == 4, isCancel: $0 == 0)
        }
        let snapshot = UIContextSnapshot.dialog(DialogContext(revision: "rev", title: "Order", message: nil, buttons: buttons))
        let data = try ControlMessageCoding.encoder.encode(snapshot)
        #expect(try ControlMessageCoding.decoder.decode(UIContextSnapshot.self, from: data) == snapshot)
    }
}
