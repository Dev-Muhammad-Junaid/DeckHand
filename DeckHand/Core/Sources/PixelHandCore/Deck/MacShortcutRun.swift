//
//  MacShortcutRun.swift
//  PixelHandCore
//
//  The pure part of running a Shortcuts.app shortcut on the Mac
//  (`Action.macShortcut`): the command line, the time limit and how the
//  result becomes a receipt. The Mac's `DeckHandler` spawns the process.
//

import Foundation

public enum MacShortcutRun {
    /// The Shortcuts command-line tool (macOS 12 and later).
    public static let executablePath = "/usr/bin/shortcuts"
    /// A run that hasn't exited by then is terminated and reported failed.
    public static let timeout: TimeInterval = 15

    /// The arguments for `shortcuts`, or `nil` when `name` isn't
    /// acceptable. The name is one argument, never a shell string, so
    /// quotes and spaces in it are harmless; a leading `-` (which would
    /// read as an option) is refused by `ActionValidation.isShortcutName`.
    public static func arguments(name: String) -> [String]? {
        guard ActionValidation.isShortcutName(name) else { return nil }
        return ["run", name]
    }

    /// How the run ended.
    public enum Ending: Equatable, Sendable {
        case exited(status: Int32)
        case timedOut
        case couldNotStart
    }

    /// The receipt for `ending`.
    public static func outcome(_ ending: Ending, name: String) -> ActionOutcome {
        switch ending {
        case .exited(0):
            .completed
        case let .exited(status):
            .failed(reason: "The shortcut “\(name)” stopped with an error (\(status)).")
        case .timedOut:
            .failed(reason: "The shortcut “\(name)” took longer than \(Int(timeout)) seconds and was stopped.")
        case .couldNotStart:
            .failed(reason: "Shortcuts isn't available on this Mac.")
        }
    }
}
