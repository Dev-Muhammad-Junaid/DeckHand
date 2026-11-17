//
//  CloudRecognitionStatusTests.swift
//  PixelHandCoreTests
//
//  The Settings row used to say "Not available … needs a CloudKit container
//  registered to a paid developer account" long after the container was
//  registered. It now reports the build switch and the iCloud account.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct CloudRecognitionStatusTests {

    @Test func buildSwitchOffWinsOverEverything() {
        #expect(CloudRecognitionStatus.resolve(cloudEnabled: false, account: .available) == .disabledInBuild)
        #expect(CloudRecognitionStatus.resolve(cloudEnabled: false, account: nil) == .disabledInBuild)
    }

    @Test func accountStatesMap() {
        #expect(CloudRecognitionStatus.resolve(cloudEnabled: true, account: nil) == .checking)
        #expect(CloudRecognitionStatus.resolve(cloudEnabled: true, account: .available) == .on)
        #expect(CloudRecognitionStatus.resolve(cloudEnabled: true, account: .noAccount) == .noAccount)
        for account: CloudRecognitionStatus.Account in [.restricted, .temporarilyUnavailable, .couldNotDetermine] {
            #expect(CloudRecognitionStatus.resolve(cloudEnabled: true, account: account) == .unavailable)
        }
    }

    @Test func noCopyMentionsTheOldRegistrationBlocker() {
        let all: [CloudRecognitionStatus] = [.checking, .on, .noAccount, .unavailable, .disabledInBuild]
        let text = all.map { $0.badge + " " + $0.detail }.joined(separator: " ") + CloudRecognitionStatus.footer
        #expect(!(text.contains("paid developer account")))
        #expect(!text.contains("registered"))
        #expect(CloudRecognitionStatus.on.badge == "On")
    }

    @Test func copyDoesNotPromiseSkippingApproval() {
        // The Mac still prompts for every connection (DeviceAuthorizationManager).
        #expect(!(CloudRecognitionStatus.on.detail.contains("without the approval")))
        #expect(CloudRecognitionStatus.footer.contains("still asks"))
    }
}
