//
//  RemoteInputValidationTests.swift
//  DeckHandTests
//
//  PH-031: a remote used to crash the Mac host with one scroll message,
//  because `Int32(-dy * 3)` traps on NaN, ±∞ and anything past ±7e8.
//  These tests pin the validation layer every inbound message goes
//  through: non-finite numbers drop the message, the rest are clamped,
//  and nothing traps.
//

import XCTest

final class RemoteInputValidationTests: XCTestCase {

    private let hostile: [Float] = [
        .nan, -.nan, .infinity, -.infinity,
        .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
        1e9, -1e9,
    ]

    // MARK: - Scroll (the crash)

    func testWheelUnitsNeverTrap() {
        for value in hostile + [0, 1, -1, 7e8, -7e8, 7.2e8, -7.2e8] {
            _ = RemoteInputValidation.wheelUnits(forScrollDelta: value)
        }
        XCTAssertEqual(RemoteInputValidation.wheelUnits(forScrollDelta: .nan), 0)
        XCTAssertEqual(RemoteInputValidation.wheelUnits(forScrollDelta: .infinity), 0)
        XCTAssertEqual(RemoteInputValidation.wheelUnits(forScrollDelta: 1e9), .min)
        XCTAssertEqual(RemoteInputValidation.wheelUnits(forScrollDelta: -1e9), .max)
    }

    func testWheelUnitsMatchTheOldFormulaForNormalValues() {
        for value: Float in [0, 1, -1, 2.5, -12.75, 400, -10_000] {
            XCTAssertEqual(
                RemoteInputValidation.wheelUnits(forScrollDelta: value),
                Int32(-value * 3),
                "delta \(value)"
            )
        }
    }

    func testNonFiniteScrollIsDropped() {
        for value: Float in [.nan, .infinity, -.infinity] {
            XCTAssertNil(RemoteInputValidation.sanitize(.mouseScroll(dx: 0, dy: value, phase: .changed)))
            XCTAssertNil(RemoteInputValidation.sanitize(.mouseScroll(dx: value, dy: 0, phase: .changed)))
        }
    }

    func testHugeScrollIsClamped() throws {
        let message = try XCTUnwrap(RemoteInputValidation.sanitize(
            .mouseScroll(dx: -.greatestFiniteMagnitude, dy: 1e9, phase: .end)
        ))
        guard case let .mouseScroll(dx, dy, phase) = message else {
            return XCTFail("Expected mouseScroll, got \(message)")
        }
        XCTAssertEqual(dx, -RemoteInputValidation.maxScrollDelta)
        XCTAssertEqual(dy, RemoteInputValidation.maxScrollDelta)
        XCTAssertEqual(phase, .end)
        // The clamped value converts without trapping.
        _ = Int32(-dy * 3)
    }

    func testNormalScrollIsUnchanged() throws {
        let message = try XCTUnwrap(RemoteInputValidation.sanitize(.mouseScroll(dx: 1.5, dy: -12, phase: .begin)))
        guard case let .mouseScroll(dx, dy, _) = message else { return XCTFail("\(message)") }
        XCTAssertEqual(dx, 1.5)
        XCTAssertEqual(dy, -12)
    }

    // MARK: - Pointer

    func testPointerDeltas() throws {
        XCTAssertNil(RemoteInputValidation.sanitize(.mouseDelta(dx: .nan, dy: 0)))
        XCTAssertNil(RemoteInputValidation.sanitize(.mouseDelta(dx: 0, dy: -.infinity)))

        let clamped = try XCTUnwrap(RemoteInputValidation.sanitize(.mouseDelta(dx: 1e9, dy: -1e9)))
        guard case let .mouseDelta(dx, dy) = clamped else { return XCTFail("\(clamped)") }
        XCTAssertEqual(dx, RemoteInputValidation.maxPointerDelta)
        XCTAssertEqual(dy, -RemoteInputValidation.maxPointerDelta)

        let normal = try XCTUnwrap(RemoteInputValidation.sanitize(.mouseDelta(dx: 3.25, dy: -0.5)))
        guard case let .mouseDelta(ndx, ndy) = normal else { return XCTFail("\(normal)") }
        XCTAssertEqual(ndx, 3.25)
        XCTAssertEqual(ndy, -0.5)
    }

    // MARK: - Capture region

