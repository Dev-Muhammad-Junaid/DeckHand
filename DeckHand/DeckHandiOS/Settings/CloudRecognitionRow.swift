//
//  CloudRecognitionRow.swift
//  DeckHandiOS
//
//  The "Recognize my own devices" row in Settings › Connection.
//

import CloudKit
import SwiftUI

/// "Recognize my own devices": reports whether same-iCloud recognition is
/// working on this device, from the build switch and the iCloud account.
struct CloudRecognitionRow: View {
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
