//
//  DeckHandSentry.swift
//  Deck Hand – Shared
//
//  Boots the Sentry Cocoa SDK for the Pixel Hand iOS and macOS apps.
//  DSNs live in each target's Info.plist under `SENTRY_DSN` so the two
//  Sentry projects stay separate. Shared is also compiled into
//  DeckHandTests without the Sentry package, so the real start path is
//  gated on `canImport(Sentry)`.
//

import Foundation

#if canImport(Sentry)
import Sentry
#endif

enum DeckHandSentry {
    /// Info.plist key that holds the public Sentry DSN for this target.
    static let dsnInfoPlistKey = "SENTRY_DSN"

    /// Start Sentry as early as possible on the main thread.
    /// No-op when the Sentry module is not linked (unit-test target) or when
    /// the DSN key is missing/empty.
    static func start() {
        #if canImport(Sentry)
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: dsnInfoPlistKey) as? String,
              !dsn.isEmpty else {
            DeckHandLog.app.error("Sentry DSN missing from Info.plist (\(Self.dsnInfoPlistKey, privacy: .public)); crash reporting disabled")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            // Modest production tracing; raise only when investigating perf.
            options.tracesSampleRate = 0.2

            #if DEBUG
            options.environment = "debug"
            options.debug = false
            #else
            options.environment = "release"
            #endif

            options.releaseName = Self.releaseName(from: .main)
        }

        DeckHandLog.app.info("Sentry started (env=\(Self.environmentLabel, privacy: .public))")
        #endif
    }

    /// `<bundleID>@<marketing>+<build>` — matches Sentry's default when set
    /// explicitly so releases stay stable across SDK upgrades.
    static func releaseName(from bundle: Bundle) -> String {
        let bundleID = bundle.bundleIdentifier ?? "com.deckhand"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(bundleID)@\(version)+\(build)"
    }

    private static var environmentLabel: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}
