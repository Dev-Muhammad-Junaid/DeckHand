//
//  ApprovalStatusCopyTests.swift
//  PixelHandCoreTests
//
//  The Mac answers "denied" both for a click on Deny and for its 45 s
//  approval expiry. The remote used to say "was declined" for both.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct ApprovalStatusCopyTests {

    @Test func quickDenialStaysDenied() {
        #expect(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 3) == "denied")
        #expect(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 30) == "denied")
    }

    @Test func denialAtTheExpiryReadsAsTimeout() {
        #expect(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 45) == ApprovalStatusCopy.timedOutStatus)
        #expect(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 44.2) == ApprovalStatusCopy.timedOutStatus)
        #expect(ApprovalStatusCopy.displayStatus(forWireStatus: "denied", pendingFor: 47) == ApprovalStatusCopy.timedOutStatus)
    }

    @Test func otherStatusesPassThrough() {
        for status in ["pending", "granted", "host_disconnected"] {
            #expect(ApprovalStatusCopy.displayStatus(forWireStatus: status, pendingFor: 60) == status)
        }
    }

    @Test func timeoutCopySaysItTimedOut() {
        let copy = ApprovalStatusCopy.overlay(status: ApprovalStatusCopy.timedOutStatus, peerName: "Studio Mac")
        #expect(copy.title == "Request Timed Out")
        #expect(copy.message.contains("45 seconds"))
        #expect(copy.message.contains("Studio Mac"))
        #expect(!copy.message.contains("declined"))
    }

    @Test func denialCopyStillSaysDeclined() {
        let copy = ApprovalStatusCopy.overlay(status: "denied", peerName: "Studio Mac")
        #expect(copy.title == "Access Denied")
        #expect(copy.message.contains("declined"))
    }

    @Test func timeoutIsTerminalAndFinal() {
        #expect(ApprovalStatusCopy.isTerminal(ApprovalStatusCopy.timedOutStatus))
        #expect(ApprovalStatusCopy.isFinalVerdict(ApprovalStatusCopy.timedOutStatus))
        #expect(ApprovalStatusCopy.isTerminal("host_disconnected"))
        #expect(!ApprovalStatusCopy.isFinalVerdict("host_disconnected"))
        #expect(!ApprovalStatusCopy.isTerminal("pending"))
        #expect(!ApprovalStatusCopy.isTerminal("granted"))
    }
}

@Suite struct ConnectionHeaderStatusTests {

    @Test func headerSaysConnectedOnlyWhenGranted() {
        #expect(ApprovalStatusCopy.headerSubtitle(status: "granted", activeAppName: nil) == "Connected")
        #expect(ApprovalStatusCopy.headerSubtitle(status: "granted", activeAppName: "Safari") == "Safari")
        for status in ["pending", "denied", ApprovalStatusCopy.timedOutStatus, "host_disconnected", "weird"] {
            let subtitle = ApprovalStatusCopy.headerSubtitle(status: status, activeAppName: "Safari")
            #expect(subtitle != "Connected", "\(status)")
            #expect(subtitle != "Safari", "\(status)")
        }
    }

    @Test func waitingAndDeniedHeaders() {
        #expect(ApprovalStatusCopy.headerSubtitle(status: "pending", activeAppName: nil) == "Waiting for approval")
        #expect(ApprovalStatusCopy.headerSubtitle(status: "denied", activeAppName: nil) == "Not allowed")
    }

    @Test func liveIndicatorOnlyWhenGranted() {
        #expect(ApprovalStatusCopy.showsLiveIndicator(status: "granted"))
        #expect(!(ApprovalStatusCopy.showsLiveIndicator(status: "pending")))
        #expect(!(ApprovalStatusCopy.showsLiveIndicator(status: "denied")))
        #expect(!(ApprovalStatusCopy.showsLiveIndicator(status: "host_disconnected")))
    }
}
