//
//  DeckHandDiagnostics.swift
//  Pixel Hand – Shared
//
//  Crash and performance reporting through Sentry, shared by both apps.
//
//  Privacy rules, which the privacy policy, PrivacyInfo.xcprivacy and the
//  App Store "App Privacy" answers all depend on:
//
//   • Off switch: the user's "Share crash reports" setting. When it's off
//     the SDK is never started (or is closed immediately), so nothing is
//     captured or sent.
//   • No personal data: `sendDefaultPii` stays false, and `scrub` drops the
//     device and host names Sentry could otherwise pick up — those are
//     usually the owner's name ("Junaid's iPad").
//   • No user content: no screenshots, no view hierarchy, no session
//     replay. Pixel Hand shows the Mac's screen, so any of those would ship
//     the user's screen contents.
//   • The DSN comes from the `SentryDSN` Info.plist key, which is filled in
//     from the `SENTRY_DSN` build setting in project.yml. An empty DSN
//     (forks, local builds) turns reporting off rather than failing.
//

import Foundation
import Sentry

enum DeckHandDiagnostics {
    /// `UserDefaults` key for the user's choice. Absent means "on".
    static let enabledKey = "diagnostics.shareCrashReports"

    /// Whether the user allows crash reports. Defaults to on: the reports
    /// carry no personal data and aren't linked to the user.
    static var isEnabledByUser: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// The DSN baked in at build time, or `nil` when this build has none.
    static var dsn: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// Call as early in launch as possible. Safe to call more than once.
    static func startIfEnabled() {
        guard !SentrySDK.isEnabled else { return }
        guard isEnabledByUser else {
            DeckHandLog.app.info("Crash reporting off by user choice")
            return
        }
        start()
    }

    /// Records the user's choice and applies it immediately.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            if !SentrySDK.isEnabled { start() }
        } else if SentrySDK.isEnabled {
            SentrySDK.close()
            DeckHandLog.app.info("Crash reporting turned off")
        }
    }

    /// Reports a non-fatal failure the app recovered from, such as a
    /// startup error shown on screen instead of crashing. No-op when off.
    static func capture(_ error: Error) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(error: error)
    }

    private static func start() {
        guard let dsn else {
            DeckHandLog.app.info("Crash reporting unavailable: no Sentry DSN in this build")
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif

            // ── Privacy ─────────────────────────────────────────────
            options.sendDefaultPii = false
            #if os(iOS)
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
            #endif
            // Pixel Hand makes no HTTP requests of its own; the only ones
            // would be Sentry's and CloudKit's.
            options.enableNetworkBreadcrumbs = false
            options.beforeSend = { event in scrub(event) }

            // ── What to collect ─────────────────────────────────────
            // Crashes, hangs and watchdog terminations are on by default.
            #if os(macOS)
            // AppKit swallows uncaught NSExceptions on the main thread
            // unless this is on, so they'd never be reported.
            options.enableUncaughtNSExceptionReporting = true
            #endif
            // A sample of launches and screen loads, for the performance
            // data the privacy policy describes. Keep it low.
            options.tracesSampleRate = 0.1
        }
        DeckHandLog.app.info("Crash reporting on")
    }

    /// Drops identifying names before an event leaves the device.
    private static func scrub(_ event: Event) -> Event {
        event.serverName = nil
        // Keep only the user ID: Sentry fills it with a random per-install
        // ID, which is what lets it count affected installs. Nothing else
        // (IP, name, email) should ever be there.
        event.user = event.user?.userId.map { User(userId: $0) }
        if var device = event.context?["device"] {
            device.removeValue(forKey: "name")
            event.context?["device"] = device
        }
        return event
    }
}
