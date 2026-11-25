//
//  InputInjector.swift
//  DeckHandMac
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

// These constants are defined in IOKit/hidsystem/ev_keymap.h but aren't
// globally visible without importing IOKit.hid.
let NX_KEYTYPE_PLAY: Int32 = 16
let NX_KEYTYPE_NEXT: Int32 = 17
let NX_KEYTYPE_PREVIOUS: Int32 = 18

/// Injects mouse and keyboard events into the macOS input system via CGEvent.
/// Requires Accessibility access — call `requestAccessibility()` on first use.
@MainActor
final class InputInjector {
    static let shared = InputInjector()

    private init() {}

    // MARK: - Diagnostics
    //
    // Every injection method below returns silently when Accessibility
    // isn't granted, which made "the Mac received the message but the
    // cursor never moved" indistinguishable from "the message never
    // arrived" (hypothesis 3). These throttled logs make that distinction
    // visible in Console.app / `log stream` without flooding at 120 Hz.
    private var lastSkipLogAt: Date = .distantPast
    private var hasLoggedFirstInjection = false
    /// Timestamp of the previous `moveCursor` injection, used to detect
    /// dropped frames during active movement (cursor-jitter investigation).
    private var lastMoveCursorAt: Date?
    /// Buttons a remote holds down (`input.mouseDown`), so pointer moves
    /// are posted as drags. `DragGuard` decides when they go down and up.
    private(set) var heldButtons: Set<MouseButton> = []

    /// Logs (≤1/sec) that an inbound input event was dropped because
    /// Accessibility isn't granted — the smoking gun for "received but
    /// not injected."
    private func noteInjectSkipped(_ action: String) {
        let now = Date()
        guard now.timeIntervalSince(lastSkipLogAt) > 1 else { return }
        lastSkipLogAt = now
        DeckHandLog.input.error("⛔️ \(action, privacy: .public) skipped — Accessibility not granted (AXIsProcessTrusted=false)")
    }

    /// One-shot confirmation that CGEvents are actually being posted, so a
    /// successful "received and injected" path is provable from the logs.
    private func noteInjectionActive(_ action: String) {
        guard !hasLoggedFirstInjection else { return }
        hasLoggedFirstInjection = true
        DeckHandLog.input.info("✅ Injecting input — first \(action, privacy: .public) posted since launch (Accessibility granted)")
    }

    // MARK: - Accessibility

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    nonisolated func requestAccessibility() {
        // Use the known string key directly to avoid the global shared-mutable warning
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Mouse movement

    /// Moves the cursor by a relative delta (in points).
    ///
    /// The iPad applies user-chosen sensitivity before sending; the host
    /// adds a subtle acceleration curve so small movements stay precise
    /// while large swipes cover more distance — matching macOS trackpad feel.
    ///
    /// We let macOS handle every aspect of multi-display routing. No local
    /// clamping, no synthetic delta fields — just a clean absolute-position
    /// `mouseMoved` event. macOS clips out-of-bounds coordinates at the HID
    /// layer on its own, so the cursor moves freely across every connected
    /// display without us doing anything extra.
    func moveCursor(dx: Float, dy: Float) {
        guard isAccessibilityGranted else { noteInjectSkipped("mouseDelta"); return }
        // ControlReceiver already sanitizes every message; this keeps a NaN/∞ from ever
        // becoming a cursor position if another caller forgets to.
        guard let safeDX = RemoteInputValidation.clamp(dx, limit: RemoteInputValidation.maxPointerDelta),
              let safeDY = RemoteInputValidation.clamp(dy, limit: RemoteInputValidation.maxPointerDelta)
        else { return }
        // Jitter probe: during active movement the iPad streams deltas at up to
        // 120 Hz (~8 ms apart). A gap in the 33–250 ms band means frames were
        // dropped while the user was still moving — i.e. visible cursor jitter,
        // usually from main-thread contention. Idle gaps (>250 ms, finger
        // lifted) are normal and not logged, so this stays quiet in steady use.
        let now = Date()
        if let last = lastMoveCursorAt {
            let gapMs = now.timeIntervalSince(last) * 1000
            if gapMs > 33, gapMs < 250 {
                DeckHandLog.input.info("Cursor delta gap \(Int(gapMs))ms — possible jitter / main-thread contention")
            }
        }
        lastMoveCursorAt = now
        let currentPos = NSEvent.mouseLocation
        // NSEvent y is flipped relative to CGDisplayBounds. We flip using
        // the *global* frame's max-y so the conversion stays correct on
        // multi-display setups where the main display isn't at the top.
        let cgCurrent = Self.flipNSPointToCG(currentPos)

        let accelDx = applyAcceleration(safeDX)
        let accelDy = applyAcceleration(safeDY)

        let next = CGPoint(x: cgCurrent.x + Double(accelDx),
                           y: cgCurrent.y + Double(accelDy))
        // While a remote holds a button the move is a drag, or the app
        // under the pointer sees a hover and drops the drag.
        let (moveType, moveButton) = dragMoveType()
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: moveType,
                            mouseCursorPosition: next,
                            mouseButton: moveButton)
        event?.post(tap: .cghidEventTap)
        noteInjectionActive("mouseDelta")
    }

