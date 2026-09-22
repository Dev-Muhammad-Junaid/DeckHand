//
//  PermissionsMonitor.swift
//  DeckHandMac
//
//  Live TCC permission status for the menu bar panel.
//
//  Screen Recording is reported from `CGPreflightScreenCaptureAccess`
//  only. We used to probe `SCShareableContent` to catch stale grants, but
//  that API is a permission *request*: on current macOS it presents
//  "record your screen and system audio" on every launch, including when
//  the Settings toggle is already on for a previous build of this bundle.
//  Ground truth for capture is the capture path itself; this panel only
//  mirrors what System Settings currently says.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import UserNotifications

@MainActor
final class PermissionsMonitor: ObservableObject {
    static let shared = PermissionsMonitor()

    enum Status: Equatable {
        case granted
        case denied
        /// Granted but needs an app relaunch to take effect (Screen
        /// Recording behaves this way when toggled while running).
        case unknown
    }

    @Published private(set) var accessibility: Status = .unknown
    @Published private(set) var screenRecording: Status = .unknown
    @Published private(set) var notifications: Status = .unknown

    private init() {
        refresh()
    }

    /// Re-evaluates every permission. Cheap and silent — never calls
    /// ScreenCaptureKit. `SCShareableContent` is a *request*, not a
    /// preflight: on current macOS it presents "record your screen and
    /// system audio" even when the Settings toggle is already on for a
    /// previous build of this bundle. Status here is the Settings toggle
    /// (`CGPreflightScreenCaptureAccess`) plus `AXIsProcessTrusted`.
    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied

        // `@Sendable` is load-bearing: UserNotifications calls this back on
        // its own internal queue (UNUserNotificationServiceConnection
        // .call-out), but this type is @MainActor, so without the annotation
        // Swift 6 infers the closure as main-actor-isolated and the runtime
        // executor check traps. Marking it @Sendable makes it nonisolated;
        // the Task hop below does the main-actor write.
        UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
            let status: Status = switch settings.authorizationStatus {
            case .authorized, .provisional: .granted
            case .denied: .denied
            default: .unknown
            }
            Task { @MainActor in
                self.notifications = status
            }
        }
    }

    // MARK: - Actions

    /// Triggers the system Accessibility prompt (first time) or opens the
    /// Settings pane (after a denial, the prompt no longer shows).
    func fixAccessibility() {
        if !AXIsProcessTrusted() {
            InputInjector.shared.requestAccessibility()
            openSettings(pane: "Privacy_Accessibility")
        }
        refresh()
    }

    /// Registers the app in the Screen Recording list and opens the pane.
    /// Does not call ScreenCaptureKit — that would re-present the system
    /// audio dialog. `CGRequestScreenCaptureAccess` is only used when the
    /// toggle is still off, so a granted app is never asked again.
    func fixScreenRecording() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        openSettings(pane: "Privacy_ScreenCapture")
        refresh()
    }

    func fixNotifications() {
        DeviceAuthorizationManager.shared.requestNotificationPermissions()
        openNotificationSettings()
        refresh()
    }

    private func openSettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Notifications is its own top-level System Settings pane, not a
    /// Privacy & Security anchor — `Privacy_Notifications` isn't a real
    /// anchor there, so the old code landed on the generic Privacy &
    /// Security overview with no Allow toggle in sight. `id=<bundleID>`
    /// deep-links straight to this app's row, where the Allow Notifications
    /// switch lives even after a prior denial.
    private func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.deckhand.mac"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
