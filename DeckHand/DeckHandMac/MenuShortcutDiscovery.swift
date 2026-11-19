//
//  MenuShortcutDiscovery.swift
//  DeckHandMac
//
//  Enumerates the keyboard shortcuts advertised by a running app's menu bar
//  via the Accessibility (AX) API. We already hold AX permission for input
//  injection, so this costs nothing extra.
//
//  AX exposes menu items' shortcuts through three attributes:
//
//    • AXMenuItemCmdChar      – the literal character ("P", "F", …)
//    • AXMenuItemCmdVirtualKey – a virtual key code (for arrows / F-keys /
//                                 function-key-only bindings that have no
//                                 printable character)
//    • AXMenuItemCmdModifiers – a bitmask: bit0 shift, bit1 option, bit2
//                                 control, bit3 "NO command" (unset means
//                                 command is included)
//
//  We recurse the menu bar, skip separators / items with no shortcut, and
//  translate each into an `AppShortcutBinding` the iPad can store alongside
//  curated and user-authored bindings.
//
//  Hardened against slow and huge apps (S9):
//
//  - every element gets a short `AXUIElementSetMessagingTimeout`
//    (`MenuReadLimits.messagingTimeout`), so a busy app costs a quarter of
//    a second per call instead of the system's ~6 s;
//  - each element's five attributes are read in one round trip
//    (`AXUIElementCopyMultipleAttributeValues`);
//  - the walk is bounded by Core's `MenuReadBudget` (depth, nodes, items,
//    children per menu, wall time, consecutive time-outs); what was read
//    before a limit is still returned;
//  - it runs on its own serial queue, never on the main actor or the Swift
//    concurrency pool, whose threads mustn't block on another process.
//

import AppKit
import ApplicationServices
import Foundation

enum MenuShortcutDiscovery {
    /// Returns every keyboard-shortcut-bearing menu item in `bundleID`'s menu
    /// bar. If the app isn't running, returns an empty array — the caller is
    /// expected to launch it via `AppLauncher.activateAndWait` first.
    @MainActor
    static func discover(bundleID: String, launcher: AppLauncher) async -> [AppShortcutBinding] {
        // Make sure the app is running — an app that hasn't launched has no
        // AX menu bar to walk. We don't steal focus back afterwards; the user
        // can still dismiss it on their own.
        await launcher.activateAndWait(bundleID: bundleID, timeout: 1.5, settleDelay: 0.2)

        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?.processIdentifier else {
            return []
        }

        let rawList = await readMenuBar(pid: pid, limits: .standard)

        var bindings: [AppShortcutBinding] = []
        var seenIDs = Set<String>()
        for raw in rawList {
            guard let binding = raw.toBinding(bundleID: bundleID) else { continue }
            let dedupeKey = "\(binding.bundleID)|\(binding.displayName)|\(binding.keys.joined(separator: "+"))"
            guard !seenIDs.contains(dedupeKey) else { continue }
            seenIDs.insert(dedupeKey)
            bindings.append(binding)
        }
        return bindings
    }

    // MARK: - Raw traversal

    private struct RawMenuItem: Sendable {
        let path: [String]
        let title: String
        let cmdChar: String?
        let virtualKey: Int?
        let modifiers: Int

        func toBinding(bundleID: String) -> AppShortcutBinding? {
            guard let keys = shortcutKeys() else { return nil }
            let display = displayName()
            // Deterministic ID so re-importing doesn't duplicate entries.
            let slug = (path + [title]).joined(separator: ">").lowercased()
                .replacingOccurrences(of: " ", with: "-")
            return AppShortcutBinding(
                id: "imported.\(bundleID).\(slug)",
                bundleID: bundleID,
                displayName: display,
                keys: keys,
                sfSymbol: sfSymbolGuess(for: display),
                isCurated: false,
                category: path.first
            )
        }

