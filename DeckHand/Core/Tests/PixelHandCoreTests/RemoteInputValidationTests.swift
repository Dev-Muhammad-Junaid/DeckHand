//
//  RemoteInputValidationTests.swift
//  PixelHandCoreTests
//
//  PH-031: a remote used to crash the Mac host with one scroll message,
//  because `Int32(-dy * 3)` traps on NaN, ±∞ and anything past ±7e8.
//  These tests pin the validation layer every inbound message goes
//  through: non-finite numbers drop the message, the rest are clamped,
//  and nothing traps.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct RemoteInputValidationTests {

    private let hostile: [Float] = [
        .nan, -.nan, .infinity, -.infinity,
        .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
        1e9, -1e9,
    ]

    // MARK: - Scroll (the crash)

    @Test func wheelUnitsNeverTrap() {
        for value in hostile + [0, 1, -1, 7e8, -7e8, 7.2e8, -7.2e8] {
            _ = RemoteInputValidation.wheelUnits(forScrollDelta: value)
        }
        #expect(RemoteInputValidation.wheelUnits(forScrollDelta: .nan) == 0)
        #expect(RemoteInputValidation.wheelUnits(forScrollDelta: .infinity) == 0)
        #expect(RemoteInputValidation.wheelUnits(forScrollDelta: 1e9) == .min)
        #expect(RemoteInputValidation.wheelUnits(forScrollDelta: -1e9) == .max)
    }

    @Test func wheelUnitsMatchTheOldFormulaForNormalValues() {
        for value: Float in [0, 1, -1, 2.5, -12.75, 400, -10_000] {
            #expect(RemoteInputValidation.wheelUnits(forScrollDelta: value) == Int32(-value * 3), "delta \(value)")
        }
    }

    @Test func nonFiniteScrollIsDropped() {
        for value: Float in [.nan, .infinity, -.infinity] {
            #expect(RemoteInputValidation.sanitize(.input(.mouseScroll(dx: 0, dy: value, phase: .changed))) == nil)
            #expect(RemoteInputValidation.sanitize(.input(.mouseScroll(dx: value, dy: 0, phase: .changed))) == nil)
        }
    }

    @Test func hugeScrollIsClamped() throws {
        let message = try #require(RemoteInputValidation.sanitize(
            .input(.mouseScroll(dx: -.greatestFiniteMagnitude, dy: 1e9, phase: .end))
        ))
        guard case let .input(.mouseScroll(dx, dy, phase)) = message else {
            Issue.record("Expected mouseScroll, got \(message)")
            return
        }
        #expect(dx == -RemoteInputValidation.maxScrollDelta)
        #expect(dy == RemoteInputValidation.maxScrollDelta)
        #expect(phase == .end)
        // The clamped value converts without trapping.
        _ = Int32(-dy * 3)
    }

    @Test func normalScrollIsUnchanged() throws {
        let message = try #require(RemoteInputValidation.sanitize(.input(.mouseScroll(dx: 1.5, dy: -12, phase: .begin))))
        guard case let .input(.mouseScroll(dx, dy, _)) = message else { Issue.record("\(message)"); return }
        #expect(dx == 1.5)
        #expect(dy == -12)
    }

    // MARK: - Pointer

    @Test func pointerDeltas() throws {
        #expect(RemoteInputValidation.sanitize(.input(.mouseDelta(dx: .nan, dy: 0))) == nil)
        #expect(RemoteInputValidation.sanitize(.input(.mouseDelta(dx: 0, dy: -.infinity))) == nil)

        let clamped = try #require(RemoteInputValidation.sanitize(.input(.mouseDelta(dx: 1e9, dy: -1e9))))
        guard case let .input(.mouseDelta(dx, dy)) = clamped else { Issue.record("\(clamped)"); return }
        #expect(dx == RemoteInputValidation.maxPointerDelta)
        #expect(dy == -RemoteInputValidation.maxPointerDelta)

        let normal = try #require(RemoteInputValidation.sanitize(.input(.mouseDelta(dx: 3.25, dy: -0.5))))
        guard case let .input(.mouseDelta(ndx, ndy)) = normal else { Issue.record("\(normal)"); return }
        #expect(ndx == 3.25)
        #expect(ndy == -0.5)
    }

    // MARK: - Capture region

    @Test func regionWithBadNumbersIsDropped() {
        let bad: [CaptureMode] = [
            .region(x: .nan, y: 0, width: 0.5, height: 0.5),
            .region(x: 0, y: .infinity, width: 0.5, height: 0.5),
            .region(x: 0, y: 0, width: -0.5, height: 0.5),
            .region(x: 0, y: 0, width: 0.5, height: 0),
            .region(x: 2, y: 2, width: 0.5, height: 0.5),     // entirely off-screen
            .region(x: -3, y: 0, width: 1, height: 1),        // entirely left of the display
        ]
        for mode in bad {
            #expect(RemoteInputValidation.sanitize(mode) == nil, "\(mode)")
            #expect(RemoteInputValidation.sanitize(.capture(.requestScreenshot(requestID: "r", mode: mode, quality: .standard))) == nil, "\(mode)")
        }
    }

    @Test func regionIsClippedToTheDisplay() throws {
        let mode = try #require(RemoteInputValidation.sanitize(.region(x: -0.25, y: 0.5, width: 0.5, height: 1e9)))
        #expect(mode == .region(x: 0, y: 0.5, width: 0.25, height: 0.5))

        let inside = CaptureMode.region(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        #expect(RemoteInputValidation.sanitize(inside) == inside)
        #expect(RemoteInputValidation.sanitize(.fullScreen) == .fullScreen)
        #expect(RemoteInputValidation.sanitize(.window(windowID: .max)) == .window(windowID: .max))
    }

    // MARK: - Mirror

    @Test func mirrorSettingsAreClamped() throws {
        let cases: [(Int, Int, Int, Int)] = [
            (.min, .min, 1, 120),
            (.max, .max, 30, 1920),
            (0, 0, 1, 120),
            (-5, -5, 1, 120),
            (20, 480, 20, 480),
        ]
        for (fps, width, expectedFPS, expectedWidth) in cases {
            let message = try #require(RemoteInputValidation.sanitize(.mirror(.start(fps: fps, maxWidth: width, displayID: 7))))
            guard case let .mirror(.start(outFPS, outWidth, displayID)) = message else { Issue.record("\(message)"); return }
            #expect(outFPS == expectedFPS)
            #expect(outWidth == expectedWidth)
            #expect(displayID == 7)
        }
    }

    // MARK: - Tracked runs, strings and pass-through

    @Test("A run is checked as the message its action stands for")
    func runsAreValidatedToo() {
        let tooManyKeys = Array(repeating: "a", count: ProtocolLimits.maxChordKeys + 1)
        #expect(RemoteInputValidation.sanitize(.deck(.run(requestID: "t", action: .shortcut(keys: tooManyKeys)))) == nil)
        let fine = ControlMessage.deck(.run(requestID: "t", action: .shortcut(keys: ["cmd", "c"])))
        #expect(RemoteInputValidation.sanitize(fine) == fine)
    }

    @Test("Strings and chords past the limits are dropped")
    func oversizeStringsAreDropped() {
        let long = String(repeating: "x", count: ProtocolLimits.maxStringLength + 1)
        #expect(RemoteInputValidation.sanitize(.apps(.launchApp(bundleID: long))) == nil)
        #expect(RemoteInputValidation.sanitize(.apps(.triggerContextAction(id: long))) == nil)
        #expect(RemoteInputValidation.sanitize(.capture(.requestWindowList(requestID: long))) == nil)
        #expect(RemoteInputValidation.sanitize(.deck(.requestAppMenuShortcuts(bundleID: long))) == nil)
        #expect(RemoteInputValidation.sanitize(.input(.keyboardShortcut(keys: [long]))) == nil)
        #expect(RemoteInputValidation.sanitize(.deck(.run(requestID: long, action: .media(key: .next)))) == nil)
        #expect(RemoteInputValidation.sanitize(.apps(.appShortcut(bundleID: "com.apple.Safari", keys: ["cmd", long]))) == nil)
    }

    @Test func messagesWithoutNumbersPassThrough() {
        let messages: [ControlMessage] = [
            .input(.mouseClick(button: .left)),
            .input(.keyboardShortcut(keys: ["cmd", "c"])),
            .input(.media(key: .playPause)),
            .system(.run(action: .showDesktop)),
            .session(.ping(seq: .max)),
            .pairing(.requestAuthorizationStatus),
            .system(.switchSpace(direction: .next, displayID: UInt32.max)),
            .apps(.launchApp(bundleID: "com.apple.Safari")),
            .deck(.run(requestID: "t", action: .contextAction(id: "rev|0|OK"))),
        ]
        for message in messages {
            #expect(RemoteInputValidation.sanitize(message) == message, "\(message)")
        }
    }

    /// JSON can't carry NaN or ∞, but any finite float decodes, and 1e30
    /// used to crash the host through `Int32(-dy * 3)`.
    @Test func largestDecodableScrollIsSafeEndToEnd() throws {
        let json = #"{"input":{"mouseScroll":{"dx":0,"dy":1e30,"phase":"changed"}},"v":\#(PixelHandProtocol.version)}"#
        let decoded = try ControlMessageCoding.decode(Data(json.utf8))
        let message = try #require(RemoteInputValidation.sanitize(decoded))
        guard case let .input(.mouseScroll(_, dy, _)) = message else { Issue.record("\(message)"); return }
        #expect(RemoteInputValidation.wheelUnits(forScrollDelta: dy) == Int32(-RemoteInputValidation.maxScrollDelta * 3))
    }

    // MARK: - Typing, drags and the clipboard (iOS interaction lane)

    @Test("Typed text is cleaned of control characters; empty or oversize text is dropped")
    func typedText() {
        #expect(RemoteInputValidation.sanitize(.input(.typeText(text: "héllo 👋🏽\r\n"))) == .input(.typeText(text: "héllo 👋🏽\n")))
        #expect(RemoteInputValidation.sanitize(.input(.typeText(text: "a\u{1B}[2Jb"))) == .input(.typeText(text: "a[2Jb")))
        #expect(RemoteInputValidation.sanitize(.input(.typeText(text: ""))) == nil)
        #expect(RemoteInputValidation.sanitize(.input(.typeText(text: "\u{0}\u{7}"))) == nil)
        let atLimit = String(repeating: "a", count: TypingPolicy.maxMessageBytes)
        #expect(RemoteInputValidation.sanitize(.input(.typeText(text: atLimit))) == .input(.typeText(text: atLimit)))
        #expect(RemoteInputValidation.sanitize(.input(.typeText(text: atLimit + "a"))) == nil)
    }

    @Test("Button presses and releases pass through")
    func buttons() {
        for button in MouseButton.allCases {
            #expect(RemoteInputValidation.sanitize(.input(.mouseDown(button: button))) == .input(.mouseDown(button: button)))
            #expect(RemoteInputValidation.sanitize(.input(.mouseUp(button: button))) == .input(.mouseUp(button: button)))
        }
    }

    @Test("Clipboard text up to the cap is accepted; empty or oversize is dropped")
    func clipboardText() {
        #expect(RemoteInputValidation.sanitize(.sharing(.setClipboard(text: "hi", paste: true))) == .sharing(.setClipboard(text: "hi", paste: true)))
        #expect(RemoteInputValidation.sanitize(.sharing(.setClipboard(text: "", paste: false))) == nil)
        let over = String(repeating: "a", count: ClipboardPolicy.maxTextBytes + 1)
        #expect(RemoteInputValidation.sanitize(.sharing(.setClipboard(text: over, paste: false))) == nil)
        #expect(RemoteInputValidation.sanitize(.sharing(.clipboardSync(enabled: true))) == .sharing(.clipboardSync(enabled: true)))
    }

    @Test("A remote can't send the Mac's clipboard message")
    func macClipboardFromRemoteIsDropped() {
        #expect(RemoteInputValidation.sanitize(.sharing(.macClipboard(text: "x"))) == nil)
    }
}
