//
//  SymbolicHotKeys.swift
//  DeckHandMac
//
//  Posts the Mac's own system shortcuts (S7): Mission Control, App Exposé,
//  Show Desktop, Launchpad / Apps and moving between Spaces. It reads the
//  user's bindings from the window server, so a shortcut changed in System
//  Settings › Keyboard › Keyboard Shortcuts is followed, and posts the chord
//  as a `CGEvent` at the HID tap. No System Events, so no Automation prompt.
//
//  Which hot key and chord to use is decided in Core
//  (`SymbolicHotKeyResolver`); this file only reads, switches on for a
//  moment, posts and restores.
//
//  Private API (Mac app only, Developer ID; approved in DECISIONS.md),
//  every symbol looked up with `dlsym` and skipped if missing:
//
//  - `CGSGetSymbolicHotKeyValue`, `CGSIsSymbolicHotKeyEnabled` (read);
//  - `CGSSetSymbolicHotKeyEnabled`, `CGSSetSymbolicHotKeyValue` (switch a
//    hot key on, or bind a spare chord, for about a second when the user
//    has every shortcut for the action off; then put it back);
//  - `CoreDockSendNotification` (used by `SystemActionTrigger`).
//
//  With the read calls missing, Apple's default chords are posted.
//

import AppKit
import CoreGraphics
import Darwin
import Foundation

@MainActor
final class SymbolicHotKeys {
    static let shared = SymbolicHotKeys()

    /// What a hot key looked like before we touched it, so the restore
    /// after a burst of taps puts back the user's setting, not ours.
    private struct SavedHotKey {
        let wasEnabled: Bool
        let keyEquivalent: UInt16
        let keyCode: UInt16
        let modifiers: UInt32
    }

    private var savedHotKeys: [Int32: SavedHotKey] = [:]
    private var restoreTasks: [Int32: Task<Void, Never>] = [:]
    private var loggedMissingSymbols = false

    /// How long a hot key we switched on stays on before it is restored.
    private static let restoreDelay: Duration = .milliseconds(1200)
    /// Time for the window server to pick up a hot key we just changed.
    private static let settleDelay: Duration = .milliseconds(60)

    private init() {}

    /// Reads the hot keys `action` may use. `nil` when the read calls are
    /// missing on this macOS.
    func table(for action: HotKeyAction) -> [SymbolicHotKey: HotKeyBinding]? {
        guard let cgs = CGSHotKeyCalls.shared else { return nil }
        var table: [SymbolicHotKey: HotKeyBinding] = [:]
        for key in SymbolicHotKeyResolver.hotKeysToRead(for: action) {
            var keyEquivalent: UInt16 = 0
            var keyCode: UInt16 = SymbolicHotKey.unboundKeyCode
            var modifiers: UInt32 = 0
            guard cgs.getValue(key.rawValue, &keyEquivalent, &keyCode, &modifiers) == 0 else { continue }
            table[key] = HotKeyBinding(keyCode: keyCode, modifiers: modifiers, isEnabled: cgs.isEnabled(key.rawValue))
        }
        return table
    }

    /// Posts the shortcut for `action`. Returns `false` when nothing could
    /// be posted (no Accessibility, or a hot key couldn't be switched on).
    @discardableResult
    func perform(_ action: HotKeyAction) async -> Bool {
        guard AXIsProcessTrusted() else {
            DeckHandLog.input.error("\(action.rawValue, privacy: .public): Accessibility is off, so no shortcut can be posted")
            return false
        }
        let table = table(for: action)
        if table == nil, !loggedMissingSymbols {
            loggedMissingSymbols = true
            DeckHandLog.input.error("Symbolic hot key calls not found on this macOS; posting Apple's default shortcuts")
        }
        let resolution = SymbolicHotKeyResolver.resolve(action, table: table)
        switch resolution {
        case let .post(key, chord):
            DeckHandLog.input.info("\(action.rawValue, privacy: .public): posting the user's shortcut \(key.rawValue, privacy: .public) (\(chord.description, privacy: .public))")
            return Self.post(chord)

        case let .postDefault(key, chord):
            DeckHandLog.input.info("\(action.rawValue, privacy: .public): posting Apple's default for \(key.rawValue, privacy: .public) (\(chord.description, privacy: .public)), unread")
            return Self.post(chord)

        case let .enableTemporarily(key, chord, needsBinding):
            return await postTemporarily(key, chord: chord, needsBinding: needsBinding, action: action)
        }
    }