    func testRegionWithBadNumbersIsDropped() {
        let bad: [CaptureMode] = [
            .region(x: .nan, y: 0, width: 0.5, height: 0.5),
            .region(x: 0, y: .infinity, width: 0.5, height: 0.5),
            .region(x: 0, y: 0, width: -0.5, height: 0.5),
            .region(x: 0, y: 0, width: 0.5, height: 0),
            .region(x: 2, y: 2, width: 0.5, height: 0.5),     // entirely off-screen
            .region(x: -3, y: 0, width: 1, height: 1),        // entirely left of the display
        ]
        for mode in bad {
            XCTAssertNil(RemoteInputValidation.sanitize(mode), "\(mode)")
            XCTAssertNil(RemoteInputValidation.sanitize(.requestScreenshot(requestID: "r", mode: mode)), "\(mode)")
        }
    }

    func testRegionIsClippedToTheDisplay() throws {
        let mode = try XCTUnwrap(RemoteInputValidation.sanitize(.region(x: -0.25, y: 0.5, width: 0.5, height: 1e9)))
        XCTAssertEqual(mode, .region(x: 0, y: 0.5, width: 0.25, height: 0.5))

        let inside = CaptureMode.region(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        XCTAssertEqual(RemoteInputValidation.sanitize(inside), inside)
        XCTAssertEqual(RemoteInputValidation.sanitize(.fullScreen), .fullScreen)
        XCTAssertEqual(RemoteInputValidation.sanitize(.window(windowID: .max)), .window(windowID: .max))
    }

    // MARK: - Mirror

    func testMirrorSettingsAreClamped() throws {
        let cases: [(Int, Int, Int, Int)] = [
            (.min, .min, 1, 120),
            (.max, .max, 30, 1920),
            (0, 0, 1, 120),
            (-5, -5, 1, 120),
            (20, 480, 20, 480),
        ]
        for (fps, width, expectedFPS, expectedWidth) in cases {
            let message = try XCTUnwrap(RemoteInputValidation.sanitize(.startMirror(fps: fps, maxWidth: width, displayID: 7)))
            guard case let .startMirror(outFPS, outWidth, displayID) = message else { return XCTFail("\(message)") }
            XCTAssertEqual(outFPS, expectedFPS)
            XCTAssertEqual(outWidth, expectedWidth)
            XCTAssertEqual(displayID, 7)
        }
    }

    // MARK: - Wrappers and pass-through

    func testTrackedCommandsAreValidatedToo() throws {
        XCTAssertNil(RemoteInputValidation.sanitize(.tracked(requestID: "t", command: .mouseScroll(dx: 0, dy: .nan, phase: .changed))))

        let message = try XCTUnwrap(RemoteInputValidation.sanitize(
            .tracked(requestID: "t", command: .mouseDelta(dx: 1e9, dy: 0))
        ))
        guard case let .tracked(requestID, .mouseDelta(dx, _)) = message else { return XCTFail("\(message)") }
        XCTAssertEqual(requestID, "t")
        XCTAssertEqual(dx, RemoteInputValidation.maxPointerDelta)
    }

    func testMessagesWithoutNumbersPassThrough() {
        let messages: [ControlMessage] = [
            .mouseClick(button: .left),
            .keyboardShortcut(keys: ["cmd", "c"]),
            .macroButton(id: "showdesktop"),
            .ping(seq: .max),
            .requestAuthorizationStatus,
            .switchSpace(direction: .next, displayID: UInt32.max),
        ]
        for message in messages {
            XCTAssertNotNil(RemoteInputValidation.sanitize(message), "\(message)")
        }
    }

    /// JSON can't carry NaN or ∞, but any finite float decodes, and 1e30
    /// used to crash the host through `Int32(-dy * 3)`.
    func testLargestDecodableScrollIsSafeEndToEnd() throws {
        let json = #"{"type":"mouseScroll","dx":0,"dy":1e30,"phase":"changed"}"#
        let decoded = try JSONDecoder().decode(ControlMessage.self, from: Data(json.utf8))
        let message = try XCTUnwrap(RemoteInputValidation.sanitize(decoded))
        guard case let .mouseScroll(_, dy, _) = message else { return XCTFail("\(message)") }
        XCTAssertEqual(RemoteInputValidation.wheelUnits(forScrollDelta: dy), Int32(-RemoteInputValidation.maxScrollDelta * 3))
    }
}
