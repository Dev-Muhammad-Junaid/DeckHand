//
//  CloudRecognitionStatusTests.swift
//  DeckHandTests
//
//  The Settings row used to say "Not available … needs a CloudKit container
//  registered to a paid developer account" long after the container was
//  registered. It now reports the build switch and the iCloud account.
//

import XCTest

final class CloudRecognitionStatusTests: XCTestCase {

    func testBuildSwitchOffWinsOverEverything() {
        XCTAssertEqual(CloudRecognitionStatus.resolve(cloudEnabled: false, account: .available), .disabledInBuild)
        XCTAssertEqual(CloudRecognitionStatus.resolve(cloudEnabled: false, account: nil), .disabledInBuild)
    }

    func testAccountStatesMap() {
        XCTAssertEqual(CloudRecognitionStatus.resolve(cloudEnabled: true, account: nil), .checking)
        XCTAssertEqual(CloudRecognitionStatus.resolve(cloudEnabled: true, account: .available), .on)
        XCTAssertEqual(CloudRecognitionStatus.resolve(cloudEnabled: true, account: .noAccount), .noAccount)
        for account: CloudRecognitionStatus.Account in [.restricted, .temporarilyUnavailable, .couldNotDetermine] {
            XCTAssertEqual(CloudRecognitionStatus.resolve(cloudEnabled: true, account: account), .unavailable)
        }
    }

    func testThisBuildHasCloudKitOn() {
        XCTAssertTrue(DeckHandCloud.isCloudEnabled)
        XCTAssertEqual(DeckHandCloud.containerIdentifier, "iCloud.com.widgetsflow.pixelhand")
    }

    func testNoCopyMentionsTheOldRegistrationBlocker() {
        let all: [CloudRecognitionStatus] = [.checking, .on, .noAccount, .unavailable, .disabledInBuild]
        let text = all.map { $0.badge + " " + $0.detail }.joined(separator: " ") + CloudRecognitionStatus.footer
        XCTAssertFalse(text.contains("paid developer account"))
        XCTAssertFalse(text.contains("registered"))
        XCTAssertEqual(CloudRecognitionStatus.on.badge, "On")
    }

    func testCopyDoesNotPromiseSkippingApproval() {
        // The Mac still prompts for every connection (DeviceAuthorizationManager).
        XCTAssertFalse(CloudRecognitionStatus.on.detail.contains("without the approval"))
        XCTAssertTrue(CloudRecognitionStatus.footer.contains("still asks"))
    }
}
