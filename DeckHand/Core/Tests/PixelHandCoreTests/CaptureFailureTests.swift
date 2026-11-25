//
//  CaptureFailureTests.swift
//  PixelHandCoreTests
//

import Testing
@testable import PixelHandCore

@Suite("CaptureFailure: capture and mirror errors in words a person can act on")
struct CaptureFailureTests {
    /// What build 19 showed with the Mac locked.
    let build19 = "Live mirror unavailable: The operation couldn’t be completed. (Pixel_Hand.ScreenCaptureService.CaptureError error 2.)"

    @Test("The build 19 raw error with the Mac locked reads as the locked copy")
    func lockedMacBuild19() {
        #expect(CaptureSheetChrome.errorTitle(message: build19, isMirror: true, macLocked: true) == "Mac is locked")
        let body = CaptureSheetChrome.errorMessage(message: build19, isMirror: true, macLocked: true)
        #expect(body.hasPrefix("Unlock the Mac to see its screen."))
        // The Mac now reports a locked failure itself.
        let sent = CaptureFailure.reported(.noDisplay, macLocked: true).message(isMirror: true)
        #expect(sent == LockPolicy.lockedErrorMessage)
        #expect(CaptureSheetChrome.errorTitle(message: sent, isMirror: true) == "Mac is locked")
    }

    @Test("A raw error from an older Mac never reaches the alert")
    func rawNeverShown() {
        let mirror = CaptureSheetChrome.errorMessage(message: build19, isMirror: true)
        #expect(mirror == "The Mac couldn’t start the live screen. Try again.")
        let shot = CaptureSheetChrome.errorMessage(message: "Capture failed: The operation couldn't be completed. (SCStreamErrorDomain error -3801.)", isMirror: false)
        #expect(shot == "The Mac couldn’t take the screenshot. Try again.")
        #expect(CaptureSheetChrome.errorTitle(message: build19, isMirror: true) == "Live screen unavailable")
    }

    @Test("Raw system errors are recognised; sentences are not")
    func rawDetection() {
        for raw in [
            "The operation couldn’t be completed. (Pixel_Hand.ScreenCaptureService.CaptureError error 2.)",
            "The operation couldn't be completed.",
            "Error Domain=NSOSStatusErrorDomain Code=-50 \"(null)\"",
            "Pixel_Hand.ScreenCaptureService.CaptureError",
            "SCStreamErrorDomain error -3801",
            "failed with status: -12",
            "",
            "   ",
        ] {
            #expect(UserFacingError.isRaw(raw), "\(raw)")
            #expect(UserFacingError.sentence(from: raw) == nil, "\(raw)")
        }
        for clean in [
            LockPolicy.lockedErrorMessage,
            LockPolicy.offConsoleMirrorMessage,
            "That window has closed. Refresh the window list and try again.",
            "Enter the code 4821 0934 on the Mac.",
            "Pixel Hand needs Screen Recording on the Mac. Turn it on in System Settings › Privacy & Security › Screen Recording, then try again.",
        ] {
            #expect(!UserFacingError.isRaw(clean), "\(clean)")
            #expect(UserFacingError.sentence(from: clean) == clean, "\(clean)")
        }
    }

    @Test("A sentence is tidied: an older Mac's prefix dropped, capitalised, full stop")
    func tidy() {
        #expect(UserFacingError.sentence(from: "Live mirror unavailable: couldn't open the mirror stream.") == "Couldn't open the mirror stream.")
        #expect(UserFacingError.sentence(from: "no display to capture") == "No display to capture.")
        #expect(UserFacingError.sentence(from: "Timeout") == "Timeout.")
    }

    @Test("Every failure has clean sentence-case copy for both the screenshot and the live screen")
    func everyFailureIsClean() {
        for failure in CaptureFailure.allCases {
            for isMirror in [true, false] {
                let message = failure.message(isMirror: isMirror)
                #expect(!UserFacingError.isRaw(message), "\(failure)")
                #expect(message.first?.isUppercase == true, "\(failure)")
                #expect(message.hasSuffix("."), "\(failure)")
                #expect(!message.contains("Pixel_Hand"), "\(failure)")
                // Shown as is by the remote's alert.
                #expect(CaptureSheetChrome.errorMessage(message: message, isMirror: isMirror) == message
                        || failure == .macLocked, "\(failure)")
            }
        }
        #expect(CaptureFailure.reported(.windowClosed, macLocked: false) == .windowClosed)
    }

    @Test("Alert titles are sentence case")
    func titles() {
        for isMirror in [true, false] {
            for message in ["x", LockPolicy.lockedErrorMessage] {
                let title = CaptureSheetChrome.errorTitle(message: message, isMirror: isMirror)
                let words = title.split(separator: " ").dropFirst()
                #expect(words.allSatisfy { $0 == "Mac" || $0.first?.isLowercase == true }, "\(title)")
            }
        }
    }

    @Test("A failed connection names the Mac and never shows a raw error")
    func connectFailure() {
        let raw = UserFacingError.connectFailure(macName: "Studio", detail: "The operation couldn’t be completed. (Loom.LoomError error 4.)")
        #expect(raw == "Couldn’t connect to Studio. Check that Pixel Hand is open on the Mac, then try again.")
        let clean = UserFacingError.connectFailure(macName: "Studio", detail: "The Mac refused the connection")
        #expect(clean == "Couldn’t connect to Studio. The Mac refused the connection.")
    }
}
