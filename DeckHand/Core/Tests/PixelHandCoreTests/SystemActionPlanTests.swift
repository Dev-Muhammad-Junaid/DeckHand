//
//  SystemActionPlanTests.swift
//  PixelHandCoreTests
//
//  On macOS 27 `Mission Control 1` and `open -a Apps` do nothing, and the
//  F11 fallback needs the user's Show Desktop shortcut switched on. The
//  plan must never rely on those paths first on 27, and must keep the
//  known-good paths on older systems.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct SystemActionPlanTests {

    // MARK: Show Desktop (bug 1)

    @Test func showDesktopOnMacOS27SkipsTheBrokenBinary() {
        let plan = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27)
        #expect(plan.first == .symbolicHotKey)
        #expect(!plan.contains(.missionControlBinary))
        #expect(plan.last == .systemEventsKey, "the binding-dependent F11 path is the last resort")
    }

    @Test func showDesktopOnOlderSystemsKeepsTheBinaryAsAFallback() {
        for major in [14, 15, 26] {
            let plan = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: major)
            #expect(plan.first == .symbolicHotKey, "macOS \(major)")
            #expect(plan.contains(.missionControlBinary), "macOS \(major)")
            #expect(plan.firstIndex(of: .missionControlBinary)! < plan.firstIndex(of: .systemEventsKey)!)
        }
    }

    @Test func bindingIndependentMechanismsComeBeforeF11() {
        let plan = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27)
        let f11 = plan.firstIndex(of: .systemEventsKey)!
        for mechanism in [SystemActionMechanism.symbolicHotKey, .dockNotification, .dedicatedKey] {
            #expect(plan.firstIndex(of: mechanism)! < f11, "\(mechanism.rawValue)")
        }
    }

    // MARK: Launchpad / Apps (bug 2)

    @Test func launchpadOnMacOS27NeverUsesOpenApp() {
        let plan = SystemActionPlan.mechanisms(for: .launchpad, macOSMajor: 27)
        #expect(!plan.contains(.openApp))
        #expect(plan == [.symbolicHotKey, .dedicatedKey, .dockNotification])
    }

    @Test func launchpadOnOlderSystemsKeepsOpenAppFirst() {
        for major in [14, 15, 26] {
            let plan = SystemActionPlan.mechanisms(for: .launchpad, macOSMajor: major)
            #expect(plan.first == .openApp, "macOS \(major)")
            #expect(plan.contains(.symbolicHotKey), "macOS \(major)")
        }
    }

    @Test func launchpadNeverFallsBackToShowDesktopPaths() {
        for major in [14, 26, 27, 28] {
            let plan = SystemActionPlan.mechanisms(for: .launchpad, macOSMajor: major)
            #expect(!plan.contains(.missionControlBinary))
            #expect(!plan.contains(.systemEventsKey))
        }
    }

    // MARK: Other actions and overrides

    @Test("Locate is not planned: it is drawn by the Mac app itself")
    func locateIsNotPlanned() {
        #expect(SystemActionPlan.mechanisms(for: .locateCursor, macOSMajor: 27).isEmpty)
        #expect(SystemActionPlan.mechanisms(for: .locateCursor, macOSMajor: 27, override: "dockNotification").isEmpty)
        #expect(SystemActionPlan.overrideKey(for: .locateCursor) == nil)
    }

    @Test("Mission Control and App Exposé go through the user's hot key first, never System Events (S7)")
    func missionControlAndAppExposeUseHotKeys() {
        for major in [14, 26, 27] {
            let missionControl = SystemActionPlan.mechanisms(for: .missionControl, macOSMajor: major)
            #expect(missionControl == [.symbolicHotKey, .openApp], "macOS \(major)")
            let appExpose = SystemActionPlan.mechanisms(for: .appExpose, macOSMajor: major)
            #expect(appExpose == [.symbolicHotKey], "macOS \(major)")
            #expect(!missionControl.contains(.systemEventsKey) && !appExpose.contains(.systemEventsKey))
        }
    }

    @Test func overrideForcesTheListedMechanisms() {
        #expect(SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: "dockNotification") == [.dockNotification])
        #expect(SystemActionPlan.mechanisms(for: .launchpad, macOSMajor: 27, override: " dedicatedKey , symbolicHotKey ") == [.dedicatedKey, .symbolicHotKey])
    }

    @Test func badOverrideFallsBackToTheDefaultPlan() {
        let defaults = SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27)
        #expect(SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: "nonsense") == defaults)
        #expect(SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: "  ") == defaults)
        #expect(SystemActionPlan.mechanisms(for: .showDesktop, macOSMajor: 27, override: nil) == defaults)
    }

    @Test func overrideKeys() {
        #expect(SystemActionPlan.overrideKey(for: .showDesktop) == "PixelHandShowDesktopMechanism")
        #expect(SystemActionPlan.overrideKey(for: .launchpad) == "PixelHandLaunchpadMechanism")
        #expect(SystemActionPlan.overrideKey(for: .missionControl) == "PixelHandMissionControlMechanism")
        #expect(SystemActionPlan.overrideKey(for: .appExpose) == "PixelHandAppExposeMechanism")
    }

    // MARK: Symbolic hot keys

    @Test func hotKeyIDs() {
        #expect(SymbolicHotKey(.showDesktop) == .showDesktop)
        #expect(SymbolicHotKey.showDesktop.rawValue == 36)
        #expect(SymbolicHotKey(.launchpad)?.rawValue == 160)
        #expect(SymbolicHotKey(.missionControl)?.rawValue == 32)
        #expect(SymbolicHotKey(.appExpose)?.rawValue == 33)
        #expect(SymbolicHotKey(.locateCursor) == nil)
    }

    @Test func boundHotKeyUsesTheUsersChord() {
        // Show Desktop switched off but still set to fn F11, as on the test Mac.
        let result = SymbolicHotKey.showDesktop.chord(boundKeyCode: 103, boundModifiers: 0x80_0000)
        #expect(result.chord == .init(keyCode: 103, modifiers: 0x80_0000))
        #expect(!result.needsTemporaryBinding)
    }

    @Test func unboundHotKeyGetsAFallbackChord() {
        let showDesktop = SymbolicHotKey.showDesktop.chord(boundKeyCode: SymbolicHotKey.unboundKeyCode, boundModifiers: 0)
        #expect(showDesktop.needsTemporaryBinding)
        #expect(showDesktop.chord.keyCode == 103)

        let launchpad = SymbolicHotKey.showLaunchpad.chord(boundKeyCode: nil, boundModifiers: 0)
        #expect(launchpad.needsTemporaryBinding)
        #expect(launchpad.chord.keyCode == 80)
        // Never ⌘Space (Spotlight).
        #expect(launchpad.chord.keyCode != 49)
        #expect(launchpad.chord.modifiers != 0, "a bare F19 could clash with a user's own binding")
    }
}
