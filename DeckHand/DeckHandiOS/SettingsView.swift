//
//  SettingsView.swift
//  DeckHandiOS
//
//  The remote's preferences. Grouped so the two costly sections — mirror and
//  pointer — read as the ones worth touching, with footers that say what a
//  choice actually costs rather than just what it does.
//
//  Segmented controls carry their own titles: a `Picker` in a `Form` drops
//  its label under `.segmented`, which leaves bare options like "Off / Light
//  / Full" floating with nothing to say what they belong to.
//

import CloudKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                mirrorSection
                pointerSection
                captureSection
                appsSection
                appearanceSection
                connectionSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(OpaqueSettingsBar())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Applied here as well as at the app root: a sheet gets its own
        // presentation host, so without this the appearance change wouldn't
        // reach the very screen you changed it on until it was reopened.
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    // MARK: - Live mirror

    private var mirrorSection: some View {
        Section {
            Picker("Sharpness", selection: $settings.mirrorSharpness) {
                ForEach(MirrorSharpness.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Text(settings.mirrorSharpness.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)

            SettingBlock("Frame rate") {
                Picker("Frame rate", selection: $settings.mirrorFrameRate) {
                    ForEach(MirrorFrameRate.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Remember size and position", isOn: $settings.rememberMirrorLayout)
        } header: {
            Text("Live mirror")
        } footer: {
            Text("Sharpness and frame rate together decide how much of your network the mirror uses. Drop both if the picture stutters before you blame the Mac.")
        }
    }

    // MARK: - Pointer

    private var pointerSection: some View {
        Section {
            SettingBlock("Sensitivity", value: TrackpadSensitivity.label(for: settings.pointerSensitivity)) {
                Slider(
                    value: Binding(
                        get: { Double(TrackpadSensitivity.nearestIndex(to: settings.pointerSensitivity)) },
                        set: { settings.pointerSensitivity = TrackpadSensitivity.anchors[Int($0.rounded())] }
                    ),
                    in: TrackpadSensitivity.indexRange,
                    step: 1
                )
                .accessibilityLabel("Pointer sensitivity")
                .accessibilityValue(TrackpadSensitivity.label(for: settings.pointerSensitivity))
            }

            SettingBlock("Haptics", caption: "Taps and gestures buzz the iPad.") {
                Picker("Haptics", selection: $settings.hapticStrength) {
                    ForEach(HapticStrength.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Natural scrolling", isOn: $settings.naturalScrolling)

            SettingBlock("Send rate", caption: "How often touches are sent to the Mac.") {
                Picker("Send rate", selection: $settings.inputSendRate) {
                    ForEach(InputSendRate.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } header: {
            Text("Pointer and gestures")
        } footer: {
            Text("Natural scrolling moves the content with your fingers. 120 Hz matches ProMotion so no touch is discarded; 60 Hz halves the packets if the pointer feels erratic on a busy network.")
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        Section {
            Picker("Capture button", selection: $settings.defaultCapture) {
                ForEach(DefaultCapture.allCases) { option in
                    Label(option.label, systemImage: option.icon).tag(option)
                }
            }

            SettingBlock("Quality", caption: settings.screenshotQuality.detail) {
                Picker("Quality", selection: $settings.screenshotQuality) {
                    ForEach(CaptureQuality.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Save to Photos automatically", isOn: $settings.autoSaveToPhotos)
        } header: {
            Text("Screenshots")
        } footer: {
            Text("Quality applies to full-screen captures. Region and window captures already ship at close to native resolution. Saving automatically asks for Photos access the first time a capture lands.")
        }
    }

    // MARK: - Apps

    /// Only appears once something is hidden. Hiding happens from a context
    /// menu in the Apps grid, which has no way to undo itself.
    @ViewBuilder
    private var appsSection: some View {
        let hidden = settings.hiddenAppBundleIDs
        if !hidden.isEmpty {
            Section {
                HStack {
                    Text("Hidden apps")
                    Spacer()
                    Text("\(hidden.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("Show hidden apps") {
                    settings.unhideAllApps()
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("Hidden apps are removed from the Apps grid and its search results. This puts them all back.")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            SettingBlock("Theme") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Applies to the control screens. The device picker stays dark to match the app icon.")
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            CloudRecognitionRow()
        } header: {
            Text("Connection")
        } footer: {
            Text(CloudRecognitionStatus.footer)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle("Share crash reports", isOn: $settings.shareCrashReports)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Sends crash, hang and performance reports to the developer so problems can be fixed. They include the device model, system version and what the app was doing — never your screen, your captures, your device names or who you are. Applies to this device; the Mac has its own switch.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Button("Show the welcome tour again") {
                settings.hasCompletedOnboarding = false
                dismiss()
            }
        } footer: {
            Text("Rows marked \(Text("Not available").italic()) are visible so you know they're planned, but they do nothing yet.")
        }
    }
}

// MARK: - Building blocks

/// Keeps scrolled rows from showing through the "Settings" title.
///
/// In a sheet the inline bar is transparent until content scrolls under it,
/// and on iOS 26 its soft scroll-edge blur let glass controls such as the
/// segmented pickers read straight through the title in dark mode. A
/// visible bar background, plus a hard scroll edge on iOS 26, keeps the
/// title on a solid surface in both appearances.
private struct OpaqueSettingsBar: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
                .toolbarBackground(.visible, for: .navigationBar)
        }
        #else
        content
            .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }
}

/// A titled control. Segmented pickers and sliders lose their `Picker` label
/// inside a `Form`, so the title is drawn explicitly above the control.
private struct SettingBlock<Content: View>: View {
    let title: String
    var value: String?
    var caption: String?
    @ViewBuilder let content: Content

    init(
        _ title: String,
        value: String? = nil,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                if let value {
                    Spacer()
                    Text(value)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// "Recognize my own devices": reports whether same-iCloud recognition is
/// working on this device, from the build switch and the iCloud account.
private struct CloudRecognitionRow: View {
    @State private var account: CloudRecognitionStatus.Account?

    private var status: CloudRecognitionStatus {
        .resolve(cloudEnabled: DeckHandCloud.isCloudEnabled, account: account)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Recognize my own devices")
                    .foregroundStyle(status.isActive ? Color.primary : Color.secondary)
                Spacer(minLength: 8)
                Text(status.badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.isActive ? DeckHandTheme.Brand.mint : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill((status.isActive ? DeckHandTheme.Brand.mint : Color.secondary).opacity(0.14))
                    )
            }
            Text(status.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recognize my own devices. \(status.badge). \(status.detail)")
        .task {
            // Never touch CKContainer when the build has CloudKit off: the
            // container needs the iCloud entitlement to exist.
            guard DeckHandCloud.isCloudEnabled else { return }
            account = await Self.currentAccount()
        }
    }

    private static func currentAccount() async -> CloudRecognitionStatus.Account {
        do {
            let status = try await CKContainer(identifier: DeckHandCloud.containerIdentifier).accountStatus()
            switch status {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            case .couldNotDetermine: return .couldNotDetermine
            @unknown default: return .couldNotDetermine
            }
        } catch {
            DeckHandLog.app.error("iCloud account status failed: \(error.localizedDescription, privacy: .public)")
            return .couldNotDetermine
        }
    }
}
