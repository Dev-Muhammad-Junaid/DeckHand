//
//  ActionLibrary.swift
//  PixelHandCore
//
//  The deck editor's action library (UX-020, D3): every kind of `Action` a
//  key can store, grouped into sections, each with a glyph, a title, one
//  line of help and the fields the inspector asks for. Dialog presses
//  (`contextAction`) aren't here: a key can't store one
//  (`ActionValidation.Issue.contextActionNotStorable`); they live on the
//  context strip.
//

import Foundation

public enum ActionKind: String, CaseIterable, Sendable, Identifiable {
    case shortcut
    case appShortcut
    case menuCommand
    case launchApp
    case system
    case media
    case macShortcut
    case sequence

    public var id: String { rawValue }

    /// The kind `action` is, or `nil` for a dialog press.
    public init?(_ action: Action) {
        switch action {
        case .shortcut: self = .shortcut
        case .appShortcut: self = .appShortcut
        case .menuCommand: self = .menuCommand
        case .launchApp: self = .launchApp
        case .system: self = .system
        case .media: self = .media
        case .macShortcut: self = .macShortcut
        case .sequence: self = .sequence
        case .contextAction: return nil
        }
    }

    public var title: String {
        switch self {
        case .shortcut: "Key press"
        case .appShortcut: "Key press in an app"
        case .menuCommand: "Menu command"
        case .launchApp: "Open an app"
        case .system: "Mac action"
        case .media: "Media key"
        case .macShortcut: "Mac Shortcut"
        case .sequence: "Sequence"
        }
    }

    public var help: String {
        switch self {
        case .shortcut: "Presses a key combination in the app in front."
        case .appShortcut: "Brings an app forward, then presses a key combination."
        case .menuCommand: "Picks a menu item by name. Works even if its shortcut changes."
        case .launchApp: "Opens an app, or brings it forward."
        case .system: "Mission Control, Show Desktop, Launchpad and more."
        case .media: "Play, pause and skip on the Mac."
        case .macShortcut: "Runs a shortcut from the Shortcuts app on the Mac."
        case .sequence: "Runs several actions in order, with pauses."
        }
    }

    /// The board name of the kind's glyph.
    public var glyphName: String {
        switch self {
        case .shortcut: "keyboard"
        case .appShortcut: "type"
        case .menuCommand: "deck"
        case .launchApp: "laptop"
        case .system: "mission"
        case .media: "play"
        case .macShortcut: "run"
        case .sequence: "build"
        }
    }

    public var glyph: GlyphBitmap { PixelGlyphs.named(glyphName) ?? PixelGlyphs.deck }

    /// A starting action of this kind; the inspector fills in the rest.
    /// `frontBundleID` seeds app-bound kinds with the app in front.
    public func template(frontBundleID: String?) -> Action {
        let app = frontBundleID ?? "com.apple.finder"
        switch self {
        case .shortcut: return .shortcut(keys: ["cmd", "c"])
        case .appShortcut: return .appShortcut(bundleID: app, keys: ["cmd", "n"])
        case .menuCommand: return .menuCommand(bundleID: app, path: ["File", "New"])
        case .launchApp: return .launchApp(bundleID: app)
        case .system: return .system(action: .missionControl)
        case .media: return .media(key: .playPause)
        case .macShortcut: return .macShortcut(name: "")
        case .sequence:
            return .sequence(steps: [
                .run(action: .launchApp(bundleID: app)),
                .delay(milliseconds: 500),
                .run(action: .shortcut(keys: ["cmd", "n"])),
            ])
        }
    }
}

/// One ready-made entry in the library: a whole action, not a kind.
public struct ActionPreset: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let glyphName: String
    public let action: Action

    public init(id: String, title: String, glyphName: String, action: Action) {
        self.id = id
        self.title = title
        self.glyphName = glyphName
        self.action = action
    }

    public var glyph: GlyphBitmap { PixelGlyphs.named(glyphName) ?? DeckGlyphs.glyph(for: action) }
}