        private func shortcutKeys() -> [String]? {
            var keys: [String] = []
            // Command is present unless bit 3 is set.
            let hasCmd = (modifiers & 0x08) == 0
            if hasCmd { keys.append("cmd") }
            if (modifiers & 0x01) != 0 { keys.append("shift") }
            if (modifiers & 0x02) != 0 { keys.append("option") }
            if (modifiers & 0x04) != 0 { keys.append("ctrl") }

            if let vk = virtualKey, let named = NameForVirtualKey(vk) {
                keys.append(named)
            } else if let c = cmdChar, !c.isEmpty {
                keys.append(c.lowercased())
            } else {
                return nil
            }

            // Shortcut needs at least one literal key + at least one modifier
            // for it to be interesting (plain letters don't have shortcuts).
            let hasLiteral = keys.contains { !["cmd", "shift", "option", "ctrl", "fn"].contains($0) }
            let hasModifier = keys.contains { ["cmd", "shift", "option", "ctrl", "fn"].contains($0) }
            return (hasLiteral && hasModifier) ? keys : nil
        }

        private func displayName() -> String {
            // Use parent menu as context when the leaf title is generic
            // (e.g. "New…" under File becomes "File › New…"). Keeps tiles
            // unambiguous when Cursor has three "New" entries.
            let cleaned = title.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "…", with: "")
            if let top = path.first, !top.isEmpty {
                return "\(top) › \(cleaned)"
            }
            return cleaned
        }

