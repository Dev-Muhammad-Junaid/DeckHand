//
//  SystemActionTrigger.swift
//  DeckHandMac
//
//  Runs Mission Control, App Exposé, Show Desktop and Launchpad / Apps
//  through the plan in `SystemActionPlan` (Core): the first mechanism that
//  is able to run wins, since none can tell whether the Dock reacted.
//
//  - `symbolicHotKey` posts the user's own shortcut (S7,
//    `SymbolicHotKeys.swift`), switching it on for a moment if it is off.
//  - `dockNotification` calls `CoreDockSendNotification` (private, `dlsym`).
//  - The rest are the older paths, kept where they still work.
//
//  On macOS 27 `Mission Control 1` and `open -a Apps` stopped doing
//  anything, and System Events needed the Automation prompt; neither is
//  used first any more.
//

import AppKit
import CoreGraphics
import Darwin
import Foundation

@MainActor
final class SystemActionTrigger {
    static let shared = SystemActionTrigger()

    private init() {}

    /// Runs `macro` with the first mechanism that can run. Returns `false`
    /// if none could.
    @discardableResult
    func run(_ macro: SystemMacro) async -> Bool {
        let overrideValue = SystemActionPlan.overrideKey(for: macro)
            .flatMap { UserDefaults.standard.string(forKey: $0) }
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let plan = SystemActionPlan.mechanisms(for: macro, macOSMajor: major, override: overrideValue)
        for mechanism in plan {
            if await attempt(mechanism, for: macro) {
                DeckHandLog.input.info("\(macro.rawValue, privacy: .public): ran via \(mechanism.rawValue, privacy: .public) (macOS \(major, privacy: .public)\(overrideValue == nil ? "" : ", override", privacy: .public))")
                return true
            }
            DeckHandLog.input.info("\(macro.rawValue, privacy: .public): \(mechanism.rawValue, privacy: .public) unavailable, trying the next way")
        }
        DeckHandLog.input.error("\(macro.rawValue, privacy: .public): no mechanism could run (plan \(plan.map(\.rawValue).joined(separator: ","), privacy: .public))")
        return false
    }

    // MARK: - Mechanisms

    private func attempt(_ mechanism: SystemActionMechanism, for macro: SystemMacro) async -> Bool {
        switch mechanism {
        case .symbolicHotKey:
            guard let action = HotKeyAction(macro) else { return false }
            return await SymbolicHotKeys.shared.perform(action)
        case .dockNotification:
            switch macro {
            case .showDesktop: return Self.sendDockNotification("com.apple.showdesktop.awake")
            case .launchpad: return Self.sendDockNotification("com.apple.launchpad.toggle")
            default: return false
            }
        case .dedicatedKey:
            guard AXIsProcessTrusted() else { return false }
            switch macro {
            case .showDesktop:
                // ⌘ + Mission Control key (virtual key 0xA0) is Apple's fixed
                // Show Desktop shortcut on keyboards with that key.
                return Self.postKey(0xA0, flags: [.maskCommand, .maskSecondaryFn])
            case .launchpad:
                // The Launchpad key (virtual key 0x83); Apps on macOS 26+.
                return Self.postKey(0x83, flags: [.maskSecondaryFn])
            default:
                return false
            }
        case .missionControlBinary:
            guard macro == .showDesktop, let path = Self.missionControlExecutable else { return false }
            return Self.runTool(path, ["1"])
        case .openApp:
            switch macro {
            case .missionControl:
                return Self.runTool("/usr/bin/open", ["-a", "Mission Control"])
            case .launchpad:
                let name = FileManager.default.fileExists(atPath: "/System/Applications/Launchpad.app") ? "Launchpad" : "Apps"
                return Self.runTool("/usr/bin/open", ["-a", name])
            default:
                return false
            }
        case .systemEventsKey:
            guard macro == .showDesktop else { return false }
            return Self.runTool("/usr/bin/osascript", ["-e", "tell application \"System Events\" to key code 103"])
        }
    }

    // MARK: - Helpers

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func sendDockNotification(_ name: String) -> Bool {
        guard let send = CGSHotKeyCalls.coreDockSendNotification else { return false }
        _ = send(name as CFString, nil)
        return true
    }

    private static let missionControlExecutable: String? = [
        "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control",
        "/Applications/Mission Control.app/Contents/MacOS/Mission Control",
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func runTool(_ path: String, _ arguments: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        do {
            try proc.run()
            return true
        } catch {
            DeckHandLog.input.error("Couldn't run \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
