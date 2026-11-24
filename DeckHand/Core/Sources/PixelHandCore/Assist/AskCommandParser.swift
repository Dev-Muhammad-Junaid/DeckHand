//
//  AskCommandParser.swift
//  PixelHandCore
//
//  Ask's deterministic planner: the fallback when Apple Intelligence isn't
//  there, and what the on-device plan is checked against. It splits a
//  request into clauses ("open Safari and make a new tab" → "open Safari",
//  "make a new tab") and turns each one into steps from a fixed grammar:
//
//  - open / switch to / quit an app ("open Figma", "quit Slack")
//  - a chord written out ("press cmd shift p", "hit ⌘⇧T", "press return")
//  - everyday commands ("new tab", "reload", "select all", "zoom in")
//  - media ("play", "next song") and system actions ("mission control",
//    "lock the screen", "take a screenshot")
//  - typed text ("type hello world", `write "a, b and c"`)
//  - "run the shortcut Morning", "wait 2 seconds", "go to apple.com"
//  - menu paths ("File > Export > PDF in Pages")
//
//  App commands after an app was named in the same request go to that app
//  (`appShortcut`), so "open Safari and make a new tab" presses ⌘T in
//  Safari. What it can't map becomes a quiet note, never a guess.
//

import Foundation

public struct AskCommandParser: Sendable {
    public var catalog: AskAppCatalog

    public init(catalog: AskAppCatalog = AskAppCatalog()) {
        self.catalog = catalog
    }

    /// Longest request it reads.
    public static let maxRequestLength = 1_000

