//
//  FocusTextObserver.swift
//  DeckHandMac
//
//  Live text sync, Phase 1 (protocol 17, `RD-live-sync-and-caret.md` §1.1):
//  the Accessibility half. It watches the front app's focused text field
//  with an `AXObserver` and reads it as text for `FocusTextSync`.
//
//  - One `AXObserver` per front-app pid, re-created when another app
//    activates (`NSWorkspace.didActivateApplicationNotification`). On the
//    app element: `kAXFocusedUIElementChangedNotification`. On the focused
//    element: `kAXValueChangedNotification`,
//    `kAXSelectedTextChangedNotification`,
//    `kAXUIElementDestroyedNotification`; moved when the focus moves.
//  - Everything runs on one dedicated thread with its own run loop (the
//    observer's source is added there): never the main actor, never the
//    Swift concurrency pool, whose threads mustn't block on another
//    process. Every element gets a 0.1 s messaging timeout, so a hung app
//    costs this thread 0.1 s a call and nothing else.
//  - Callbacks only note the change; Core's `TextSyncPacer` turns a burst
//    into at most 30 reads a second (leading edge, one trailing) and
//    `onChange` asks `FocusTextSync` to read.
//  - The geometry poll in `FocusTracker` stays: nothing notifies when a
//    field's window moves, and it doubles as a safety net for missed
//    notifications (`FocusTextSync.pollTick`).
//
//  Privacy (`TextSyncPolicy.readability`, checked before any value is
//  read): nothing while the Mac is locked, nothing under secure event input
//  (`IsSecureEventInputEnabled`, TN2150), never a password field, never
//  web or Electron content (`AXWebArea` ancestors; Phase 2), never a
//  terminal. Text is read as a window of ≤ 1 000 UTF-16 units with
//  `AXStringForRange`, never `AXValue` of a long field.
//
//  Writing: only the selection (`kAXSelectedTextRangeAttribute`, where
//  settable). The replacement is **typed** by `TypingQueue`; `AXValue` is
//  never set.
//

import AppKit
import ApplicationServices
import Carbon
import Foundation

final class FocusTextObserver: @unchecked Sendable {
    /// The app in front.
    struct Front: Sendable, Equatable {
        let pid: pid_t
        let name: String?
        let bundleID: String?
    }

    /// One reading of the focused field.
    struct Reading: Sendable {
        /// The process and element, hashed; `nil` without a field.
        let elementKey: UInt64?
        let reading: TextRevisionTracker.Reading
    }

    private static let messagingTimeout: Float = 0.1
    private static let maxAncestors = 40
    /// `AXValue` is read only for fields up to this long; longer ones by
    /// range (`RD` §5, huge fields).
    private static let maxValueRead = 20_000

    /// Called on the observer's thread, paced to 30 a second.
    var onChange: (@Sendable () -> Void)?

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    // Confined to the thread.
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedElement: AXUIElement?
    private var pacer = TextSyncPacer()
    private var lastElement: AXUIElement?
    private var lastElementInWeb = false
    private var activationToken: NSObjectProtocol?

    init() {}

    // MARK: Life