public enum ActionLibrary {
    public struct Section: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let presets: [ActionPreset]
    }

    /// The library's sections for an app in front (`frontBundleID`, named
    /// `frontAppName`): that app's curated presets first, then the Mac's
    /// actions and media keys. Custom kinds are listed separately
    /// (`ActionKind.allCases`).
    public static func sections(frontBundleID: String?, frontAppName: String?) -> [Section] {
        var sections: [Section] = []
        if let frontBundleID {
            let curated = CuratedShortcuts.bindings(for: frontBundleID).map { binding in
                ActionPreset(
                    id: "curated." + binding.id,
                    title: binding.displayName,
                    glyphName: DeckGlyphs.glyph(forSymbol: binding.sfSymbol)?.name ?? "keyboard",
                    action: .appShortcut(bundleID: frontBundleID, keys: binding.keys)
                )
            }
            if !curated.isEmpty {
                sections.append(Section(id: "app", title: frontAppName ?? "This app", presets: curated))
            }
        }
        let system = SystemMacro.allCases.map { macro in
            ActionPreset(id: "system." + macro.rawValue, title: macro.title, glyphName: DeckGlyphs.glyph(for: .system(action: macro)).name, action: .system(action: macro))
        }
        sections.append(Section(id: "mac", title: "Mac", presets: system))
        let media = MediaKey.allCases.map { key in
            ActionPreset(id: "media." + key.rawValue, title: key.title, glyphName: DeckGlyphs.glyph(for: .media(key: key)).name, action: .media(key: key))
        }
        sections.append(Section(id: "media", title: "Media", presets: media))
        return sections
    }

    /// Presets whose title contains `query` (case and diacritics folded).
    public static func filter(_ sections: [Section], query: String) -> [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sections }
        return sections.compactMap { section in
            let hits = section.presets.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return hits.isEmpty ? nil : Section(id: section.id, title: section.title, presets: hits)
        }
    }
}

// MARK: - Editing helpers for the inspector

extension Action {
    /// The same action as another kind, keeping what carries over (the app,
    /// the keys), for the inspector's kind picker.
    public func converted(to kind: ActionKind, frontBundleID: String?) -> Action {
        if ActionKind(self) == kind { return self }
        let app = bundleID ?? frontBundleID
        let keys = chordKeys
        switch kind {
        case .shortcut: return .shortcut(keys: keys ?? ["cmd", "c"])
        case .appShortcut: return .appShortcut(bundleID: app ?? "com.apple.finder", keys: keys ?? ["cmd", "n"])
        case .launchApp: return .launchApp(bundleID: app ?? "com.apple.finder")
        case .menuCommand: return .menuCommand(bundleID: app ?? "com.apple.finder", path: ["File", "New"])
        default: return kind.template(frontBundleID: app)
        }
    }

    /// The app this action is tied to, if any.
    public var bundleID: String? {
        switch self {
        case let .appShortcut(bundleID, _), let .launchApp(bundleID), let .menuCommand(bundleID, _): bundleID
        default: nil
        }
    }

    /// The chord keys, for key presses.
    public var chordKeys: [String]? {
        switch self {
        case let .shortcut(keys), let .appShortcut(_, keys): keys
        default: nil
        }
    }
}

public enum ChordParsing {
    /// Modifier names in the order the Mac expects them.
    public static let modifiers = ["cmd", "shift", "option", "ctrl"]

    /// Builds a chord from modifier flags and one key ("t", "f5", "space").
    /// The key is lower-cased and trimmed; an empty key gives `nil`.
    public static func chord(modifiers active: Set<String>, key: String) -> [String]? {
        let key = key.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, key.utf8.count <= ActionLimits.maxKeyNameBytes else { return nil }
        return modifiers.filter(active.contains) + [key]
    }

    /// Splits a chord back into its modifiers and its key.
    public static func split(_ keys: [String]) -> (modifiers: Set<String>, key: String) {
        let mods = Set(keys.filter { modifiers.contains($0) || $0 == "command" || $0 == "control" || $0 == "alt" }
            .map { $0 == "command" ? "cmd" : $0 == "control" ? "ctrl" : $0 == "alt" ? "option" : $0 })
        let key = keys.last { !(modifiers.contains($0) || ["command", "control", "alt"].contains($0)) } ?? ""
        return (mods, key)
    }
}
