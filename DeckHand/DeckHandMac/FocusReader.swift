//
//  FocusReader.swift
//  DeckHandMac
//
//  Reads the focused text field through Accessibility for `FocusTracker`
//  (OT-12, OT-13). Everything here runs on one serial queue, never on the
//  main actor or the Swift concurrency pool, whose threads mustn't block on
//  another process; every element gets a 0.1 s messaging timeout.
//
//  One look:
//  1. The system-wide element's `AXFocusedUIElement` (the front app's, if
//     the system-wide one has none).
//  2. Its role and subrole, `AXPosition` and `AXSize` (Quartz global
//     points, top-left origin, y down, the same space as `CGDisplayBounds`).
//  3. The caret: `AXSelectedTextRange` + `AXBoundsForRange` (native text;
//     a zero-length range that answers an empty rect is retried on the
//     character before or after it), else `AXSelectedTextMarkerRange` +
//     `AXBoundsForTextMarkerRange` (WebKit and Chromium web content).
//     These are attribute names, not symbols: nothing private is linked.
//  4. The display it's on (`CGGetActiveDisplayList` / `CGDisplayBounds`)
//     and local top-left points (Core `FocusReading.display` / `local`).
//  5. Text, only when `FocusReading.mayReadText` says so (native text role,
//     not a password field, not inside an `AXWebArea`, Mac unlocked): the
//     role and subrole are checked before any value is read. At most
//     1 000 UTF-16 units around the caret, read with `AXStringForRange`
//     when the field is longer, so a long document isn't copied 8 times a
//     second.
//  6. No usable frame (many web and Electron fields, or a non-text
//     element without a caret): `source = .pointer` with the pointer's
//     square only.
//
//  Electron apps build their Accessibility tree only for assistive tools.
//  While a remote watches, the reader sets `AXManualAccessibility` on the
//  front app's element once if the app bundles Electron and the attribute
//  isn't already on; Electron documents this attribute for third-party
//  assistive apps, and it does nothing in other apps. It is turned off
//  again when the last remote stops watching, only for the apps this
//  reader turned on. `AXEnhancedUserInterface` (what VoiceOver sets) is
//  never set: in AppKit apps it slows window animations and confuses
//  window managers. Set the user default `PHFocusElectronAccessibility` to
//  NO to stop it. Known side effect: an Electron app may notice an
//  assistive tool (VS Code can offer its screen reader mode).
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class FocusReader: @unchecked Sendable {
    /// The app in front, read on the main actor.
    struct Frontmost: Sendable {
        let pid: pid_t
        let name: String?
        let bundlePath: String?
    }

    /// Per-call messaging timeout: an app that doesn't answer costs this,
    /// not the system's ~6 s.
    private static let messagingTimeout: Float = 0.1
    /// Most parents walked looking for an `AXWebArea`.
    private static let maxAncestors = 40
    private static let electronDefaultsKey = "PHFocusElectronAccessibility"
    private static let manualAccessibility = "AXManualAccessibility"

    private let queue = DispatchQueue(label: "com.widgetsflow.pixelhand.focus", qos: .userInitiated)

    // Confined to `queue`.
    private var checkedPIDs: Set<pid_t> = []
    private var manualAccessibilityPIDs: [pid_t: AXUIElement] = [:]
    private var lastElement: AXUIElement?
    private var lastElementInWeb = false

    @MainActor
    static func frontmost() -> Frontmost? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Frontmost(pid: app.processIdentifier, name: app.localizedName, bundlePath: app.bundleURL?.path)
    }

    /// "Nothing to show" on the main display. Reads no Accessibility.
    static func nothing() -> FocusedFieldSnapshot {
        let id = CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        return .nothing(displayID: id, displayWidth: Double(bounds.width), displayHeight: Double(bounds.height))
    }

    /// One look, on the reader's queue.
    func read(front: Frontmost?) async -> FocusedFieldSnapshot {
        await withCheckedContinuation { (continuation: CheckedContinuation<FocusedFieldSnapshot, Never>) in
            queue.async {
                continuation.resume(returning: self.look(front: front))
            }
        }
    }

    /// The last remote stopped watching: turn `AXManualAccessibility` back
    /// off where this reader turned it on, and forget cached elements.
    func endWatch() {
        queue.async {
            for (pid, app) in self.manualAccessibilityPIDs {
                let result = AXUIElementSetAttributeValue(app, Self.manualAccessibility as CFString, kCFBooleanFalse)
                DeckHandLog.context.info("Focus: AXManualAccessibility off for pid \(pid, privacy: .public): \(result.rawValue, privacy: .public)")
            }
            self.manualAccessibilityPIDs.removeAll()
            self.checkedPIDs.removeAll()
            self.lastElement = nil
            self.lastElementInWeb = false
        }
    }

    // MARK: - One look (on `queue`)

    private func look(front: Frontmost?) -> FocusedFieldSnapshot {
        let displays = Self.activeDisplays()
        let pointer = CGEvent(source: nil)?.location
        let pointerRect = pointer.map { FocusRect.around(x: Double($0.x), y: Double($0.y), size: FocusReading.pointerSize) }

        if let front { enableElectronAccessibilityIfNeeded(front) }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        var focused: AXUIElement? = Self.element(systemWide, kAXFocusedUIElementAttribute)
        if focused == nil, let front {
            let app = AXUIElementCreateApplication(front.pid)
            AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
            focused = Self.element(app, kAXFocusedUIElementAttribute)
        }

        var axRole: String?
        var axSubrole: String?
        var field: FocusRect?
        var caret: FocusRect?
        var selection: CFRange?
        if let focused {
            AXUIElementSetMessagingTimeout(focused, Self.messagingTimeout)
            axRole = Self.string(focused, kAXRoleAttribute)
            axSubrole = Self.string(focused, kAXSubroleAttribute)
            field = Self.frame(focused).flatMap { FocusReading.isUsable($0) ? $0 : nil }
            selection = Self.range(focused, kAXSelectedTextRangeAttribute)
            caret = Self.caret(focused, selection: selection)
        }
        let role = FocusReading.role(axRole: axRole, axSubrole: axSubrole)

        // An element counts when it has a caret, or is a text role with a
        // frame. A focused button or window frame would only mislead.
        let isText = role == .textField || role == .textArea || role == .comboBox
        let source: FocusedFieldSnapshot.Source
        if caret != nil || (isText && field != nil) {
            source = .accessibility
        } else if pointerRect != nil {
            source = .pointer
            field = nil
            caret = nil
        } else {
            return Self.nothing()
        }

        guard let anchor = (source == .accessibility ? (field ?? caret) : pointerRect),
              let display = FocusReading.display(for: anchor, among: displays) else {
            return Self.nothing()
        }

        var text: FocusedText?
        if source == .accessibility, let focused,
           FocusReading.mayReadText(axRole: axRole, axSubrole: axSubrole, inWebContent: false, lock: .unlocked),
           !isInWebContent(focused) {
            // The tracker never calls `read` while locked and drops a
            // reading taken across a lock, hence `.unlocked` here.
            text = Self.text(focused, selection: selection)
        }

        return FocusedFieldSnapshot(
            displayID: display.id,
            displayWidth: display.bounds.width,
            displayHeight: display.bounds.height,
            field: field.map { FocusReading.local($0, on: display) },
            caret: caret.map { FocusReading.local($0, on: display) },
            pointer: pointerRect.map { FocusReading.local($0, on: display) },
            source: source,
            app: front?.name,
            role: role,
            text: text
        )
    }

    // MARK: Electron

    private func enableElectronAccessibilityIfNeeded(_ front: Frontmost) {
        guard !checkedPIDs.contains(front.pid) else { return }
        checkedPIDs.insert(front.pid)
        guard UserDefaults.standard.object(forKey: Self.electronDefaultsKey) as? Bool ?? true,
              let path = front.bundlePath,
              FileManager.default.fileExists(atPath: path + "/Contents/Frameworks/Electron Framework.framework") else { return }
        let app = AXUIElementCreateApplication(front.pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        var current: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, Self.manualAccessibility as CFString, &current) == .success,
           (current as? NSNumber)?.boolValue == true {
            return // already on (another assistive tool): leave it alone
        }
        let result = AXUIElementSetAttributeValue(app, Self.manualAccessibility as CFString, kCFBooleanTrue)
        if result == .success {
            manualAccessibilityPIDs[front.pid] = app
        }
        DeckHandLog.context.info("Focus: AXManualAccessibility on for \(front.name ?? "?", privacy: .public): \(result.rawValue, privacy: .public)")
    }

    // MARK: Web content

    /// Whether `element` sits inside an `AXWebArea`. Cached for the last
    /// focused element, so the walk happens once per focus change.
    private func isInWebContent(_ element: AXUIElement) -> Bool {
        if let lastElement, CFEqual(lastElement, element) { return lastElementInWeb }
        var current: AXUIElement? = element
        var inWeb = false
        for _ in 0..<Self.maxAncestors {
            guard let node = current else { break }
            AXUIElementSetMessagingTimeout(node, Self.messagingTimeout)
            if Self.string(node, kAXRoleAttribute) == "AXWebArea" {
                inWeb = true
                break
            }
            current = Self.element(node, kAXParentAttribute)
        }
        lastElement = element
        lastElementInWeb = inWeb
        return inWeb
    }

    // MARK: Caret

    private static func caret(_ element: AXUIElement, selection: CFRange?) -> FocusRect? {
        if let selection {
            if let rect = bounds(element, selection), FocusReading.isUsable(rect), selection.length > 0 || rect.width < 4 {
                return rect
            }
            if selection.length == 0 {
                if selection.location > 0,
                   let before = bounds(element, CFRange(location: selection.location - 1, length: 1)),
                   FocusReading.isUsable(before) {
                    return FocusReading.caret(after: before)
                }
                if let after = bounds(element, CFRange(location: selection.location, length: 1)),
                   FocusReading.isUsable(after) {
                    return FocusReading.caret(before: after)
                }
            }
        }
        // Web content: text markers.
        var marker: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &marker) == .success,
           let marker,
           let rect = parameterizedRect(element, "AXBoundsForTextMarkerRange", marker),
           FocusReading.isUsable(rect) {
            return rect
        }
        return nil
    }

    private static func bounds(_ element: AXUIElement, _ range: CFRange) -> FocusRect? {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        return parameterizedRect(element, kAXBoundsForRangeParameterizedAttribute, value)
    }

    private static func parameterizedRect(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> FocusRect? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &out) == .success,
              let value = axValue(out), AXValueGetType(value) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return focusRect(rect)
    }

    // MARK: Text

    private static func text(_ element: AXUIElement, selection: CFRange?) -> FocusedText? {
        let count = int(element, kAXNumberOfCharactersAttribute)
        if let count, count > FocusReading.maxTextLength {
            let start = selection.map { Int($0.location) } ?? count
            let window = FocusReading.textWindow(count: count, selectionStart: start)
            var range = CFRange(location: window.location, length: window.length)
            guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
            var out: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &out) == .success,
                  let string = out as? String else { return nil }
            return FocusReading.text(
                window: string,
                windowLocation: window.location,
                totalCount: count,
                selectionStart: start,
                selectionLength: selection.map { Int($0.length) } ?? 0
            )
        }
        guard let value = string(element, kAXValueAttribute) else { return nil }
        let total = value.utf16.count
        let start = selection.map { Int($0.location) } ?? total
        let window = FocusReading.textWindow(count: total, selectionStart: start)
        let windowed: String
        if window.location == 0, window.length == total {
            windowed = value
        } else {
            // Field didn't report its length: cut here, on UTF-16 offsets.
            let utf16 = value.utf16
            let lower = utf16.index(utf16.startIndex, offsetBy: window.location)
            let upper = utf16.index(lower, offsetBy: window.length)
            windowed = String(utf16[lower..<upper]) ?? String(value[lower..<upper])
        }
        return FocusReading.text(
            window: windowed,
            windowLocation: window.location,
            totalCount: total,
            selectionStart: start,
            selectionLength: selection.map { Int($0.length) } ?? 0
        )
    }

    // MARK: Displays

    private static func activeDisplays() -> [FocusReading.Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        let capacity = count
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard CGGetActiveDisplayList(capacity, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            let b = CGDisplayBounds(id)
            return FocusReading.Display(id: id, bounds: FocusRect(x: Double(b.origin.x), y: Double(b.origin.y), width: Double(b.width), height: Double(b.height)))
        }
    }

    // MARK: AX helpers

    private static func axValue(_ ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.intValue
    }

    private static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = axValue(ref), AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    private static func frame(_ element: AXUIElement) -> FocusRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = axValue(positionRef), AXValueGetType(positionValue) == .cgPoint,
              let sizeValue = axValue(sizeRef), AXValueGetType(sizeValue) == .cgSize else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return focusRect(CGRect(origin: position, size: size))
    }

    private static func focusRect(_ r: CGRect) -> FocusRect {
        FocusRect(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.width), height: Double(r.height))
    }
}
