//
//  AskVocabulary.swift
//  PixelHandCore
//
//  The words Ask understands without a model: chords written out
//  ("cmd shift p", "⌘⇧P", "control-command-f"), app names ("Safari",
//  "VS Code"), and everyday commands ("new tab", "mission control"). Both
//  the deterministic parser and the on-device plan resolver use them, so a
//  model's "Command+T" or "Chrome" lands on the same wire names and
//  bundle IDs.
//

import Foundation

// MARK: - Chords

public enum ChordParser {
    /// The wire name for one written key, or `nil` when it isn't a key
    /// `KeyTable` knows.
    public static func canonical(_ raw: String) -> String {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch s {
        case "⌘", "cmd", "command", "cmnd", "apple": return "cmd"
        case "⇧", "shift": return "shift"
        case "⌥", "option", "opt", "alt": return "option"
        case "⌃", "ctrl", "control", "ctl": return "ctrl"
        case "fn", "function", "globe": return "fn"
        case "↩", "return", "enter": return "return"
        case "⇥", "tab": return "tab"
        case "⎋", "esc", "escape": return "escape"
        case "⌫", "delete", "backspace", "back space": return "delete"
        case "⌦", "forward delete", "forwarddelete": return "forwarddelete"
        case "␣", "space", "spacebar", "space bar": return "space"
        case "←", "left", "left arrow", "arrow left": return "left"
        case "→", "right", "right arrow", "arrow right": return "right"
        case "↑", "up", "up arrow", "arrow up": return "up"
        case "↓", "down", "down arrow", "arrow down": return "down"
        case "page up", "pageup", "pgup": return "pageup"
        case "page down", "pagedown", "pgdn": return "pagedown"
        case "home": return "home"
        case "end": return "end"
        case "plus": return "="
        case "minus", "dash", "hyphen": return "-"
        case "comma": return ","
        case "period", "dot", "full stop": return "."
        case "slash": return "/"
        case "backslash": return "\\"
        case "semicolon": return ";"
        case "quote", "apostrophe": return "'"
        case "backtick", "grave": return "`"
        case "left bracket": return "["
        case "right bracket": return "]"
        default: return s
        }
    }

    /// Parses a written chord into wire names, modifiers first in press
    /// order. `nil` unless it resolves to exactly one key (`KeyTable.chord`).
    ///
    ///     parse("cmd shift p")        → ["cmd", "shift", "p"]
    ///     parse("⌘⇧P")                → ["cmd", "shift", "p"]
    ///     parse("Control-Command-F")  → ["cmd", "ctrl", "f"]
    ///     parse("return")             → ["return"]
    public static func parse(_ text: String) -> [String]? {
        var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source.count <= 64 else { return nil }
        // Multi-word key names first, so "page up" isn't "page" + "up".
        for phrase in ["forward delete", "back space", "space bar", "page up", "page down",
                       "left arrow", "right arrow", "up arrow", "down arrow",
                       "left bracket", "right bracket", "full stop"] {
            let joined = phrase.replacingOccurrences(of: " ", with: "_")
            source = source.replacingOccurrences(of: phrase, with: joined, options: .caseInsensitive)
        }
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current.replacingOccurrences(of: "_", with: " ")); current = "" }
        }
        for character in source {
            if "⌘⇧⌥⌃↩⇥⎋⌫⌦␣←→↑↓".contains(character) {
                flush()
                tokens.append(String(character))
            } else if character == " " || character == "+" || (character == "-" && !current.isEmpty) {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()
        // "⌘⇧P": a trailing single glyph-run letter arrives as its own token.
        var modifiers: [KeyModifier] = []
        var key: String?
        for token in tokens {
            let name = canonical(token)
            if let modifier = KeyModifier.named(name) {
                if !modifiers.contains(modifier) { modifiers.append(modifier) }
            } else if KeyTable.keyCode(for: name) != nil {
                guard key == nil else { return nil }
                key = name == " " ? "space" : name
            } else {
                return nil
            }
        }
        guard let key else { return nil }
        let ordered = KeyModifier.pressOrder.filter(modifiers.contains).map(\.askWireName)
        return ordered + [key]
    }
}

extension KeyModifier {
    /// The wire name Ask writes for this modifier.
    var askWireName: String {
        switch self {
        case .command: "cmd"
        case .shift: "shift"
        case .option: "option"
        case .control: "ctrl"
        case .function: "fn"
        }
    }
}

// MARK: - Apps

/// App names to bundle IDs: the Mac's installed apps when the remote has
/// them, then a built-in list of common apps.
public struct AskAppCatalog: Sendable {
    public struct App: Sendable, Equatable {
        public var bundleID: String
        public var name: String
        public init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    public private(set) var apps: [App]