    /// Starts the thread and follows the front app.
    func start(front: Front?) {
        if thread == nil {
            let thread = Thread { [weak self] in
                guard let self else { return }
                self.runLoop = CFRunLoopGetCurrent()
                // A source keeps the run loop alive with nothing observed.
                var context = CFRunLoopSourceContext()
                let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
                CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
                self.ready.signal()
                CFRunLoopRun()
            }
            thread.name = "com.widgetsflow.pixelhand.focus-text"
            thread.qualityOfService = .userInitiated
            self.thread = thread
            thread.start()
            ready.wait()
            activationToken = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] note in
                guard let self else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let front = app.map { Front(pid: $0.processIdentifier, name: $0.localizedName, bundleID: $0.bundleIdentifier) }
                self.perform { self.follow(front) }
            }
        }
        perform { [weak self] in self?.follow(front) }
    }

    /// Stops observing (the last remote stopped wanting text).
    func stop() {
        if let activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(activationToken)
            self.activationToken = nil
        }
        perform { [weak self] in
            self?.tearDown()
            self?.pacer.reset()
            self?.lastElement = nil
        }
    }

    // MARK: Work on the thread

    /// Runs `block` on the observer's thread.
    func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func onThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            guard runLoop != nil else {
                continuation.resume(returning: work())
                return
            }
            perform { continuation.resume(returning: work()) }
        }
    }

    /// One reading of the focused field. `previousStart` keeps the window
    /// still while the caret stays clear of its edges.
    func read(front: Front?, lock: MacLockState, previousStart: Int?) async -> Reading {
        await onThread { [self] in self.look(front: front, lock: lock, previousStart: previousStart) }
    }

    /// `length` units of the field from `start`, as UTF-16.
    func span(_ range: PixelHandCore.TextRange) async -> [UInt16]? {
        await onThread { [self] in
            guard let element = self.focusedElement() else { return nil }
            return Self.string(element, range: range).map { Array($0.utf16) }
        }
    }

    /// Sets the field's selection through Accessibility. Returns whether
    /// it took (read back).
    func select(_ range: PixelHandCore.TextRange) async -> Bool {
        await onThread { [self] in
            guard let element = self.focusedElement() else { return false }
            var cfRange = CFRange(location: range.start, length: range.length)
            guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
            guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
            guard let now = Self.range(element, kAXSelectedTextRangeAttribute) else { return true }
            return now.location == range.start && now.length == range.length
        }
    }

    /// Whether any app has secure event input on (a password prompt,
    /// `sudo` in Terminal): nothing is read and edits are refused.
    static func secureInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    // MARK: Observer

    private func follow(_ front: Front?) {
        guard front?.pid != observedPID else { return }
        tearDown()
        guard let front else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<FocusTextObserver>.fromOpaque(refcon).takeUnretainedValue()
            me.noted(notification as String)
        }
        guard AXObserverCreate(front.pid, callback, &created) == .success, let created else {
            DeckHandLog.context.info("Focus text: no observer for pid \(front.pid, privacy: .public)")
            return
        }
        observer = created
        observedPID = front.pid
        let app = AXUIElementCreateApplication(front.pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, app, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        watchFocusedElement()
        noted(kAXFocusedUIElementChangedNotification)
    }

    private func tearDown() {
        if let observer {
            if let observedElement { removeElementNotifications(observer, observedElement) }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = nil
        observedElement = nil
    }

    /// Moves the element notifications to the element that has focus now.
    private func watchFocusedElement() {
        guard let observer else { return }
        let focused = focusedElement()
        if let observedElement, let focused, CFEqual(observedElement, focused) { return }
        if let observedElement { removeElementNotifications(observer, observedElement) }
        observedElement = focused
        guard let focused else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, focused, name as CFString, refcon)
        }
    }

    private func removeElementNotifications(_ observer: AXObserver, _ element: AXUIElement) {
        for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification, kAXUIElementDestroyedNotification] {
            AXObserverRemoveNotification(observer, element, name as CFString)
        }
    }

    /// A notification (on the thread): only note it; the pacer decides
    /// when to read.
    private func noted(_ name: String) {
        if name == kAXFocusedUIElementChangedNotification || name == kAXUIElementDestroyedNotification {
            if name == kAXUIElementDestroyedNotification { observedElement = nil }
            watchFocusedElement()
        }
        let now = CFAbsoluteTimeGetCurrent()
        switch pacer.note(now: now) {
        case .sendNow:
            onChange?()
        case let .sendAt(at):
            let timer = CFRunLoopTimerCreateWithHandler(nil, at, 0, 0, 0) { [weak self] _ in
                guard let self, self.pacer.fire(now: CFAbsoluteTimeGetCurrent()) else { return }
                self.onChange?()
            }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        case .wait:
            break
        }
    }

    // MARK: One look

    private func look(front: Front?, lock: MacLockState, previousStart: Int?) -> Reading {
        func unreadable(_ reason: TextReadability, key: UInt64? = nil) -> Reading {
            Reading(elementKey: key, reading: .init(readable: reason, window: nil, length: 0, selection: .caret(0), canSetSelection: false, canEdit: false))
        }
        // Locked or secure input: no Accessibility at all.
        if lock.isLocked { return unreadable(.locked) }
        if Self.secureInputEnabled() { return unreadable(.secure) }

        let element = focusedElement()
        let role = element.flatMap { Self.stringValue($0, kAXRoleAttribute) }
        let subrole = element.flatMap { Self.stringValue($0, kAXSubroleAttribute) }
        let key = element.map { Self.key($0, pid: front?.pid ?? 0) }
        // Role, subrole and web ancestry first: a password or web field's
        // value is never asked for.
        let preliminary = TextSyncPolicy.readability(
            lock: lock, secureInput: false, hasFocus: element != nil, axRole: role, axSubrole: subrole,
            inWebContent: element.map(isInWebContent) ?? false, appName: front?.name, bundleID: front?.bundleID,
            characterCount: nil, hasInsertionPointLine: true
        )
        guard preliminary == .yes, let element else { return unreadable(preliminary, key: key) }

        let count = Self.int(element, kAXNumberOfCharactersAttribute)
        let hasLine = Self.int(element, kAXInsertionPointLineNumberAttribute) != nil
        let readable = TextSyncPolicy.readability(
            lock: lock, secureInput: false, hasFocus: true, axRole: role, axSubrole: subrole,
            inWebContent: false, appName: front?.name, bundleID: front?.bundleID,
            characterCount: count, hasInsertionPointLine: hasLine
        )
        guard readable == .yes else { return unreadable(readable, key: key) }

        let selected = Self.range(element, kAXSelectedTextRangeAttribute)
        let canSetSelection = Self.isSettable(element, kAXSelectedTextRangeAttribute)
        let canEdit = Self.isSettable(element, kAXValueAttribute)
            && (Self.bool(element, kAXEnabledAttribute) ?? true)

        // The field's length, and its value only when that's short.
        var length = count
        var shortValue: String?
        if length == nil || (length ?? 0) <= Self.maxValueRead {
            if let value = Self.stringValue(element, kAXValueAttribute), value.utf16.count <= Self.maxValueRead {
                shortValue = value
                length = value.utf16.count
            }
        }
        guard let length else { return unreadable(.noField, key: key) }
        let selection = selected.map { PixelHandCore.TextRange(start: $0.location, length: $0.length) } ?? .caret(length)
        let windowRange = TextSyncPolicy.window(fieldLength: length, selection: selection, previousStart: previousStart)
        let units: [UInt16]
        if let shortValue {
            let all = Array(shortValue.utf16)
            units = Array(all[min(windowRange.start, all.count)..<min(windowRange.end, all.count)])
        } else if let text = Self.string(element, range: windowRange) {
            units = Array(text.utf16)
        } else {
            return unreadable(.noField, key: key)
        }
        let aligned = TextUnits.aligned(units, start: windowRange.start)
        let window = TextWindow(start: aligned.start, value: String(decoding: aligned.units, as: UTF16.self))
        return Reading(elementKey: key, reading: .init(
            readable: .yes,
            window: window,
            length: length,
            selection: selection,
            canSetSelection: canSetSelection,
            canEdit: canEdit
        ))
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        var element = Self.element(systemWide, kAXFocusedUIElementAttribute)
        if element == nil, let pid = observedPID {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
            element = Self.element(app, kAXFocusedUIElementAttribute)
        }
        if let element { AXUIElementSetMessagingTimeout(element, Self.messagingTimeout) }
        return element
    }

    /// Whether `element` sits inside an `AXWebArea` (cached per element).
    private func isInWebContent(_ element: AXUIElement) -> Bool {
        if let lastElement, CFEqual(lastElement, element) { return lastElementInWeb }
        var current: AXUIElement? = element
        var inWeb = false
        for _ in 0..<Self.maxAncestors {
            guard let node = current else { break }
            AXUIElementSetMessagingTimeout(node, Self.messagingTimeout)
            if Self.stringValue(node, kAXRoleAttribute) == "AXWebArea" {
                inWeb = true
                break
            }
            current = Self.element(node, kAXParentAttribute)
        }
        lastElement = element
        lastElementInWeb = inWeb
        return inWeb
    }

    private static func key(_ element: AXUIElement, pid: pid_t) -> UInt64 {
        (UInt64(UInt32(bitPattern: pid)) << 32) ^ UInt64(UInt(bitPattern: CFHash(element)))
    }

    // MARK: AX helpers

    private static func string(_ element: AXUIElement, range: PixelHandCore.TextRange) -> String? {
        var cfRange = CFRange(location: range.start, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &out) == .success else { return nil }
        return out as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.intValue
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.boolValue
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    private static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let value = ref as! AXValue
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }
}
