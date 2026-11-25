//
//  SettingsDiagnosticsSection.swift
//  DeckHandiOS
//
//  Settings › Diagnostics (VQ-054): how this device is connected (the
//  Mac, the link, the round trip), the last few connection problems, and
//  Export logs, which gathers this app's log entries from the last hour
//  into a text file to share. Session ids and other debug detail live here,
//  never in the main UI (04 §9).
//
//  `ConnectionDiagnostics` is written by the session, the switcher and the
//  pairing code; this section only reads it.
//

import Observation
import OSLog
import SwiftUI

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

struct SettingsDiagnosticsSection: View {
    private let diagnostics = ConnectionDiagnostics.shared
    private let link = RemoteLinkStatus.shared

    @State private var export: ExportState = .idle

    enum ExportState: Equatable {
        case idle, working, ready(URL), failed(String)
    }

    var body: some View {
        Section {
            LabeledContent("Mac", value: diagnostics.macName ?? "Not connected")
            if diagnostics.macName != nil {
                LabeledContent("Link", value: link.current?.displayName ?? "Unknown")
                LabeledContent("Round trip", value: diagnostics.roundTripMs.map { "\($0) ms" } ?? "Measuring")
                if link.isAway {
                    LabeledContent("Mirror quality", value: "Away (VPN or slow link)")
                }
            }
            LabeledContent("Protocol", value: "\(PixelHandProtocol.version)")

            if diagnostics.problems.isEmpty {
                Text("No connection problems since Pixel Hand opened.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics.problems) { problem in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(problem.message)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(problem.at.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            exportRow
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Export logs makes a text file of the last hour of Pixel Hand’s log to send with a problem report. It has device and Mac names, no screen contents and no typed text.")
        }
        .accessibilityIdentifier("ph.settings.diagnostics")
    }

    @ViewBuilder
    private var exportRow: some View {
        switch export {
        case .idle, .failed:
            Button("Export logs") { Task { await exportLogs() } }
                .accessibilityIdentifier("ph.settings.exportLogs")
            if case let .failed(message) = export {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(PixelHandTheme.warning)
            }
        case .working:
            HStack(spacing: PixelHandTheme.Space.sm) {
                DotWave(pitch: 2.5, label: "Gathering logs")
                Text("Gathering logs…")
                    .foregroundStyle(.secondary)
            }
        case let .ready(url):
            ShareLink(item: url) {
                Text("Share log file")
            }
            .accessibilityIdentifier("ph.settings.shareLogs")
        }
    }

    private func exportLogs() async {
        export = .working
        let result = await Task.detached(priority: .utility) { () -> Result<URL, Error> in
            Result { try LogExport.write(since: Date().addingTimeInterval(-3_600)) }
        }.value
        switch result {
        case let .success(url): export = .ready(url)
        case let .failure(error): export = .failed("Couldn’t read the log: \(error.localizedDescription)")
        }
    }
}

/// Reads this process's entries from the unified log (public API,
/// `OSLogStore`, iOS 15+) and writes them to a temporary text file.
enum LogExport {
    static func write(since start: Date) throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: start)
        let entries = try store.getEntries(at: position)
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            // Only Pixel Hand's own subsystem (and Loom's): not system noise.
            guard log.subsystem == DeckHandLog.subsystem || log.subsystem.hasPrefix("com.loom") else { continue }
            lines.append("\(formatter.string(from: log.date)) [\(log.category)] \(log.composedMessage)")
        }
        if lines.isEmpty { lines.append("No Pixel Hand log entries in the last hour.") }
        let name = "PixelHand-log-\(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
