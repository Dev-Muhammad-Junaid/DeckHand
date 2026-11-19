//
//  DeckHandSettings.swift
//  DeckHandiOS
//
//  User preferences for the remote. One observable store injected into the
//  view tree, persisted to `UserDefaults` on write.
//
//  Several of these knobs cost bandwidth or host CPU (mirror sharpness and
//  frame rate, input send rate, screenshot quality). They are deliberately
//  manual for now: a link-quality heuristic needs a baseline the user can
//  fall back to when it guesses wrong, so the explicit control ships first.
//

import Foundation
import SwiftUI

// The choice enums live beside this file in Settings/DeckHandSettings+*.swift.

// MARK: - Store

/// Single source of truth for user preferences, injected with
/// `.environmentObject`. Every property writes straight through to
/// `UserDefaults`, so there is no save step and nothing to lose on a crash.
@MainActor
final class DeckHandSettings: ObservableObject {
    private enum Key {
        static let pointerSensitivity = "settings.pointerSensitivity"
        static let inputSendRate = "settings.inputSendRate"
        static let hapticStrength = "settings.hapticStrength"
        static let naturalScrolling = "settings.naturalScrolling"
        static let mirrorFrameRate = "settings.mirrorFrameRate"
        static let mirrorSharpness = "settings.mirrorSharpness"
        static let rememberMirrorLayout = "settings.rememberMirrorLayout"
        static let mirrorLayout = "settings.mirrorLayout"
        // MARK: Mirror (lane)
        static let mirrorFollowsCursor = "settings.mirrorFollowsCursor"
        static let showMirrorStats = "settings.showMirrorStats"
        static let mirrorPrefersHEVC = "settings.mirrorPrefersHEVC"
        static let screenshotQuality = "settings.screenshotQuality"
        static let defaultCapture = "settings.defaultCapture"
        static let autoSaveToPhotos = "settings.autoSaveToPhotos"
        static let appearance = "settings.appearance"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        /// Owned by `StreamDeckGridView`; the key predates this store.
        static let hiddenApps = "hiddenBundleIDs"
        // MARK: iOS interaction (lane)
        static let trackpadGestures = "settings.trackpadGestures"
        static let pencilHoverPointer = "settings.pencilHoverPointer"
        static let clipboardSync = "settings.clipboardSync"
        static let pasteRightAway = "settings.pasteRightAway"
    }

    private let defaults: UserDefaults

    // ── Pointer and gestures ────────────────────────────────────────
    @Published var pointerSensitivity: Float {
        didSet { defaults.set(pointerSensitivity, forKey: Key.pointerSensitivity) }
    }

    @Published var inputSendRate: InputSendRate {
        didSet { defaults.set(inputSendRate.rawValue, forKey: Key.inputSendRate) }
    }

    @Published var hapticStrength: HapticStrength {
        didSet {
            defaults.set(hapticStrength.rawValue, forKey: Key.hapticStrength)
            // Haptics fire from leaf views and gesture closures all over the
            // app, most of which have no reason to hold a settings
            // reference. Mirroring the choice onto the shared player keeps
            // one gate for every call site.
            GestureHaptic.strength = hapticStrength
        }
    }

    /// Inverts scroll direction so the content tracks the fingers. Defaults
    /// off, which preserves the direction the app has always used.
    @Published var naturalScrolling: Bool {
        didSet { defaults.set(naturalScrolling, forKey: Key.naturalScrolling) }
    }

    // MARK: iOS interaction (lane)
    // Choices and copy in Settings/DeckHandSettings+Input.swift.

    /// Three- and four-finger swipes and pinches run Mac views (S11).
    @Published var trackpadGestures: Bool {
        didSet { defaults.set(trackpadGestures, forKey: Key.trackpadGestures) }
    }

    /// Apple Pencil hovering over the trackpad moves the pointer (S12).
    @Published var pencilHoverPointer: Bool {
        didSet { defaults.set(pencilHoverPointer, forKey: Key.pencilHoverPointer) }
    }

    /// The Mac's clipboard text comes to this device (S10). Off until the
    /// person turns it on.
    @Published var clipboardSync: Bool {
        didSet { defaults.set(clipboardSync, forKey: Key.clipboardSync) }
    }

    /// Paste to Mac also presses ⌘V on the Mac; off puts it on the Mac's
    /// clipboard only.
    @Published var pasteRightAway: Bool {
        didSet { defaults.set(pasteRightAway, forKey: Key.pasteRightAway) }
    }

    // ── Live mirror ─────────────────────────────────────────────────
    @Published var mirrorFrameRate: MirrorFrameRate {
        didSet { defaults.set(mirrorFrameRate.rawValue, forKey: Key.mirrorFrameRate) }
    }

    @Published var mirrorSharpness: MirrorSharpness {
        didSet { defaults.set(mirrorSharpness.rawValue, forKey: Key.mirrorSharpness) }
    }

    @Published var rememberMirrorLayout: Bool {
        didSet {
            defaults.set(rememberMirrorLayout, forKey: Key.rememberMirrorLayout)
            if !rememberMirrorLayout { mirrorLayout = nil }
        }
    }

    @Published var mirrorLayout: MirrorLayout? {
        didSet {
            if let mirrorLayout, let data = try? JSONEncoder().encode(mirrorLayout) {
                defaults.set(data, forKey: Key.mirrorLayout)
            } else {
                defaults.removeObject(forKey: Key.mirrorLayout)
            }
        }
    }

