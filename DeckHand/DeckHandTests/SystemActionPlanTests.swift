//
//  SystemActionPlanTests.swift
//  DeckHandTests
//
//  On macOS 27 `Mission Control 1` and `open -a Apps` do nothing, and the
//  F11 fallback needs the user's Show Desktop shortcut switched on. The
//  plan must never rely on those paths first on 27, and must keep the
//  known-good paths on older systems.
//

import XCTest

final class SystemActionPlanTests: XCTestCase {

    // MARK: Show Desktop (bug 1)

    func testShowDesktopOnMacOS27SkipsTheBrokenBinary() {
        let plan = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27)
        XCTAssertEqual(plan.first, .symbolicHotKey)
        XCTAssertFalse(plan.contains(.missionControlBinary))
        XCTAssertEqual(plan.last, .systemEventsKey, "the binding-dependent F11 path is the last resort")
    }

    func testShowDesktopOnOlderSystemsKeepsTheBinaryAsAFallback() {
        for major in [14, 15, 26] {
            let plan = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: major)
            XCTAssertEqual(plan.first, .symbolicHotKey, "macOS \(major)")
            XCTAssertTrue(plan.contains(.missionControlBinary), "macOS \(major)")
            XCTAssertLessThan(plan.firstIndex(of: .missionControlBinary)!, plan.firstIndex(of: .systemEventsKey)!)
        }
    }

    func testBindingIndependentMechanismsComeBeforeF11() {
        let plan = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27)
        let f11 = plan.firstIndex(of: .systemEventsKey)!
        for mechanism in [SystemActionMechanism.symbolicHotKey, .dockNotification, .dedicatedKey] {
            XCTAssertLessThan(plan.firstIndex(of: mechanism)!, f11, mechanism.rawValue)
        }
    }

    // MARK: Other actions and overrides

    func testOtherActionsAreNotPlanned() {
        for macro in [SystemMacro.locateCursor, .missionControl, .appExpose] {
            XCTAssertTrue(SystemActionPlan.mechanisms(for: macro, macOSMajor: 27).isEmpty)
            XCTAssertTrue(SystemActionPlan.mechanisms(for: macro, macOSMajor: 27, override: "dockNotification").isEmpty)
            XCTAssertNil(SystemActionPlan.overrideKey(for: macro))
        }
    }

    func testOverrideForcesTheListedMechanisms() {
        XCTAssertEqual(
            SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: "dockNotification"),
            [.dockNotification]
        )
    }

    func testBadOverrideFallsBackToTheDefaultPlan() {
        let defaults = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27)
        XCTAssertEqual(SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: "nonsense"), defaults)
        XCTAssertEqual(SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: "  "), defaults)
        XCTAssertEqual(SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: nil), defaults)
    }

    func testOverrideKeys() {
        XCTAssertEqual(SystemActionPlan.overrideKey(for: .showDesktop), "PixelHandShowDesktopMechanism")
        XCTAssertEqual(SystemActionPlan.overrideKey(for: .launchpad), "PixelHandLaunchpadMechanism")
    }

    // MARK: Symbolic hot keys

    func testHotKeyIDs() {
        XCTAssertEqual(SymbolicHotKey(.showDesktop), .showDesktop)
        XCTAssertEqual(SymbolicHotKey.showDesktop.rawValue, 36)
        XCTAssertEqual(SymbolicHotKey(.launchpad)?.rawValue, 160)
        XCTAssertNil(SymbolicHotKey(.missionControl))
    }

    func testBoundHotKeyUsesTheUsersChord() {
        // Show Desktop switched off but still set to fn F11, as on the test Mac.
        let result = SymbolicHotKey.showDesktop.chord(boundKeyCode: 103, boundModifiers: 0x80_0000)
        XCTAssertEqual(result.chord, .init(keyCode: 103, modifiers: 0x80_0000))
        XCTAssertFalse(result.needsTemporaryBinding)
    }

    func testUnboundHotKeyGetsAFallbackChord() {
        let showDesktop = SymbolicHotKey.showDesktop.chord(boundKeyCode: SymbolicHotKey.unboundKeyCode, boundModifiers: 0)
        XCTAssertTrue(showDesktop.needsTemporaryBinding)
        XCTAssertEqual(showDesktop.chord.keyCode, 103)
    }
}
