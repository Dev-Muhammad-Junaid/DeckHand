//
//  MenuCommandPresser.swift
//  DeckHandMac
//
//  Runs `Action.menuCommand`: finds the menu item at a stored path in an
//  app's menu bar through Accessibility and presses it (AXPress). Works
//  when the user rebinds the item's shortcut, or it has none.
//
//  Same hardening as `MenuShortcutDiscovery`'s walk (S9): a short
//  messaging timeout on every element, the bounded `MenuReadBudget`, and
//  its own serial queue, never the main actor or the cooperative pool.
//  It only follows the path (one menu per level), so it reads far fewer
//  elements than a full shortcut import. Title matching is Core's
//  `MenuPath`.
//

import AppKit
import ApplicationServices
import Foundation

enum MenuCommandPresser {
    enum Result: Equatable, Sendable {
        case pressed
        case appNotRunning
        /// No item matched `path[level]`.
        case notFound(level: Int)
        case disabled
        /// The walk hit a `MenuReadBudget` limit (a hung or huge app).
        case gaveUp
        case pressFailed
    }

    /// Tighter than a shortcut import: the remote waits on this.
    static let limits = MenuReadLimits(maxDepth: 2 * ActionLimits.maxMenuPathComponents, timeLimit: 1.0)

    /// Activates `bundleID` (launching it if needed), then presses the
    /// menu item at `path`.
    @MainActor
    static func press(bundleID: String, path: [String], launcher: AppLauncher) async -> Result {
        await launcher.activateAndWait(bundleID: bundleID, timeout: 1.0, settleDelay: 0.08)
        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?.processIdentifier else {
            return .appNotRunning
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: pressOnQueue(pid: pid, path: path))
            }
        }
    }

    /// The outcome a receipt carries.
    static func outcome(_ result: Result, path: [String]) -> ActionOutcome {
        let shown = path.joined(separator: " › ")
        switch result {
        case .pressed: return .completed
        case .appNotRunning: return .failed(reason: "The app isn't running.")
        case let .notFound(level):
            let missing = level < path.count ? path[level] : shown
            return .failed(reason: "No menu item “\(missing)” in \(shown).")
        case .disabled: return .failed(reason: "“\(shown)” is greyed out right now.")
        case .gaveUp: return .failed(reason: "The app's menus didn't answer in time.")
        case .pressFailed: return .failed(reason: "The menu item couldn't be pressed.")
        }
    }

    private static let queue = DispatchQueue(label: "com.widgetsflow.pixelhand.menu-press", qos: .userInitiated)

    private static func pressOnQueue(pid: pid_t, path: [String]) -> Result {
        var budget = MenuReadBudget(limits: limits, start: Date())
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, limits.messagingTimeout)

        var menuBarRef: CFTypeRef?
        let barError = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef)
        budget.noteRead(timedOut: barError == .cannotComplete)
        guard barError == .success, let barRef = menuBarRef, CFGetTypeID(barRef) == AXUIElementGetTypeID() else {
            return budget.isExhausted ? .gaveUp : .notFound(level: 0)
        }
        // The menu bar's children are its top menus (AXMenuBarItem); each
        // has one AXMenu child holding the items, which may have submenus.
        var container = barRef as! AXUIElement
        for (level, wanted) in path.enumerated() {
            guard budget.mayDescend(toDepth: level * 2) else { return .gaveUp }
            let children = items(of: container, budget: &budget)
            if budget.isExhausted { return .gaveUp }
            let titles = children.map { title(of: $0, budget: &budget) }
            if budget.isExhausted { return .gaveUp }
            guard let index = MenuPath.index(of: wanted, in: titles) else { return .notFound(level: level) }
            let item = children[index]
            if level == path.count - 1 {
                if !isEnabled(item, budget: &budget) { return budget.isExhausted ? .gaveUp : .disabled }
                let error = AXUIElementPerformAction(item, kAXPressAction as CFString)
                return error == .success ? .pressed : .pressFailed
            }
            // Step into the item's submenu (its single AXMenu child).
            guard let submenu = items(of: item, budget: &budget).first else {
                return budget.isExhausted ? .gaveUp : .notFound(level: level + 1)
            }
            container = submenu
        }
        return .notFound(level: 0)
    }

    private static func items(of element: AXUIElement, budget: inout MenuReadBudget) -> [AXUIElement] {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref)
        budget.noteRead(timedOut: error == .cannotComplete)
        guard error == .success, let children = ref as? [AXUIElement] else { return [] }
        let count = budget.childrenToRead(of: children.count)
        var out: [AXUIElement] = []
        for child in children.prefix(count) {
            guard budget.visitNode() else { break }
            AXUIElementSetMessagingTimeout(child, budget.limits.messagingTimeout)
            out.append(child)
        }
        return out
    }

    private static func title(of element: AXUIElement, budget: inout MenuReadBudget) -> String {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref)
        budget.noteRead(timedOut: error == .cannotComplete)
        return (ref as? String) ?? ""
    }

    private static func isEnabled(_ element: AXUIElement, budget: inout MenuReadBudget) -> Bool {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &ref)
        budget.noteRead(timedOut: error == .cannotComplete)
        // An app that doesn't report it is given the benefit of the doubt.
        return (ref as? Bool) ?? true
    }
}
