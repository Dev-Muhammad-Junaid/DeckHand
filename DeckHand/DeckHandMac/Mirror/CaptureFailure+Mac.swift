//
//  CaptureFailure+Mac.swift
//  DeckHandMac
//
//  Maps what ScreenCaptureKit and `ScreenCaptureService` throw onto
//  PixelHandCore's `CaptureFailure`, so the remote gets a sentence, never
//  "Pixel_Hand.ScreenCaptureService.CaptureError error 2" (build 19). A
//  locked Mac explains every failure: ScreenCaptureKit lists no display
//  while the screen is locked.
//

import Foundation

extension CaptureFailure {
    /// ScreenCaptureKit's "user declined" (`SCStreamError.userDeclined`).
    private static let screenCaptureKitDomain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
    private static let userDeclinedCode = -3801

    /// The failure behind `error`, ignoring the lock state.
    static func cause(of error: Error) -> CaptureFailure {
        if let capture = error as? ScreenCaptureService.CaptureError {
            switch capture {
            case .permissionDenied: return .screenRecordingDenied
            case .noDisplay: return .noDisplay
            case .windowNotFound: return .windowClosed
            case .captureFailed: return .captureFailed
            case .encodeFailed: return .encodeFailed
            }
        }
        let ns = error as NSError
        if ns.domain == screenCaptureKitDomain || ns.domain == "SCStreamErrorDomain",
           ns.code == userDeclinedCode {
            return .screenRecordingDenied
        }
        return .captureFailed
    }

    /// The failure to report to a remote for `error` (or for `fallback`
    /// when there is no error): `.macLocked` while the Mac is locked.
    @MainActor
    static func reported(for error: Error?, fallback: CaptureFailure = .captureFailed) -> CaptureFailure {
        reported(error.map(cause(of:)) ?? fallback, macLocked: MacLockMonitor.shared.state.isLocked)
    }
}
