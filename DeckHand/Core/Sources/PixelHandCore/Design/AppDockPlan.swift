//
//  AppDockPlan.swift
//  PixelHandCore – Design
//
//  The app dock's order and marks (UX-005, `02-Design-System.md` §7
//  `AppDock`, board `.adock`). The Mac reports running apps in Cmd-Tab order,
//  which reshuffles on every switch; a dock that reorders under the thumb
//  can't be learned, so the dock keeps the Mac Dock's rule instead: an app
//  keeps its slot while it runs, new apps join at the end (in the Mac's
//  Cmd-Tab order), and quit apps leave. The first order is the Cmd-Tab order,
//  so the front app starts first.
//

import Foundation

/// One app in the dock.
public struct AppDockEntry: Hashable, Sendable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    /// The Mac's frontmost app: accent ring and a lit (mint) running dot.
    public let isFront: Bool
    /// The app is showing a dialog: a warning dot on its icon.
    public let hasDialog: Bool

    public init(bundleID: String, isFront: Bool, hasDialog: Bool) {
        self.bundleID = bundleID
        self.isFront = isFront
        self.hasDialog = hasDialog
    }
}

public enum AppDockPlan {
    /// The dock's next order. Apps in `previous` that still run keep their
    /// relative order; apps that newly run are appended in `running`'s
    /// (Cmd-Tab) order. Duplicates and empty IDs are dropped.
    public static func order(previous: [String], running: [String]) -> [String] {
        let runningSet = Set(running.filter { !$0.isEmpty })
        var seen = Set<String>()
        var result: [String] = []
        for id in previous where runningSet.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in running where !id.isEmpty && seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// The dock's entries for `order`, keeping only apps the phone can draw
    /// (`known`: apps with a name from the Mac's app list). The front app is
    /// always present, even when the running list hasn't caught up with it
    /// yet, at the end like any new app.
    public static func entries(
        order: [String],
        known: Set<String>,
        front: String?,
        frontHasDialog: Bool
    ) -> [AppDockEntry] {
        var ids = order.filter { known.contains($0) }
        if let front, known.contains(front), !ids.contains(front) {
            ids.append(front)
        }
        return ids.map { id in
            let isFront = id == front
            return AppDockEntry(bundleID: id, isFront: isFront, hasDialog: isFront && frontHasDialog)
        }
    }
}
