//
//  MenuPath.swift
//  PixelHandCore
//
//  How a stored `menuCommand` path finds its menu item. Menus are read
//  through Accessibility on the Mac (`MenuCommandPresser`); this is the
//  pure part: title matching and the walk's decisions, testable on Linux.
//

import Foundation

public enum MenuPath {
    /// A title as compared: trimmed, the trailing ellipsis ("…" or "...")
    /// dropped, case and diacritics folded. "Export…" matches "export".
    public static func normalized(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("…") { t.removeLast() }
        if t.hasSuffix("...") { t.removeLast(3) }
        return t.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whether a menu element titled `candidate` is the path component
    /// `wanted`.
    public static func matches(_ candidate: String, _ wanted: String) -> Bool {
        let c = normalized(candidate)
        return !c.isEmpty && c == normalized(wanted)
    }

    /// Of `titles` (one menu's children, in order), the index to follow
    /// for `wanted`: the first exact title, else the first normalised match.
    public static func index(of wanted: String, in titles: [String]) -> Int? {
        if let exact = titles.firstIndex(of: wanted) { return exact }
        return titles.firstIndex { matches($0, wanted) }
    }

    /// The path an imported `AppShortcutBinding` stands for, when its
    /// display name carries one ("File › New Tab" → `["File", "New Tab"]`).
    /// Used to offer "press the menu item" for a chip whose shortcut the
    /// user later rebinds.
    public static func path(fromDisplayName name: String) -> [String]? {
        let parts = name.components(separatedBy: " › ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts
    }
}