    /// macOS-style pointer acceleration: small deltas stay 1:1,
    /// large swipes ramp up for fast traversal.
    /// The curve lives in Core (`MacPointerAcceleration`) so the remote can
    /// predict where a delta lands (picture pointer control, VQ-095).
    private func applyAcceleration(_ delta: Float) -> Float {
        // Below 3pt of movement, keep 1:1 for precision work.
        // Above that, gently ramp up to feel natural on large screens.
        Float(MacPointerAcceleration.apply(Double(delta)))
    }

    // MARK: - Scroll

    func scroll(dx: Float, dy: Float) {
        scroll(dx: dx, dy: dy, phase: .changed)
    }

    /// Scroll-phase-aware send so AppKit / WebKit / SwiftUI scroll views
    /// see continuous scroll gestures rather than a stream of un-phased
    /// wheel ticks. The iPad uses this for the begin/end transitions; the
    /// trackpad's "natural" rubber-banding and momentum continuation only
    /// kicks in when these phases are present.
    func scroll(dx: Float, dy: Float, phase: ScrollPhase) {
        guard isAccessibilityGranted else { noteInjectSkipped("scroll"); return }
        // scrollWheel: unit=pixel, axis1=vertical, axis2=horizontal
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            // Never `Int32(-dy * 3)`: that traps on NaN, ±∞ or anything past
            // ±7e8, and the value comes straight off the network.
            wheel1: RemoteInputValidation.wheelUnits(forScrollDelta: dy),
            wheel2: RemoteInputValidation.wheelUnits(forScrollDelta: dx),
            wheel3: 0
        ) else { return }