    public init(installed: [InstalledAppInfo] = []) {
        var apps = installed.map { App(bundleID: $0.bundleID, name: $0.displayName) }
        let known = Set(apps.map(\.bundleID))
        apps += Self.builtIn.filter { !known.contains($0.bundleID) }
        self.apps = apps
    }

    /// The name to show for `bundleID`.
    public func name(for bundleID: String) -> String? {
        apps.first { $0.bundleID == bundleID }?.name
    }

    /// The app a written name means: an exact name or alias first, then
    /// the shortest name that starts with it (at least three letters).
    public func app(named raw: String) -> App? {
        let wanted = Self.normalize(raw)
        guard !wanted.isEmpty else { return nil }
        if ActionValidation.isBundleID(raw), raw.contains("."), let byID = apps.first(where: { $0.bundleID.lowercased() == raw.lowercased() }) {
            return byID
        }
        if let alias = Self.aliases[wanted], let app = apps.first(where: { $0.bundleID == alias }) {
            return app
        }
        if let exact = apps.first(where: { Self.normalize($0.name) == wanted }) {
            return exact
        }
        guard wanted.count >= 3 else { return nil }
        return apps
            .filter { Self.normalize($0.name).hasPrefix(wanted) }
            .min { $0.name.count < $1.name.count }
    }

    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for suffix in [".app", " app", " application"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count))
        }
        for prefix in ["the ", "my "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static let aliases: [String: String] = [
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "vs code": "com.microsoft.VSCode",
        "vscode": "com.microsoft.VSCode",
        "code": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode",
        "settings": "com.apple.systempreferences",
        "system preferences": "com.apple.systempreferences",
        "preferences": "com.apple.systempreferences",
        "itunes": "com.apple.Music",
        "apple music": "com.apple.Music",
        "imessage": "com.apple.MobileSMS",
        "finder": "com.apple.finder",
        "word": "com.microsoft.Word",
        "excel": "com.microsoft.Excel",
        "powerpoint": "com.microsoft.Powerpoint",
        "teams": "com.microsoft.teams2",
        "app store": "com.apple.AppStore",
        "appstore": "com.apple.AppStore",
        "facetime": "com.apple.FaceTime",
        "iterm": "com.googlecode.iterm2",
        "iterm2": "com.googlecode.iterm2",
    ]

    static let builtIn: [App] = [
        App(bundleID: "com.apple.Safari", name: "Safari"),
        App(bundleID: "com.apple.finder", name: "Finder"),
        App(bundleID: "com.apple.mail", name: "Mail"),
        App(bundleID: "com.apple.MobileSMS", name: "Messages"),
        App(bundleID: "com.apple.Notes", name: "Notes"),
        App(bundleID: "com.apple.Music", name: "Music"),
        App(bundleID: "com.apple.iCal", name: "Calendar"),
        App(bundleID: "com.apple.reminders", name: "Reminders"),
        App(bundleID: "com.apple.Photos", name: "Photos"),
        App(bundleID: "com.apple.Preview", name: "Preview"),
        App(bundleID: "com.apple.TextEdit", name: "TextEdit"),
        App(bundleID: "com.apple.Terminal", name: "Terminal"),
        App(bundleID: "com.apple.systempreferences", name: "System Settings"),
        App(bundleID: "com.apple.AppStore", name: "App Store"),
        App(bundleID: "com.apple.FaceTime", name: "FaceTime"),
        App(bundleID: "com.apple.Maps", name: "Maps"),
        App(bundleID: "com.apple.podcasts", name: "Podcasts"),
        App(bundleID: "com.apple.TV", name: "TV"),
        App(bundleID: "com.apple.shortcuts", name: "Shortcuts"),
        App(bundleID: "com.apple.calculator", name: "Calculator"),
        App(bundleID: "com.apple.ActivityMonitor", name: "Activity Monitor"),
        App(bundleID: "com.apple.iWork.Pages", name: "Pages"),
        App(bundleID: "com.apple.iWork.Keynote", name: "Keynote"),
        App(bundleID: "com.apple.iWork.Numbers", name: "Numbers"),
        App(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        App(bundleID: "com.google.Chrome", name: "Google Chrome"),
        App(bundleID: "org.mozilla.firefox", name: "Firefox"),
        App(bundleID: "company.thebrowser.Browser", name: "Arc"),
        App(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        App(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        App(bundleID: "com.figma.Desktop", name: "Figma"),
        App(bundleID: "com.spotify.client", name: "Spotify"),
        App(bundleID: "us.zoom.xos", name: "zoom.us"),
        App(bundleID: "notion.id", name: "Notion"),
        App(bundleID: "com.hnc.Discord", name: "Discord"),
    ]
}