    // MARK: Mirror (lane)
    /// The mirror switches to whichever display the Mac's pointer is on.
    @Published var mirrorFollowsCursor: Bool {
        didSet { defaults.set(mirrorFollowsCursor, forKey: Key.mirrorFollowsCursor) }
    }

    /// Shows the stream stats line over the mirror (S6).
    @Published var showMirrorStats: Bool {
        didSet { defaults.set(showMirrorStats, forKey: Key.showMirrorStats) }
    }

    /// Streams the mirror as HEVC video when this device can decode it
    /// (S5); off, or after HEVC failed in a session, JPEG images.
    @Published var mirrorPrefersHEVC: Bool {
        didSet { defaults.set(mirrorPrefersHEVC, forKey: Key.mirrorPrefersHEVC) }
    }

    // ── Screenshots ─────────────────────────────────────────────────
    @Published var screenshotQuality: CaptureQuality {
        didSet { defaults.set(screenshotQuality.rawValue, forKey: Key.screenshotQuality) }
    }

    @Published var defaultCapture: DefaultCapture {
        didSet { defaults.set(defaultCapture.rawValue, forKey: Key.defaultCapture) }
    }

    @Published var autoSaveToPhotos: Bool {
        didSet { defaults.set(autoSaveToPhotos, forKey: Key.autoSaveToPhotos) }
    }

    // ── Appearance ──────────────────────────────────────────────────
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    // ── Privacy ─────────────────────────────────────────────────────
    /// Whether crash and performance reports go to Sentry. Stored by
    /// `DeckHandDiagnostics` under its own key so it can be read at launch,
    /// before this store exists. Takes effect immediately either way.
    @Published var shareCrashReports: Bool {
        didSet { DeckHandDiagnostics.setEnabled(shareCrashReports) }
    }

    // ── First run ───────────────────────────────────────────────────
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedSensitivity = defaults.object(forKey: Key.pointerSensitivity) as? Float
        pointerSensitivity = storedSensitivity ?? TrackpadSensitivity.defaultValue

        inputSendRate = InputSendRate(rawValue: defaults.integer(forKey: Key.inputSendRate))
            ?? .proMotion
        hapticStrength = (defaults.string(forKey: Key.hapticStrength)
            .flatMap(HapticStrength.init(rawValue:))) ?? .full
        naturalScrolling = defaults.bool(forKey: Key.naturalScrolling)

        mirrorFrameRate = MirrorFrameRate(rawValue: defaults.integer(forKey: Key.mirrorFrameRate))
            ?? .standard
        mirrorSharpness = (defaults.string(forKey: Key.mirrorSharpness)
            .flatMap(MirrorSharpness.init(rawValue:))) ?? .auto
        // Defaults to on: the mirror is pinchable to nearly full screen now,
        // and redoing that every session is the friction this removes.
        rememberMirrorLayout = defaults.object(forKey: Key.rememberMirrorLayout) as? Bool ?? true
        mirrorLayout = defaults.data(forKey: Key.mirrorLayout)
            .flatMap { try? JSONDecoder().decode(MirrorLayout.self, from: $0) }
        mirrorFollowsCursor = defaults.bool(forKey: Key.mirrorFollowsCursor)
        showMirrorStats = defaults.bool(forKey: Key.showMirrorStats)
        mirrorPrefersHEVC = defaults.object(forKey: Key.mirrorPrefersHEVC) as? Bool ?? true

        screenshotQuality = (defaults.string(forKey: Key.screenshotQuality)
            .flatMap(CaptureQuality.init(rawValue:))) ?? .standard
        defaultCapture = (defaults.string(forKey: Key.defaultCapture)
            .flatMap(DefaultCapture.init(rawValue:))) ?? .fullScreen
        autoSaveToPhotos = defaults.bool(forKey: Key.autoSaveToPhotos)

        appearance = (defaults.string(forKey: Key.appearance)
            .flatMap(AppearanceMode.init(rawValue:))) ?? .system

        shareCrashReports = DeckHandDiagnostics.isEnabledByUser

        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)

        // MARK: iOS interaction (lane)
        trackpadGestures = defaults.object(forKey: Key.trackpadGestures) as? Bool ?? true
        pencilHoverPointer = defaults.object(forKey: Key.pencilHoverPointer) as? Bool ?? true
        clipboardSync = defaults.bool(forKey: Key.clipboardSync)
        pasteRightAway = defaults.object(forKey: Key.pasteRightAway) as? Bool ?? true

        GestureHaptic.strength = hapticStrength
    }

    /// Stream width to ask the host for, given the width the mirror's current
    /// on-screen size implies.
    func mirrorStreamWidth(naturalWidth: Int) -> Int {
        mirrorSharpness.resolve(naturalWidth: naturalWidth)
    }

    // MARK: - Hidden apps

    /// Bundle IDs hidden from the Apps grid. Owned by `StreamDeckGridView`
    /// via `@AppStorage`; read here under the same key and format so hiding
    /// isn't a one-way door — the grid offers no way back.
    var hiddenAppBundleIDs: Set<String> {
        guard let data = defaults.data(forKey: Key.hiddenApps),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    func unhideAllApps() {
        defaults.set(try? JSONEncoder().encode(Set<String>()), forKey: Key.hiddenApps)
        objectWillChange.send()
    }
}