    /// Switches `key` on (binding `chord` first if it has no key) just long
    /// enough to post it, then restores the user's setting.
    private func postTemporarily(_ key: SymbolicHotKey, chord: SymbolicHotKey.Chord, needsBinding: Bool, action: HotKeyAction) async -> Bool {
        guard let cgs = CGSHotKeyCalls.shared, cgs.canWrite else { return false }
        let id = key.rawValue

        var keyEquivalent: UInt16 = 0
        var keyCode: UInt16 = SymbolicHotKey.unboundKeyCode
        var modifiers: UInt32 = 0
        let readable = cgs.getValue(id, &keyEquivalent, &keyCode, &modifiers) == 0
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

        var changed = false
        if needsBinding {
            guard cgs.setValue?(id, SymbolicHotKey.unboundKeyCode, chord.keyCode, chord.modifiers) == 0 else {
                DeckHandLog.input.error("Couldn't bind a temporary chord to symbolic hot key \(id, privacy: .public)")
                scheduleRestore(id, cgs: cgs)
                return false
            }
            changed = true
        }
        if !enabledNow {
            guard cgs.setEnabled?(id, true) == 0 else {
                DeckHandLog.input.error("Couldn't switch on symbolic hot key \(id, privacy: .public)")
                scheduleRestore(id, cgs: cgs)
                return false
            }
            changed = true
        }
        if changed {
            try? await Task.sleep(for: Self.settleDelay)
        }
        DeckHandLog.input.info("Symbolic hot key \(id, privacy: .public) for \(action.rawValue, privacy: .public): posting \(chord.description, privacy: .public) (was \(enabledNow ? "on" : "off", privacy: .public), \(needsBinding ? "unbound" : "bound", privacy: .public))")
        let posted = Self.post(chord)
        scheduleRestore(id, cgs: cgs)
        return posted
    }

    /// Puts the user's hot key setting back after a short delay. A new tap
    /// before then pushes the restore back instead of stacking restores.
    private func scheduleRestore(_ id: Int32, cgs: CGSHotKeyCalls) {
        restoreTasks[id]?.cancel()
        restoreTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.restoreDelay)
            guard !Task.isCancelled, let self, let saved = self.savedHotKeys[id] else { return }
            if saved.keyCode == SymbolicHotKey.unboundKeyCode {
                _ = cgs.setValue?(id, saved.keyEquivalent, saved.keyCode, saved.modifiers)
            }
            if !saved.wasEnabled {
                _ = cgs.setEnabled?(id, false)
            }
            self.savedHotKeys[id] = nil
            self.restoreTasks[id] = nil
        }
    }

    /// Posts a key down with the chord's modifiers, and a key up with the
    /// modifiers that were down before, so the chord's ⌃ or fn doesn't
    /// linger into the next click (a ⌃-click is a right click).
    static func post(_ chord: SymbolicHotKey.Chord) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(chord.keyCode)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        let before = CGEventSource.flagsState(.hidSystemState)
            .intersection(CGEventFlags(rawValue: UInt64(SymbolicHotKey.modifierMask)))
        down.flags = CGEventFlags(rawValue: UInt64(chord.modifiers))
        up.flags = before
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// The private SkyLight calls, looked up once. `nil` when either read call
/// is missing; the write calls are optional on top.
struct CGSHotKeyCalls: @unchecked Sendable {
    typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32
    typealias SetValue = @convention(c) (Int32, UInt16, UInt16, UInt32) -> Int32
    typealias IsEnabled = @convention(c) (Int32) -> Bool
    typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    typealias DockNotify = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Int32

    let getValue: GetValue
    let isEnabled: IsEnabled
    let setValue: SetValue?
    let setEnabled: SetEnabled?

    /// Both write calls exist, so a hot key can be switched on for a moment.
    var canWrite: Bool { setValue != nil && setEnabled != nil }

    static let shared: CGSHotKeyCalls? = {
        guard let get = PrivateSymbol.load("CGSGetSymbolicHotKeyValue", as: GetValue.self),
              let isOn = PrivateSymbol.load("CGSIsSymbolicHotKeyEnabled", as: IsEnabled.self)
        else {
            DeckHandLog.input.error("CGSGetSymbolicHotKeyValue / CGSIsSymbolicHotKeyEnabled not found on this macOS")
            return nil
        }
        let set = PrivateSymbol.load("CGSSetSymbolicHotKeyValue", as: SetValue.self)
        let setOn = PrivateSymbol.load("CGSSetSymbolicHotKeyEnabled", as: SetEnabled.self)
        if set == nil || setOn == nil {
            DeckHandLog.input.error("CGSSetSymbolicHotKeyValue / CGSSetSymbolicHotKeyEnabled not found; a switched-off shortcut can't be used")
        }
        return CGSHotKeyCalls(getValue: get, isEnabled: isOn, setValue: set, setEnabled: setOn)
    }()

    nonisolated(unsafe) static let coreDockSendNotification: DockNotify? = {
        let found = PrivateSymbol.load("CoreDockSendNotification", as: DockNotify.self)
        if found == nil {
            DeckHandLog.input.error("CoreDockSendNotification not found on this macOS")
        }
        return found
    }()
}

/// `dlsym` over every image loaded in the process (RTLD_DEFAULT).
enum PrivateSymbol {
    static func load<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}
