//
//  ApprovalStatusCopyTests.swift
//  DeckHandTests
//
//  The Mac answers "denied" both for a click on Deny and for its 45 s
//  approval expiry. The remote used to say "was declined" for both.
//

import XCTest

final class ApprovalStatusCopyTests: XCTestCase {

    func testQuickDenialStaysDenied() {
        XCTAssertEqual(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 3), "denied")
        XCTAssertEqual(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 30), "denied")
    }

    func testDenialAtTheExpiryReadsAsTimeout() {
        XCTAssertEqual(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 45), ApprovalStatusCopy.timedOutStatus)
        XCTAssertEqual(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 44.2), ApprovalStatusCopy.timedOutStatus)
        XCTAssertEqual(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 47), ApprovalStatusCopy.timedOutStatus)
    }

    func testOtherStatusesPassThrough() {
        for status in ["pending", "granted", "host_disconnected"] {
            XCTAssertEqual(ApprovalStatusCopy.displayStatus(forWireStatus: status, pendingFor: 60), status)
        }
    }

    func testTimeoutCopySaysItTimedOut() {
        let copy = ApprovalStatusCopy.overlay(status: ApprovalStatusCopy.timedOutStatus, peerName: "Studio Mac")
        XCTAssertEqual(copy.title, "Request Timed Out")
        XCTAssertTrue(copy.message.contains("45 seconds"))
        XCTAssertTrue(copy.message.contains("Studio Mac"))
        XCTAssertFalse(copy.message.contains("declined"))
    }

    func testDenialCopyStillSaysDeclined() {
        let copy = ApprovalStatusCopy.overlay(status: "denied", peerName: "Studio Mac")
        XCTAssertEqual(copy.title, "Access Denied")
        XCTAssertTrue(copy.message.contains("declined"))
    }

    func testTimeoutIsTerminalAndFinal() {
        XCTAssertTrue(ApprovalStatusCopy.isTerminal(ApprovalStatusCopy.timedOutStatus))
        XCTAssertTrue(ApprovalStatusCopy.isFinalVerdict(ApprovalStatusCopy.timedOutStatus))
        XCTAssertTrue(ApprovalStatusCopy.isTerminal("host_disconnected"))
        XCTAssertFalse(ApprovalStatusCopy.isFinalVerdict("host_disconnected"))
        XCTAssertFalse(ApprovalStatusCopy.isTerminal("pending"))
        XCTAssertFalse(ApprovalStatusCopy.isTerminal("granted"))
    }
}