        // Continuous scroll bit must be set so AppKit treats the deltas as
        // pixel-precise (trackpad style), not line-step (mouse-wheel style).
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)

        switch phase {
        case .begin:
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)   // kCGScrollPhaseBegan
        case .changed:
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)   // kCGScrollPhaseChanged
        case .end:
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)   // kCGScrollPhaseEnded
        case .momentumBegin:
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1) // kCGMomentumScrollPhaseBegin
        case .momentumChanged:
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2) // kCGMomentumScrollPhaseContinue
        case .momentumEnd:
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3) // kCGMomentumScrollPhaseEnd
        }

        event.post(tap: .cghidEventTap)
    }

    /// Phases recognized by `scroll(dx:dy:phase:)`. Mirrors AppKit's
    /// `NSEvent.Phase` / momentum phases without dragging in AppKit types.
    enum ScrollPhase: Sendable {
        case begin
        case changed
        case end
        case momentumBegin
        case momentumChanged
        case momentumEnd
    }

    // MARK: - Clicks

    func click(button: MouseButton, double: Bool = false) {
        guard isAccessibilityGranted else { noteInjectSkipped("click"); return }
        let pos = currentCGCursorPosition()
        let (downType, upType, cgBtn) = cgMouseTypes(for: button)

        // macOS double-click convention: the *first* down/up pair has
        // clickState = 1, the *second* has clickState = 2. Firing two pairs
        // both with clickState = 2 is read as a triple-click by AppKit.
        let states: [Int64] = double ? [1, 2] : [1]
        for state in states {
            let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                               mouseCursorPosition: pos, mouseButton: cgBtn)
            down?.setIntegerValueField(.mouseEventClickState, value: state)
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                             mouseCursorPosition: pos, mouseButton: cgBtn)
            up?.setIntegerValueField(.mouseEventClickState, value: state)
            up?.post(tap: .cghidEventTap)
        }
        noteInjectionActive("click")
    }

    // MARK: - Drag (button down / up)

    /// Presses `button` and keeps it down; moves become drags until
    /// `mouseUp`. Called by `DragGuard` only for a new press.
    func mouseDown(button: MouseButton) {
        guard isAccessibilityGranted else { noteInjectSkipped("mouseDown"); return }
        let (downType, _, cgButton) = cgMouseTypes(for: button)
        heldButtons.insert(button)
        let event = CGEvent(mouseEventSource: nil, mouseType: downType,
                            mouseCursorPosition: currentCGCursorPosition(), mouseButton: cgButton)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        event?.post(tap: .cghidEventTap)
        noteInjectionActive("mouseDown")
    }

    /// Releases a button pressed with `mouseDown`. The bookkeeping clears
    /// first, so later moves are plain moves whatever happens here.
    func mouseUp(button: MouseButton) {
        heldButtons.remove(button)
        guard isAccessibilityGranted else { noteInjectSkipped("mouseUp"); return }
        let (_, upType, cgButton) = cgMouseTypes(for: button)
        let event = CGEvent(mouseEventSource: nil, mouseType: upType,
                            mouseCursorPosition: currentCGCursorPosition(), mouseButton: cgButton)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        event?.post(tap: .cghidEventTap)
    }

    /// The event type for a pointer move: a drag of the held button (left
    /// first), or a plain move.
    private func dragMoveType() -> (CGEventType, CGMouseButton) {
        if heldButtons.contains(.left) { return (.leftMouseDragged, .left) }
        if heldButtons.contains(.right) { return (.rightMouseDragged, .right) }
        if heldButtons.contains(.middle) { return (.otherMouseDragged, .center) }
        return (.mouseMoved, .left)
    }

    // MARK: - Typed text (input.typeText)
    //
    // `TypingQueue` plans the text with Core's `TypingPlanner` and calls
    // these one step at a time, paced, so the frontmost app keeps up.

    /// A dedicated source, so a modifier the person holds on the Mac's
    /// own keyboard doesn't turn typed letters into shortcuts.
    private lazy var typingSource = CGEventSource(stateID: .privateState)

    /// Presses and releases one key of the current layout, with Shift or
    /// Option held when the character needs them.
    func typeKey(_ stroke: LayoutKeyStroke) {
        guard isAccessibilityGranted else { noteInjectSkipped("typeText"); return }
        var flags: CGEventFlags = []
        if stroke.shift { flags.insert(.maskShift) }
        if stroke.option { flags.insert(.maskAlternate) }
        let keyCode = CGKeyCode(stroke.keyCode)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: typingSource, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        noteInjectionActive("typeText")
    }

    /// Presses and releases a named key from Core's `KeyTable` (Return, Tab).
    func typeNamedKey(_ name: String) {
        guard isAccessibilityGranted else { noteInjectSkipped("typeText"); return }
        guard let code = KeyTable.keyCode(for: name) else { return }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: typingSource, virtualKey: CGKeyCode(code), keyDown: isDown) else { continue }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    /// Types `text` (at most `TypingPlanner.maxUnicodeUnitsPerEvent` UTF-16
    /// units) as a Unicode string on one key-down/up pair, for characters
    /// the layout can't type.
    func typeUnicode(_ text: String) {
        guard isAccessibilityGranted else { noteInjectSkipped("typeText"); return }
        let units = Array(text.utf16.prefix(TypingPlanner.maxUnicodeUnitsPerEvent))
        guard !units.isEmpty else { return }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: typingSource, virtualKey: 0, keyDown: isDown) else { continue }
            event.flags = []
            units.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            event.post(tap: .cghidEventTap)
        }
        noteInjectionActive("typeText")
    }

    // MARK: - Keyboard shortcuts

    /// Sends a keyboard shortcut specified as an array of key name strings.
    /// Example: ["cmd", "space"], ["cmd", "shift", "3"]
    ///
    /// Uses `.combinedSessionState` so the synthesized modifiers aren't
    /// overridden by whatever modifier keys the user happens to be holding on
    /// a physical keyboard. Posts modifier flag-changes as separate events
    /// around the key event; some apps (Chrome, Electron apps, Cursor) drop
    /// shortcuts when modifier flags arrive only as side-channel `flags` on
    /// the keydown — they want to see real `flagsChanged` events.
    func sendShortcut(keys: [String]) {
        guard isAccessibilityGranted else { noteInjectSkipped("shortcut"); return }
        let (modifiers, keyCode) = parseKeys(keys)
        guard let kc = keyCode else {
            #if DEBUG
            print("Pixel Hand: ⚠️ Unknown shortcut key in \(keys)")
            #endif
            return
        }

        let src = CGEventSource(stateID: .combinedSessionState)

        // 1. Press each modifier as a real flagsChanged event.
        let mods = activeModifierKeys(modifiers)
        for modKey in mods {
            if let down = CGEvent(keyboardEventSource: src, virtualKey: modKey, keyDown: true) {
                down.flags = modifiers
                down.post(tap: .cghidEventTap)
            }
        }

        // 2. Press and release the non-modifier key with full flags attached.
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: false) {
            keyUp.flags = modifiers
            keyUp.post(tap: .cghidEventTap)
        }

        // 3. Release modifiers in reverse order.
        for modKey in mods.reversed() {
            if let up = CGEvent(keyboardEventSource: src, virtualKey: modKey, keyDown: false) {
                up.flags = []
                up.post(tap: .cghidEventTap)
            }
        }
        noteInjectionActive("shortcut")
    }

    /// Maps a `CGEventFlags` set to the virtual key codes we need to press so
    /// AppKit sees `flagsChanged` events for each modifier (Core's
    /// `KeyModifier` codes, in its press order).
    private func activeModifierKeys(_ flags: CGEventFlags) -> [CGKeyCode] {
        KeyModifier.pressOrder
            .filter { flags.contains(Self.flag(for: $0)) }
            .map { CGKeyCode($0.keyCode) }
    }

    private static func flag(for modifier: KeyModifier) -> CGEventFlags {
        switch modifier {
        case .command: .maskCommand
        case .shift: .maskShift
        case .option: .maskAlternate
        case .control: .maskControl
        case .function: .maskSecondaryFn
        }
    }

    // MARK: - Media Controls

    /// Sends a system-defined media key (e.g., NX_KEYTYPE_PLAY).
    func sendMediaKey(_ keyType: Int32) {
        guard isAccessibilityGranted else { noteInjectSkipped("mediaKey"); return }

        // System defined key down
        if let down = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((keyType << 16) | (0xa << 8)),
            data2: -1
        ) {
            down.cgEvent?.post(tap: .cghidEventTap)
        }

        // System defined key up
        if let up = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((keyType << 16) | (0xb << 8)),
            data2: -1
        ) {
            up.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Parks the pointer in this display's menu bar. Spaces follow the
    /// display that contains the pointer; the menu bar is used instead of
    /// the centre so Control-Left/Right is not delivered into a focused
    /// text field or browser (which swallow the shortcut).
    func moveCursorToMenuBar(ofDisplay displayID: CGDirectDisplayID) {
        guard isAccessibilityGranted else { noteInjectSkipped("warpCursor"); return }
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let point = CGPoint(x: bounds.midX, y: bounds.minY + 8)
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
        noteInjectionActive("warpCursor")
    }

    func moveCursorToCenter(ofDisplay displayID: CGDirectDisplayID) {
        guard isAccessibilityGranted else { noteInjectSkipped("warpCursor"); return }
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: center,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
        noteInjectionActive("warpCursor")
    }

    /// The pointer's position in global display coordinates.
    func cursorPosition() -> CGPoint {
        currentCGCursorPosition()
    }

    /// Puts the pointer at `point` (global display coordinates).
    func moveCursor(to point: CGPoint) {
        guard isAccessibilityGranted else { noteInjectSkipped("warpCursor"); return }
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
        noteInjectionActive("warpCursor")
    }

    /// Display currently under the pointer, used when the iPad has not
    /// yet named a monitor. Falls back to the main display.
    func displayIDUnderCursor() -> CGDirectDisplayID {
        let point = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            guard screen.frame.contains(point),
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            return CGDirectDisplayID(truncating: number)
        }
        return CGMainDisplayID()
    }

    // MARK: - Helpers

    private func currentCGCursorPosition() -> CGPoint {
        Self.flipNSPointToCG(NSEvent.mouseLocation)
    }

    /// Converts an AppKit (origin-bottom-left, multi-screen-aware) point to
    /// a CGEvent (origin-top-left) point.
    private static func flipNSPointToCG(_ point: CGPoint) -> CGPoint {
        // Use the union of all displays so the conversion stays correct
        // regardless of which screen the cursor happens to be on.
        let unionMaxY = NSScreen.screens
            .map(\.frame.maxY)
            .max() ?? (NSScreen.main?.frame.maxY ?? 900)
        return CGPoint(x: point.x, y: unionMaxY - point.y)
    }

    private func cgMouseTypes(for button: MouseButton) -> (CGEventType, CGEventType, CGMouseButton) {
        switch button {
        case .left:   return (.leftMouseDown, .leftMouseUp, .left)
        case .right:  return (.rightMouseDown, .rightMouseUp, .right)
        case .middle: return (.otherMouseDown, .otherMouseUp, .center)
        }
    }

    /// Maps string key names → (CGEventFlags, CGKeyCode?) with Core's
    /// `KeyTable`, which both apps share and Core tests.
    private func parseKeys(_ keys: [String]) -> (CGEventFlags, CGKeyCode?) {
        guard let chord = KeyTable.chord(keys) else {
            // Keep the old leniency for modifiers-only or unknown keys: the
            // flags still parse, there's just no key to press.
            var flags: CGEventFlags = []
            for name in keys {
                if let modifier = KeyModifier.named(name) { flags.insert(Self.flag(for: modifier)) }
            }
            return (flags, nil)
        }
        var flags: CGEventFlags = []
        for modifier in chord.modifiers { flags.insert(Self.flag(for: modifier)) }
        return (flags, CGKeyCode(chord.keyCode))
    }
}