        private func sfSymbolGuess(for title: String) -> String {
            let t = title.lowercased()
            if t.contains("search") || t.contains("find") { return "magnifyingglass" }
            if t.contains("save") { return "square.and.arrow.down" }
            if t.contains("open") { return "folder" }
            if t.contains("new")  { return "plus.square" }
            if t.contains("close") { return "xmark.square" }
            if t.contains("tab") { return "rectangle.stack" }
            if t.contains("window") { return "macwindow" }
            if t.contains("print") { return "printer" }
            if t.contains("copy") { return "doc.on.doc" }
            if t.contains("paste") { return "doc.on.clipboard" }
            if t.contains("undo") { return "arrow.uturn.backward" }
            if t.contains("redo") { return "arrow.uturn.forward" }
            if t.contains("settings") || t.contains("preferences") { return "gearshape" }
            if t.contains("build") { return "hammer" }
            if t.contains("run") || t.contains("play") { return "play.fill" }
            if t.contains("stop") { return "stop.fill" }
            if t.contains("debug") { return "ladybug" }
            if t.contains("sidebar") { return "sidebar.left" }
            if t.contains("terminal") || t.contains("console") { return "terminal" }
            return "keyboard"
        }
    }

    /// Menu reads queue here, one at a time, off the main actor and the
    /// cooperative pool.
    private static let menuReadQueue = DispatchQueue(label: "com.widgetsflow.pixelhand.menu-read", qos: .userInitiated)

    private static func readMenuBar(pid: pid_t, limits: MenuReadLimits) async -> [RawMenuItem] {
        await withCheckedContinuation { continuation in
            menuReadQueue.async {
                let start = Date()
                var budget = MenuReadBudget(limits: limits, start: start)
                var items: [RawMenuItem] = []
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, limits.messagingTimeout)
                var menuBarRef: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef)
                budget.noteRead(timedOut: error == .cannotComplete)
                if error == .success, let ref = menuBarRef, CFGetTypeID(ref) == AXUIElementGetTypeID() {
                    walkMenuElement(ref as! AXUIElement, path: [], depth: 0, budget: &budget, into: &items)
                }
                let elapsed = Date().timeIntervalSince(start) * 1000
                if let reason = budget.stopReason {
                    DeckHandLog.context.info("Menu read for pid \(pid, privacy: .public) stopped early (\(reason.rawValue, privacy: .public)) after \(budget.nodesVisited, privacy: .public) elements, \(items.count, privacy: .public) shortcuts, \(elapsed, format: .fixed(precision: 0), privacy: .public) ms")
                } else if budget.truncatedMenus > 0 || elapsed > 1000 {
                    DeckHandLog.context.info("Menu read for pid \(pid, privacy: .public): \(budget.nodesVisited, privacy: .public) elements, \(items.count, privacy: .public) shortcuts, \(budget.truncatedMenus, privacy: .public) long menus cut, \(elapsed, format: .fixed(precision: 0), privacy: .public) ms")
                }
                continuation.resume(returning: items)
            }
        }
    }

    /// The attributes read for every element, in one round trip.
    private static let walkAttributes: [CFString] = [
        kAXTitleAttribute as CFString,
        kAXChildrenAttribute as CFString,
        kAXMenuItemCmdCharAttribute as CFString,
        kAXMenuItemCmdVirtualKeyAttribute as CFString,
        kAXMenuItemCmdModifiersAttribute as CFString,
    ]

    private static func walkMenuElement(
        _ element: AXUIElement,
        path: [String],
        depth: Int,
        budget: inout MenuReadBudget,
        into out: inout [RawMenuItem]
    ) {
        guard budget.mayDescend(toDepth: depth) else { return }
        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        budget.noteRead(timedOut: error == .cannotComplete)
        guard error == .success, let children = childrenRef as? [AXUIElement] else { return }

        let count = budget.childrenToRead(of: children.count)
        for child in children.prefix(count) {
            guard budget.visitNode() else { return }
            AXUIElementSetMessagingTimeout(child, budget.limits.messagingTimeout)

            var valuesRef: CFArray?
            let readError = AXUIElementCopyMultipleAttributeValues(child, walkAttributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef)
            budget.noteRead(timedOut: readError == .cannotComplete)
            guard !budget.isExhausted else { return }
            guard readError == .success, let values = valuesRef as? [AnyObject], values.count == walkAttributes.count else { continue }

            let title = attributeValue(values[0]) as? String ?? ""
            let grandchildren = attributeValue(values[1]) as? [AXUIElement]
            let cmdChar = attributeValue(values[2]) as? String
            let virtualKey = attributeValue(values[3]) as? Int
            let modifiers = attributeValue(values[4]) as? Int ?? 0

            if (cmdChar.map { !$0.isEmpty } ?? false) || virtualKey != nil {
                guard budget.addItem() else { return }
                out.append(RawMenuItem(
                    path: path,
                    title: title,
                    cmdChar: cmdChar,
                    virtualKey: virtualKey,
                    modifiers: modifiers
                ))
            }

            // Recurse — a menu item can still have children (a submenu).
            guard let grandchildren, !grandchildren.isEmpty else { continue }
            let childPath: [String]
            if !title.isEmpty && path.count < 2 {
                // Only keep the first two levels of path context to avoid
                // cluttering names with every submenu ancestor.
                childPath = path + [title]
            } else {
                childPath = path
            }
            walkMenuElement(child, path: childPath, depth: depth + 1, budget: &budget, into: &out)
            if budget.isExhausted { return }
        }
    }

    /// A value from `AXUIElementCopyMultipleAttributeValues`, or `nil` when
    /// that attribute came back as an error (an `AXValue` of type
    /// `.axError`: the attribute doesn't exist or timed out).
    private static func attributeValue(_ value: AnyObject) -> AnyObject? {
        if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
            return nil
        }
        return value
    }
}

/// Reverse mapping of the virtual key codes that appear in
/// `AXMenuItemCmdVirtualKey`. These are the same constants as
/// `CGKeyCode` / Carbon's `kVK_*`. We only translate the ones that make
/// sense as shortcut keys — letters/digits come through `AXMenuItemCmdChar`
/// instead, so they don't need to appear here.
private func NameForVirtualKey(_ code: Int) -> String? {
    switch code {
    case 36:  return "return"
    case 48:  return "tab"
    case 49:  return "space"
    case 51:  return "delete"
    case 53:  return "escape"
    case 76:  return "enter"
    case 96:  return "f5"
    case 97:  return "f6"
    case 98:  return "f7"
    case 99:  return "f3"
    case 100: return "f8"
    case 101: return "f9"
    case 103: return "f11"
    case 109: return "f10"
    case 111: return "f12"
    case 118: return "f4"
    case 120: return "f2"
    case 122: return "f1"
    case 123: return "left"
    case 124: return "right"
    case 125: return "down"
    case 126: return "up"
    default:  return nil
    }
}
