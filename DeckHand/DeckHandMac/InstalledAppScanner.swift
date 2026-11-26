//
//  InstalledAppScanner.swift
//  DeckHandMac
//

import AppKit
import Combine
import Foundation

/// Scans macOS application directories and produces a lightweight catalog
/// of installed user-facing apps with compressed icon data.
@MainActor
final class InstalledAppScanner {
    static let shared = InstalledAppScanner()

    /// Cached result so we don't rescan on every iPad connect.
    private var cachedApps: [InstalledAppInfo]?
    private var cachedBundleIDs: Set<String> = []
    private var lastScanDate: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Auto-invalidate when an app the cache hasn't seen launches. Newly
        // installed apps get picked up on the next iPad request without
        // having to wait out the 5-minute TTL.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular,
                      let bundleID = app.bundleIdentifier
                else { return }
                Task { @MainActor in
                    if !self.cachedBundleIDs.contains(bundleID) {
                        self.invalidateCache()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Returns cached apps if scanned within the last 5 minutes, otherwise rescans.
    func installedApps() -> [InstalledAppInfo] {
        if let cached = cachedApps,
           let lastScan = lastScanDate,
           Date().timeIntervalSince(lastScan) < 300 {
            return cached
        }
        let apps = scanInstalledApps()
        cachedApps = apps
        cachedBundleIDs = Set(apps.map(\.bundleID))
        lastScanDate = Date()
        return apps
    }

    /// Force-clears the cache so the next request triggers a fresh scan.
    func invalidateCache() {
        cachedApps = nil
        cachedBundleIDs.removeAll()
        lastScanDate = nil
    }

    // MARK: - Scanning

    private func scanInstalledApps() -> [InstalledAppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
        ]

        var seen = Set<String>()   // deduplicate by bundleID
        var apps: [InstalledAppInfo] = []
        // Running apps always get full-size icons (they're the dock); the
        // rest drop to the fallback size once the list's byte budget is
        // spent (`AppIconPolicy`, OT-1).
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var iconBytes = 0

        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let info = appInfo(at: url, running: running, iconBytes: iconBytes),
                      !seen.contains(info.bundleID) else {
                    continue
                }
                seen.insert(info.bundleID)
                iconBytes += info.iconData?.count ?? 0
                apps.append(info)
            }
        }

        // Safety-net: any regular running app that the directory scan
        // missed gets added from its `NSRunningApplication.bundleURL`.
        // Modern macOS hides Safari and some system apps inside
        // cryptex / System volumes where the directory enumerator can
        // silently fail — we'd still want them in the grid so the
        // "Apps" tab actually reflects what's on the Mac.
        //
        // Uses `runningAppInfo(_:)` which bypasses the LSUIElement /
        // LSBackgroundOnly filters — a running `.regular` app is by
        // definition user-facing, regardless of what its Info.plist claims.
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                  !seen.contains(bundleID),
                  let info = runningAppInfo(app) else { continue }
            seen.insert(bundleID)
            apps.append(info)
        }

        // No artificial cap. Icons carry transparency now (PNG or HEIC with
        // alpha at 2× the dock's size, `AppIconPolicy`); the per-icon and
        // list budgets keep ~500 apps to a few MB, which streams across
        // Loom in about a second on local Wi-Fi. If this ever becomes a
        // bottleneck, paginate via a `requestAppListPage(offset:)` message
        // rather than silently truncate the alphabet.
        return apps.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Reads bundle metadata and extracts a small icon for the given .app URL.
    /// Returns `nil` for background-only apps and system frameworks.
    private func appInfo(at url: URL, running: Set<String>, iconBytes: Int) -> InstalledAppInfo? {
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else {
            return nil
        }

        // Filter out background-only / agent / menu-bar-only apps
        let infoDict = bundle.infoDictionary ?? [:]
        if infoDict["LSBackgroundOnly"] as? Bool == true { return nil }
        if infoDict["LSUIElement"] as? Bool == true { return nil }

        // Get display name (prefer CFBundleDisplayName, fall back to CFBundleName, then filename)
        let displayName = infoDict["CFBundleDisplayName"] as? String
            ?? infoDict["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        // Skip apps with no meaningful name
        if displayName.isEmpty { return nil }

        // The icon with transparency, full size while the list is in budget.
        let side = AppIconPolicy.pixelSide(usedBytes: iconBytes, isRunning: running.contains(bundleID))
        let iconData = AppIconEncoder.icon(for: url, pixelSide: side)

        return InstalledAppInfo(
            bundleID: bundleID,
            displayName: displayName,
            iconData: iconData
        )
    }

    /// Unfiltered `InstalledAppInfo` from an `NSRunningApplication`. Skips
    /// the LSUIElement/LSBackgroundOnly checks because we're being called
    /// for an app the user is literally interacting with right now —
    /// whatever its Info.plist says about itself, it's user-facing.
    private func runningAppInfo(_ app: NSRunningApplication) -> InstalledAppInfo? {
        guard let bundleID = app.bundleIdentifier,
              let bundleURL = app.bundleURL else { return nil }
        let bundle = Bundle(url: bundleURL)
        let info = bundle?.infoDictionary ?? [:]
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? app.localizedName
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let iconData = AppIconEncoder.icon(for: bundleURL)
        return InstalledAppInfo(
            bundleID: bundleID,
            displayName: displayName,
            iconData: iconData
        )
    }
}
