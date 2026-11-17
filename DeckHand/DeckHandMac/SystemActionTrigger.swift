//
//  SystemActionTrigger.swift
//  DeckHandMac
//
//  Shows the desktop and opens Launchpad / Apps without depending on the
//  user's own shortcut settings, which the old paths did. On macOS 27
//  `Mission Control 1` and `open -a Apps` stopped doing anything, and the
//  F11 fallback can't help on a Mac where Show Desktop is switched off in
//  Keyboard Shortcuts.
//
//  Private API (Mac app only; it ships as a Developer ID download, see
//  DECISIONS.md). Every symbol is looked up with `dlsym`, and a missing
//  one only skips that mechanism:
//
//  - `CGSGetSymbolicHotKeyValue`, `CGSIsSymbolicHotKeyEnabled`,
//    `CGSSetSymbolicHotKeyEnabled`, `CGSSetSymbolicHotKeyValue` (SkyLight):
//    read the hot key, and if it is off or unbound, switch it on or give it
//    a spare chord for about a second, post the chord, then put the user's
//    setting back.
//  - `CoreDockSendNotification` (HIServices): asks the Dock directly.
//
//  `SystemActionPlan` (Shared) decides the order.
//

import AppKit
import CoreGraphics
import Darwin
import Foundation

@MainActor
final class SystemActionTrigger {
    static let shared = SystemActionTrigger()

    /// What the hot key looked like before we touched it, so the restore
    /// after a burst of taps puts back the user's setting, not ours.
    private struct SavedHotKey {
        let wasEnabled: Bool
        let keyEquivalent: UInt16
        let keyCode: UInt16
        let modifiers: UInt32
    }

    private var savedHotKeys: [Int32: SavedHotKey] = [:]
    private var restoreTasks: [Int32: Task<Void, Never>] = [:]

    /// How long a hot key we switched on stays on before it is restored.
    private static let restoreDelay: Duration = .milliseconds(1200)

    private init() {}

    /// Runs `macro` (Show Desktop or Launchpad) with the first mechanism
    /// that can run. Returns `false` if none could.
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
            guard let hotKey = SymbolicHotKey(macro) else { return false }
            return await postSymbolicHotKey(hotKey)
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
            guard macro == .launchpad else { return false }
            let name = FileManager.default.fileExists(atPath: "/System/Applications/Launchpad.app") ? "Launchpad" : "Apps"
            return Self.runTool("/usr/bin/open", ["-a", name])
        case .systemEventsKey:
            guard macro == .showDesktop else { return false }
            return Self.runTool("/usr/bin/osascript", ["-e", "tell application \"System Events\" to key code 103"])
        }
    }

    /// Posts the hot key's chord, switching the hot key on (and binding a
    /// spare chord if it has none) just long enough for the post.
    private func postSymbolicHotKey(_ hotKey: SymbolicHotKey) async -> Bool {
        guard AXIsProcessTrusted(), let cgs = CGSHotKeys.shared else { return false }
        let id = hotKey.rawValue

        var keyEquivalent: UInt16 = 0
        var keyCode: UInt16 = SymbolicHotKey.unboundKeyCode
        var modifiers: UInt32 = 0
        let readError = cgs.getValue(id, &keyEquivalent, &keyCode, &modifiers)
        let readable = readError == 0
        let enabledNow = cgs.isEnabled(id)

        // Keep the user's original state across a burst of taps.
        if savedHotKeys[id] == nil {
            savedHotKeys[id] = SavedHotKey(
                wasEnabled: enabledNow,
                keyEquivalent: readable ? keyEquivalent : SymbolicHotKey.unboundKeyCode,
                keyCode: readable ? keyCode : SymbolicHotKey.unboundKeyCode,
                modifiers: readable ? modifiers : 0
            )
        }

        let (chord, needsBinding) = hotKey.chord(boundKeyCode: readable ? keyCode : nil, boundModifiers: modifiers)
        var changed = false
        if needsBinding {
            guard cgs.setValue(id, SymbolicHotKey.unboundKeyCode, chord.keyCode, chord.modifiers) == 0 else {
                DeckHandLog.input.error("Couldn't bind a temporary chord to symbolic hot key \(id, privacy: .public)")
                scheduleRestore(id, cgs: cgs)
                return false
            }
            changed = true
        }
        if !enabledNow {
            guard cgs.setEnabled(id, true) == 0 else {
                DeckHandLog.input.error("Couldn't switch on symbolic hot key \(id, privacy: .public)")
                scheduleRestore(id, cgs: cgs)
                return false
            }
            changed = true
        }
        // Give the WindowServer a moment to pick up a hot key we just changed.
        if changed {
            try? await Task.sleep(for: .milliseconds(60))
        }
        DeckHandLog.input.info("Symbolic hot key \(id, privacy: .public): posting key \(chord.keyCode, privacy: .public) flags 0x\(String(chord.modifiers, radix: 16), privacy: .public) (was \(enabledNow ? "on" : "off", privacy: .public), \(needsBinding ? "unbound" : "bound", privacy: .public))")
        let posted = Self.postKey(CGKeyCode(chord.keyCode), flags: CGEventFlags(rawValue: UInt64(chord.modifiers)))
        scheduleRestore(id, cgs: cgs)
        return posted
    }

    /// Puts the user's hot key setting back after a short delay. A new tap
    /// before then pushes the restore back instead of stacking restores.
    private func scheduleRestore(_ id: Int32, cgs: CGSHotKeys) {
        restoreTasks[id]?.cancel()
        restoreTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.restoreDelay)
            guard !Task.isCancelled, let self, let saved = self.savedHotKeys[id] else { return }
            if saved.keyCode == SymbolicHotKey.unboundKeyCode {
                _ = cgs.setValue(id, saved.keyEquivalent, saved.keyCode, saved.modifiers)
            }
            if !saved.wasEnabled {
                _ = cgs.setEnabled(id, false)
            }
            self.savedHotKeys[id] = nil
            self.restoreTasks[id] = nil
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
        guard let send = CGSHotKeys.coreDockSendNotification else { return false }
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

/// The private symbols, looked up once. `nil` when any of the four hot-key
/// calls is missing on this macOS.
private struct CGSHotKeys: @unchecked Sendable {
    typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32
    typealias SetValue = @convention(c) (Int32, UInt16, UInt16, UInt32) -> Int32
    typealias IsEnabled = @convention(c) (Int32) -> Bool
    typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    typealias DockNotify = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Int32

    let getValue: GetValue
    let setValue: SetValue
    let isEnabled: IsEnabled
    let setEnabled: SetEnabled

    static let shared: CGSHotKeys? = {
        guard let get = symbol("CGSGetSymbolicHotKeyValue", as: GetValue.self),
              let set = symbol("CGSSetSymbolicHotKeyValue", as: SetValue.self),
              let isOn = symbol("CGSIsSymbolicHotKeyEnabled", as: IsEnabled.self),
              let setOn = symbol("CGSSetSymbolicHotKeyEnabled", as: SetEnabled.self)
        else {
            DeckHandLog.input.error("Symbolic hot key calls not found on this macOS")
            return nil
        }
        return CGSHotKeys(getValue: get, setValue: set, isEnabled: isOn, setEnabled: setOn)
    }()

    nonisolated(unsafe) static let coreDockSendNotification: DockNotify? = {
        let found = symbol("CoreDockSendNotification", as: DockNotify.self)
        if found == nil {
            DeckHandLog.input.error("CoreDockSendNotification not found on this macOS")
        }
        return found
    }()

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        // RTLD_DEFAULT: search every image loaded in the process.
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}
