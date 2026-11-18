//
//  DiagnosticsMessage.swift
//  PixelHandCore
//
//  Domain: diagnostics. Connection and stream statistics shared between the
//  two ends. Owned by the mirror lane (S6's stats line and HUD); the stats
//  maths is in `Mirror/MirrorStats.swift`.
//

import Foundation

public enum DiagnosticsMessage: Codable, Sendable, Equatable {
    /// Mac → remote, every `MirrorStatsPolicy.reportInterval` while that
    /// remote's mirror runs.
    case mirrorStats(stats: MirrorHostStats)
    /// Remote → Mac, every `MirrorStatsPolicy.reportInterval` while its
    /// mirror runs. The Mac logs it with its own numbers as one line.
    case mirrorClientStats(stats: MirrorClientStats)
}
