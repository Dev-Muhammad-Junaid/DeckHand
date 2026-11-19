//
//  DiagnosticsHandler.swift
//  DeckHandMac
//
//  Domain: diagnostics. A remote reports its half of the mirror (S6) once a
//  second; the Mac logs it with its own half as the one-line stats summary
//  the remote's HUD shows, at most every `logInterval` per remote. Owned by
//  the mirror lane.
//

import Foundation
import LoomKit

@MainActor
final class DiagnosticsHandler: DomainHandler {
    /// Seconds between stats lines in the log, per remote.
    static let logInterval: TimeInterval = 10

    private var lastLoggedAt: [UUID: Date] = [:]

    func handle(_ message: DiagnosticsMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case let .mirrorClientStats(stats):
            let now = Date()
            if let last = lastLoggedAt[connection.id], now.timeIntervalSince(last) < Self.logInterval {
                return
            }
            lastLoggedAt[connection.id] = now
            let host = MirrorStreamService.shared.lastHostStats[connection.id]
            let line = MirrorStatsLine.text(host: host, client: stats, clientName: "Remote")
            DeckHandLog.app.info("Mirror stats: \(line, privacy: .public)")

        case .mirrorStats:
            break // Mac → remote only
        }
    }
}
