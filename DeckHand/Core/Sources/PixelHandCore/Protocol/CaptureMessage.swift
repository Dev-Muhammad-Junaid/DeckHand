//
//  CaptureMessage.swift
//  PixelHandCore
//
//  Domain: capture and OCR. Full-screen, region and window captures and the
//  window list. Both ways. OCR runs on the remote, on the image it gets
//  back. Owned by the capture side (`CaptureHandler`, the remote's capture
//  coordinator).
//

import Foundation

public enum CaptureMessage: Codable, Sendable, Equatable {
    // MARK: Remote → Mac

    /// Capture `mode` and reply with `screenshotData` or `screenshotError`
    /// echoing `requestID`, so a late reply to an abandoned request is
    /// dropped.
    case requestScreenshot(requestID: String, mode: CaptureMode, quality: CaptureQuality)
    /// List the visible windows. Reply: `windowListResponse`.
    case requestWindowList(requestID: String)

    // MARK: Mac → remote

    /// JPEG (full screen, window) or PNG (region) bytes.
    case screenshotData(requestID: String, data: Data)
    case screenshotError(requestID: String, message: String)
    case windowListResponse(requestID: String, windows: [WindowInfo])
}
