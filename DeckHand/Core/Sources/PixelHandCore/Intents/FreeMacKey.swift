//
//  FreeMacKey.swift
//  PixelHandCore – Intents
//
//  The free Mac keys (Mission Control, Show Desktop, Play, Lock, …) as
//  choices for the Control Center "Deck Key" control (VQ-078). With an
//  empty deck its Choose sheet used to say only "No options available";
//  now it offers the eight keys the widget shows, which run without Pro.
//  Their IDs never collide with a deck key's (`DeckKey.id` is a UUID).
//

public enum FreeMacKey {
    /// One choice: a stable ID, its label and the command it runs.
    public struct Choice: Sendable, Hashable, Identifiable {
        public let id: String
        public let label: String
        public let command: RemoteCommand
    }

    /// What the choices are grouped under in the Choose sheet.
    public static let groupTitle = "Mac keys"

    static let prefix = "mac."

    /// The eight free keys, in the order the Deck widget shows them.
    public static let choices: [Choice] = [
        system(.missionControl), system(.showDesktop), media(.playPause, "Play/Pause"), system(.lockScreen),
        system(.appExpose), media(.previous, "Previous track"), media(.next, "Next track"), system(.launchpad),
    ]

    /// The free key with `id`, or nil for a deck key's ID.
    public static func choice(id: String) -> Choice? {
        guard id.hasPrefix(prefix) else { return nil }
        return choices.first { $0.id == id }
    }

    private static func system(_ command: SystemCommand) -> Choice {
        Choice(id: "\(prefix)system.\(command.rawValue)", label: command.title, command: .system(command))
    }

    private static func media(_ key: MediaKey, _ label: String) -> Choice {
        Choice(id: "\(prefix)media.\(key.rawValue)", label: label, command: .media(key))
    }
}
