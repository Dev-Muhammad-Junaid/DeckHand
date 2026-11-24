//
//  OnDeviceModel.swift
//  DeckHandiOS – Assist
//
//  What every Apple Intelligence feature in Pixel Hand shares: whether the
//  on-device model can run now, and a deadline after which the caller's
//  deterministic answer stands. Used by "Suggest a deck"
//  (`OnDeviceDeckRanker`) and Ask (`OnDeviceAskPlanner`). Foundation
//  Models only: no Private Cloud Compute, no third-party cloud
//  (DECISIONS.md). iOS 26+ behind `#available`; `nil`/`false` elsewhere.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceModel {
    /// Whether the system's on-device language model can answer now
    /// (iOS 26+, Apple Intelligence on, model downloaded, supported device).
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Runs `work`, or answers `nil` after `seconds`, whichever comes first.
    static func withDeadline<T: Sendable>(
        _ seconds: TimeInterval,
        _ work: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