    public func plan(_ request: String) -> AskPlan {
        let trimmed = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxRequestLength))
        var state = State()
        let (masked, quotes) = Self.maskQuotes(trimmed)
        let segments = Self.split(masked)

        var typing: String?
        func finishTyping() {
            if let text = typing {
                let restored = Self.restore(text, quotes: quotes).trimmingCharacters(in: .whitespaces)
                if !restored.isEmpty { state.steps.append(.typeText(restored)) }
            }
            typing = nil
        }

        for (separator, segment) in segments {
            let text = segment.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if typing != nil {
                // A clause that is itself a command ends the text ("type hi
                // and press return"); anything else is more text ("type
                // salt and pepper").
                var probe = state
                if parseClause(text, quotes: quotes, state: &probe), !Self.isQuoted(text) {
                    finishTyping()
                    _ = parseClause(text, quotes: quotes, state: &state)
                } else {
                    typing! += separator + text
                }
                continue
            }
            if let body = Self.typingBody(text) {
                typing = body
                if Self.isQuoted(body) { finishTyping() }
                continue
            }
            if !parseClause(text, quotes: quotes, state: &state) {
                let shown = Self.restore(text, quotes: quotes)
                state.notes.append("Didn’t understand “\(shown)”.")
            }
        }
        finishTyping()

        if state.steps.count > AskPlanValidation.maxSteps {
            state.steps = Array(state.steps.prefix(AskPlanValidation.maxSteps))
            state.notes.append("Kept the first \(AskPlanValidation.maxSteps) steps.")
        }
        return AskPlan(request: trimmed, steps: state.steps, notes: state.notes, source: .parser)
    }

    // MARK: - State

    struct State {
        var steps: [AskStep] = []
        var notes: [String] = []
        /// The app later app commands go to.
        var app: String?
    }

    // MARK: - Clauses

    /// Adds the clause's steps to `state`. `false` when it isn't
    /// understood (nothing added).
    func parseClause(_ original: String, quotes: [String], state: inout State) -> Bool {
        var clause = Self.clean(original)
        guard !clause.isEmpty else { return false }

        // "… in Safari": the command goes to that app.
        var app = state.app
        if let range = clause.range(of: " in ", options: .backwards) {
            let tail = String(clause[range.upperBound...])
            if let named = catalog.app(named: tail) {
                app = named.bundleID
                clause = String(clause[..<range.lowerBound])
            }
        }

        // Unsupported, said plainly.
        if let unsupported = Self.unsupported(clause) {
            state.notes.append(unsupported)
            return true
        }

        // wait 2 seconds
        if let ms = Self.waitMilliseconds(clause) {
            state.steps.append(.delay(milliseconds: ms))
            return true
        }

        // run the shortcut Morning
        if let name = Self.shortcutName(original, quotes: quotes) {
            state.steps.append(.action(.macShortcut(name: name)))
            return true
        }

        // quit Slack
        if let rest = Self.dropVerb(clause, ["quit", "close", "exit", "kill"]),
           let target = catalog.app(named: rest) {
            state.steps.append(.action(.appShortcut(bundleID: target.bundleID, keys: ["cmd", "q"])))
            if state.app == target.bundleID { state.app = nil }
            return true
        }

        // open Figma
        if let rest = Self.dropVerb(clause, ["open", "launch", "start", "switch to", "go to", "activate", "bring up", "show", "focus", "run", "use"]) {
            if let target = catalog.app(named: rest) {
                state.steps.append(.action(.launchApp(bundleID: target.bundleID)))
                state.app = target.bundleID
                return true
            }
            // go to apple.com
            if let url = Self.webAddress(rest) {
                let browser = app.flatMap { Self.browsers.contains($0) ? $0 : nil } ?? "com.apple.Safari"
                if app != browser {
                    state.steps.append(.action(.launchApp(bundleID: browser)))
                }
                state.steps.append(.action(.appShortcut(bundleID: browser, keys: ["cmd", "l"])))
                state.steps.append(.typeText(url + "\n"))
                state.app = browser
                return true
            }
        }

        // press cmd shift p
        if let rest = Self.dropVerb(clause, ["press", "hit", "tap", "push", "send", "type the shortcut", "do"]) {
            var keysText = rest
            for word in ["the ", "a "] where keysText.hasPrefix(word) { keysText = String(keysText.dropFirst(word.count)) }
            for word in [" keys", " key", " button", " shortcut"] where keysText.hasSuffix(word) { keysText = String(keysText.dropLast(word.count)) }
            if let keys = ChordParser.parse(keysText) {
                state.steps.append(.action(Self.scoped(keys, app: app)))
                return true
            }
        }
        if Self.looksLikeChord(clause), let keys = ChordParser.parse(clause) {
            state.steps.append(.action(Self.scoped(keys, app: app)))
            return true
        }

        // File > Export > PDF
        if let path = Self.menuPath(original, quotes: quotes) {
            guard let target = app else {
                state.notes.append("Name the app for “\(path.joined(separator: " › "))”, for example “… in Pages”.")
                return true
            }
            state.steps.append(.action(.menuCommand(bundleID: target, path: path)))
            return true
        }

        // new tab, mission control, play, paste my last screenshot
        if let command = Self.command(for: clause) {
            switch command {
            case let .global(action):
                state.steps.append(.action(action))
            case let .app(keys):
                state.steps.append(.action(Self.scoped(keys, app: app)))
            }
            if clause.contains("screenshot"), clause.contains("paste") {
                state.notes.append("Pastes what’s on the Mac’s clipboard. A screenshot taken with ⌃⇧⌘4 goes there.")
            }
            return true
        }
        return false
    }

    static func scoped(_ keys: [String], app: String?) -> Action {
        if let app { return .appShortcut(bundleID: app, keys: keys) }
        return .shortcut(keys: keys)
    }

    // MARK: - Commands

    enum Command: Equatable {
        /// Runs the same whatever app is in front.
        case global(Action)
        /// An app command: goes to the app named earlier, if any.
        case app([String])
    }

    static func command(for clause: String) -> Command? {
        var candidates = [clause, stripArticles(clause)]
        if let rest = dropVerb(clause, ["make", "create", "open", "do", "go", "show", "take", "turn on", "start", "click", "hit", "press", "choose", "select", "use", "toggle", "enter", "exit", "add", "please"]) {
            candidates.append(rest)
            candidates.append(stripArticles(rest))
        }
        for candidate in candidates {
            let key = candidate.trimmingCharacters(in: .whitespaces)
            if let action = globalCommands[key] { return .global(action) }
            if let keys = appCommands[key] { return .app(keys) }
        }
        if clause.contains("paste"), clause.contains("screenshot") { return .app(["cmd", "v"]) }
        return nil
    }

    static let globalCommands: [String: Action] = {
        var table: [String: Action] = [:]
        func add(_ names: [String], _ action: Action) { for name in names { table[name] = action } }
        add(["mission control"], .system(action: .missionControl))
        add(["show desktop", "desktop", "show the desktop"], .system(action: .showDesktop))
        add(["app windows", "app expose", "app exposé", "expose", "exposé", "show app windows"], .system(action: .appExpose))
        add(["launchpad", "apps", "show apps", "show all apps"], .system(action: .launchpad))
        add(["find pointer", "find cursor", "find the pointer", "find the cursor", "find mouse", "find the mouse", "locate cursor", "locate pointer", "where is the cursor", "where is my cursor"], .system(action: .locateCursor))
        add(["play", "pause", "play pause", "play/pause", "resume", "play music", "pause music", "resume music", "stop music", "pause the music", "play the music", "pause playback", "resume playback"], .media(key: .playPause))
        add(["next track", "next song", "skip", "skip song", "skip track", "skip this song", "next"], .media(key: .next))
        add(["previous track", "previous song", "last song", "previous", "last track", "go back a song"], .media(key: .previous))
        add(["lock", "lock screen", "lock the screen", "lock mac", "lock the mac", "lock my mac", "lock computer", "lock the computer", "lock it"], .shortcut(keys: ["cmd", "ctrl", "q"]))
        add(["log out", "logout", "sign out"], .shortcut(keys: ["cmd", "shift", "q"]))
        add(["force quit", "force quit menu"], .shortcut(keys: ["cmd", "option", "escape"]))
        add(["spotlight", "spotlight search", "search spotlight"], .shortcut(keys: ["cmd", "space"]))
        add(["screenshot", "screen shot", "take screenshot", "capture screen", "capture the screen", "screenshot of the screen", "full screenshot"], .shortcut(keys: ["cmd", "shift", "3"]))
        add(["screenshot of selection", "screenshot selection", "screenshot area", "screenshot region", "screenshot of an area", "screenshot part of the screen", "partial screenshot"], .shortcut(keys: ["cmd", "shift", "4"]))
        add(["screenshot options", "screen recording", "record screen", "record the screen", "screenshot toolbar"], .shortcut(keys: ["cmd", "shift", "5"]))
        add(["switch app", "switch apps", "next app", "app switcher"], .shortcut(keys: ["cmd", "tab"]))
        add(["emoji", "emoji picker", "emoji viewer", "emojis", "character viewer"], .shortcut(keys: ["cmd", "ctrl", "space"]))
        return table
    }()

    static let appCommands: [String: [String]] = {
        var table: [String: [String]] = [:]
        func add(_ names: [String], _ keys: [String]) { for name in names { table[name] = keys } }
        add(["new tab", "tab"], ["cmd", "t"])
        add(["new window", "window", "new document", "new file", "new note", "new message", "new email", "new mail", "compose", "compose email", "new"], ["cmd", "n"])
        add(["new folder", "new private window", "new incognito window", "private window", "incognito window", "incognito"], ["cmd", "shift", "n"])
        add(["close tab", "close this tab", "close the tab", "close window", "close this window", "close the window", "close"], ["cmd", "w"])
        add(["close all windows"], ["cmd", "option", "w"])
        add(["reopen tab", "reopen closed tab", "reopen last tab", "reopen the last tab", "reopen last closed tab", "undo close tab", "restore tab"], ["cmd", "shift", "t"])
        add(["reload", "refresh", "reload page", "refresh page", "reload the page", "refresh the page", "reload this page", "refresh this page"], ["cmd", "r"])
        add(["copy", "copy that", "copy it", "copy this", "copy selection"], ["cmd", "c"])
        add(["paste", "paste it", "paste that", "paste clipboard", "paste the clipboard"], ["cmd", "v"])
        add(["paste and match style", "paste as plain text", "paste plain text"], ["cmd", "option", "shift", "v"])
        add(["cut", "cut that", "cut it"], ["cmd", "x"])
        add(["undo", "undo that", "undo it"], ["cmd", "z"])
        add(["redo", "redo that"], ["cmd", "shift", "z"])
        add(["select all", "select everything", "select all text"], ["cmd", "a"])
        add(["save", "save it", "save this", "save file", "save the file", "save document"], ["cmd", "s"])
        add(["save as"], ["cmd", "shift", "s"])
        add(["print", "print this", "print page"], ["cmd", "p"])
        add(["find", "find on page", "find in page", "search page", "search in page"], ["cmd", "f"])
        add(["find next"], ["cmd", "g"])
        add(["minimize", "minimise", "minimize window", "minimise window", "minimize this window"], ["cmd", "m"])
        add(["hide", "hide app", "hide this app", "hide window"], ["cmd", "h"])
        add(["hide others", "hide other apps", "hide everything else"], ["cmd", "option", "h"])
        add(["quit", "quit app", "quit this app", "quit the app"], ["cmd", "q"])
        add(["zoom in", "bigger", "make it bigger", "make text bigger"], ["cmd", "="])
        add(["zoom out", "smaller", "make it smaller", "make text smaller"], ["cmd", "-"])
        add(["actual size", "reset zoom"], ["cmd", "0"])
        add(["address bar", "location bar", "url bar", "focus address bar", "focus the address bar"], ["cmd", "l"])
        add(["next tab"], ["ctrl", "tab"])
        add(["previous tab", "last tab"], ["ctrl", "shift", "tab"])
        add(["full screen", "fullscreen", "full screen mode", "enter full screen", "exit full screen", "toggle full screen"], ["cmd", "ctrl", "f"])
        add(["preferences", "app settings", "settings for this app"], ["cmd", ","])
        add(["bold"], ["cmd", "b"])
        add(["italic", "italics"], ["cmd", "i"])
        add(["underline"], ["cmd", "u"])
        add(["bookmark", "bookmark page", "bookmark this page", "add bookmark"], ["cmd", "d"])
        add(["history", "show history"], ["cmd", "y"])
        add(["downloads", "show downloads"], ["cmd", "option", "l"])
        add(["go back", "back", "back a page"], ["cmd", "["])
        add(["go forward", "forward", "forward a page"], ["cmd", "]"])
        add(["open file", "open a file", "open document"], ["cmd", "o"])
        add(["move to trash", "trash it", "delete file", "delete it"], ["cmd", "delete"])
        add(["go to folder"], ["cmd", "shift", "g"])
        add(["sidebar", "show sidebar", "hide sidebar", "toggle sidebar"], ["cmd", "ctrl", "s"])
        return table
    }()

    // MARK: - Grammar helpers

    static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"]

    /// Lowercased, fillers and end punctuation removed.
    static func clean(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".!?,;".contains(last) { t.removeLast() }
        var changed = true
        while changed {
            changed = false
            for filler in ["please ", "can you ", "could you ", "would you ", "i want to ", "i'd like to ", "i want you to ", "go ahead and ", "now ", "also ", "and ", "then ", "just ", "quickly "] where t.hasPrefix(filler) {
                t = String(t.dropFirst(filler.count))
                changed = true
            }
            for filler in [" please", " for me", " now"] where t.hasSuffix(filler) {
                t = String(t.dropLast(filler.count))
                changed = true
            }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func stripArticles(_ s: String) -> String {
        var t = s
        for article in ["a ", "an ", "the ", "my ", "this ", "some "] where t.hasPrefix(article) {
            t = String(t.dropFirst(article.count))
        }
        return t
    }

    /// The rest of `clause` after one of `verbs` and a space.
    static func dropVerb(_ clause: String, _ verbs: [String]) -> String? {
        for verb in verbs.sorted(by: { $0.count > $1.count }) where clause.hasPrefix(verb + " ") {
            let rest = clause.dropFirst(verb.count + 1).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    static func looksLikeChord(_ clause: String) -> Bool {
        clause.contains { "⌘⇧⌥⌃".contains($0) }
            || ["cmd", "command", "ctrl", "control", "option", "alt", "shift"].contains { clause.hasPrefix($0 + " ") || clause.hasPrefix($0 + "+") || clause.hasPrefix($0 + "-") }
    }

    static func unsupported(_ clause: String) -> String? {
        let words = clause.split(separator: " ").map(String.init)
        func has(_ w: String) -> Bool { words.contains(w) }
        if has("mute") || has("unmute") || clause.contains("volume") {
            return "Pixel Hand can’t change the Mac’s volume yet."
        }
        if clause.contains("brightness") { return "Pixel Hand can’t change the Mac’s brightness yet." }
        if clause == "sleep" || clause.hasPrefix("put the mac to sleep") || clause.hasPrefix("sleep the mac") || clause == "go to sleep" {
            return "Pixel Hand can’t put the Mac to sleep. Try “lock the screen”."
        }
        if clause.hasPrefix("shut down") || clause.hasPrefix("shutdown") || clause.hasPrefix("restart") || clause.hasPrefix("reboot") {
            return "Pixel Hand won’t shut down or restart the Mac."
        }
        return nil
    }

    static func waitMilliseconds(_ clause: String) -> Int? {
        guard let rest = dropVerb(clause, ["wait", "pause for", "wait for", "delay"]) else { return nil }
        let parts = rest.replacingOccurrences(of: "a second", with: "1 second")
            .replacingOccurrences(of: "a moment", with: "1 second")
            .split(separator: " ")
        guard let first = parts.first, let value = Double(first.replacingOccurrences(of: "s", with: "")) ?? numberWord(String(first)) else { return nil }
        let unit = parts.count > 1 ? String(parts[1]) : (first.hasSuffix("ms") ? "ms" : "s")
        let ms = unit.hasPrefix("ms") || unit.hasPrefix("milli") ? value : value * 1000
        let clamped = min(max(0, Int(ms.rounded())), ActionLimits.maxDelayMilliseconds)
        return clamped
    }

    static func numberWord(_ s: String) -> Double? {
        ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "half": 0.5][s]
    }

    /// "run the shortcut Morning Routine", "run my Morning shortcut".
    static func shortcutName(_ original: String, quotes: [String]) -> String? {
        let text = restore(original, quotes: quotes).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        let lower = text.lowercased()
        for prefix in ["run the shortcut ", "run shortcut ", "run my shortcut ", "start the shortcut ", "run the mac shortcut "] where lower.hasPrefix(prefix) {
            return cleanName(String(text.dropFirst(prefix.count)))
        }
        for prefix in ["run the ", "run my ", "run "] where lower.hasPrefix(prefix) && lower.hasSuffix(" shortcut") {
            let name = text.dropFirst(prefix.count).dropLast(" shortcut".count)
            return cleanName(String(name))
        }
        return nil
    }

    static func cleanName(_ s: String) -> String? {
        let name = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"“”'‘’")))
        return ActionValidation.isShortcutName(name) ? name : nil
    }

    /// "apple.com", "https://example.com/x".
    static func webAddress(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.contains(" "), t.contains("."), t.count <= 2_000 else { return nil }
        guard let last = t.split(separator: ".").last, last.count >= 2, last.allSatisfy({ $0.isLetter || $0 == "/" || $0.isNumber }) || t.hasPrefix("http") else { return nil }
        return t
    }

    /// "File > Export > PDF…", "choose View › Show Sidebar".
    static func menuPath(_ original: String, quotes: [String]) -> [String]? {
        var text = restore(original, quotes: quotes).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        guard text.contains(">") || text.contains("›") || text.contains("→") else { return nil }
        if let range = text.range(of: " in ", options: .backwards) { text = String(text[..<range.lowerBound]) }
        for verb in ["choose ", "click ", "select ", "pick ", "menu ", "use the menu ", "open the menu "] where text.lowercased().hasPrefix(verb) {
            text = String(text.dropFirst(verb.count))
        }
        let parts = text
            .replacingOccurrences(of: "›", with: ">")
            .replacingOccurrences(of: "→", with: ">")
            .split(separator: ">")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, parts.count <= ActionLimits.maxMenuPathComponents, parts.allSatisfy(ActionValidation.isMenuTitle) else { return nil }
        return parts
    }

    // MARK: - Typing

    /// The text after "type" / "write", or `nil` when the clause doesn't
    /// start with one. Keeps the person's case.
    static func typingBody(_ segment: String) -> String? {
        var text = segment.trimmingCharacters(in: .whitespaces)
        for filler in ["please ", "then ", "and ", "now "] where text.lowercased().hasPrefix(filler) {
            text = String(text.dropFirst(filler.count))
        }
        let lower = text.lowercased()
        for verb in ["type out ", "type in ", "type the text ", "type: ", "type ", "write out ", "write: ", "write ", "enter the text ", "enter text ", "dictate "] where lower.hasPrefix(verb) {
            let body = String(text.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
            // "type the shortcut …" is a chord, not text.
            if verb == "type " && lower.hasPrefix("type the shortcut ") { return nil }
            return body.isEmpty ? nil : body
        }
        return nil
    }

    // MARK: - Splitting and quotes

    static let quoteMark = "\u{1}"

    /// Replaces quoted text with placeholders so separators inside quotes
    /// don't split it.
    static func maskQuotes(_ s: String) -> (String, [String]) {
        var out = ""
        var quotes: [String] = []
        var current: String?
        var closer: Character = "\""
        for c in s {
            if var inside = current {
                if c == closer {
                    quotes.append(inside)
                    out += quoteMark + String(quotes.count - 1) + quoteMark
                    current = nil
                } else {
                    inside.append(c)
                    current = inside
                }
            } else if c == "\"" || c == "“" {
                current = ""
                closer = c == "“" ? "”" : "\""
            } else {
                out.append(c)
            }
        }
        if let open = current { out += "\"" + open }
        return (out, quotes)
    }

    static func restore(_ s: String, quotes: [String]) -> String {
        var out = s
        for (index, quote) in quotes.enumerated() {
            out = out.replacingOccurrences(of: quoteMark + String(index) + quoteMark, with: quote)
        }
        return out
    }

    static func isQuoted(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix(quoteMark) && t.hasSuffix(quoteMark) && t.filter({ String($0) == quoteMark }).count == 2
    }

    /// Splits on commas, semicolons, sentence ends, "and", "then" and
    /// "after that", keeping each separator for re-joining typed text.
    static func split(_ s: String) -> [(separator: String, text: String)] {
        let pattern = #"\s*(?:,\s*(?:and\s+then|and|then)?\s*|;\s*|[.!?]\s+|\s+and\s+then\s+|\s+then\s+|\s+and\s+|\s+after\s+that\s+|\s+&\s+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [("", s)]
        }
        let ns = s as NSString
        var result: [(String, String)] = []
        var last = 0
        var separator = ""
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result.append((separator, ns.substring(with: NSRange(location: last, length: match.range.location - last))))
            separator = ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        result.append((separator, ns.substring(from: last)))
        return result
    }
}
