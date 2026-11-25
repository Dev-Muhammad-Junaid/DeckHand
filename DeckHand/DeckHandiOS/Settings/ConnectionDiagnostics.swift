//
//  ConnectionDiagnostics.swift
//  DeckHandiOS
//
//  What Settings › Diagnostics shows (VQ-054): the Mac, the round trip and
//  the last few connection problems. Written by the session, the switcher
//  and the pairing code; read by `SettingsDiagnosticsSection`.
//

import Foundation
import Observation

/// What Settings › Diagnostics shows, kept outside the session model so
/// Settings can read it with or without a session.
@MainActor
@Observable
final class ConnectionDiagnostics {
    static let shared = ConnectionDiagnostics()

    struct Problem: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var at: Date
    }

    /// The Mac of the running session, `nil` without one.
    var macName: String?
    /// The smoothed round trip to the Mac, in milliseconds.
    var roundTripMs: Int?
    /// Newest first, at most `maxProblems`.
    private(set) var problems: [Problem] = []

    static let maxProblems = 8

    func record(_ message: String) {
        problems.insert(Problem(message: message, at: Date()), at: 0)
        if problems.count > Self.maxProblems { problems.removeLast(problems.count - Self.maxProblems) }
    }

    func sessionEnded() {
        macName = nil
        roundTripMs = nil
    }
}
