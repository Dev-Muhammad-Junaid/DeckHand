//
//  CaptureHandler.swift
//  DeckHandMac
//
//  Domain: capture. Full-screen, region and window captures and the window
//  list, through `ScreenCaptureService`. Owned by the mirror lane.
//

import CoreGraphics
import Foundation
import LoomKit

@MainActor
final class CaptureHandler: DomainHandler {
    func handle(_ message: CaptureMessage, from connection: LoomConnectionHandle) async {
        switch message {
        // ScreenCaptureKit calls can hang outright when the TCC grant is
        // wedged, so each request runs in its own task.
        case let .requestScreenshot(requestID, mode, quality):
            Task {
                await self.handleScreenshotRequest(
                    requestID: requestID,
                    mode: mode,
                    quality: quality,
                    handle: connection
                )
            }

        case let .requestWindowList(requestID):
            Task { await self.handleWindowListRequest(requestID: requestID, handle: connection) }

        case .screenshotData, .screenshotError, .windowListResponse:
            break // Mac → remote only
        }
    }

    /// Captures the requested slice of the screen and sends it back as JPEG,
    /// or sends a descriptive `screenshotError` so the iPad can dismiss its
    /// spinner and show a useful message. `requestID` is echoed verbatim so
    /// the iPad can drop responses belonging to a timed-out earlier tap.
    private func handleScreenshotRequest(
        requestID: String,
        mode: CaptureMode,
        quality: CaptureQuality,
        handle: LoomConnectionHandle
    ) async {
        do {
            // Format is per-mode now: full-screen is JPEG (small payloads
            // for the common case), region and window are PNG (lossless,
            // alpha-preserving). Callers on the iPad just decode via
            // UIImage(data:) so they don't care which.
            let payload: Data
            switch mode {
            case .fullScreen:
                // Quality only moves the full-screen path; the region and
                // window paths below already ship near-native pixels.
                payload = try await ScreenCaptureService.shared.captureMainDisplayJPEG(
                    maxWidth: quality.maxWidth,
                    quality: quality.jpegQuality
                )
            case let .region(x, y, width, height):
                let rect = CGRect(
                    x: CGFloat(x),
                    y: CGFloat(y),
                    width: CGFloat(width),
                    height: CGFloat(height)
                )
                payload = try await ScreenCaptureService.shared.captureRegion(normalizedRect: rect)
            case let .window(windowID):
                payload = try await ScreenCaptureService.shared.captureWindowJPEG(windowID: windowID)
            }
            try await handle.send(.capture(.screenshotData(requestID: requestID, data: payload)))
        } catch {
            // A sentence for the remote's alert, never the raw error
            // (build 19); "The Mac is locked." while it is locked.
            DeckHandLog.app.error("Screenshot failed: \(error.localizedDescription, privacy: .public)")
            let failure = CaptureFailure.reported(for: error)
            await sendError(requestID: requestID, to: handle, message: failure.message(isMirror: false))
        }
    }

    private func handleWindowListRequest(requestID: String, handle: LoomConnectionHandle) async {
        do {
            let windows = try await ScreenCaptureService.shared.enumerateWindows()
            try await handle.send(.capture(.windowListResponse(requestID: requestID, windows: windows)))
        } catch {
            // Window enumeration failures share the same TCC requirement as
            // capture, so route them through the same error channel — the
            // iPad already knows how to surface this copy.
            DeckHandLog.app.error("Window list failed: \(error.localizedDescription, privacy: .public)")
            let cause = CaptureFailure.cause(of: error)
            let failure = CaptureFailure.reported(
                for: nil,
                fallback: cause == .screenRecordingDenied ? cause : .windowListFailed
            )
            await sendError(requestID: requestID, to: handle, message: failure.message(isMirror: false))
        }
    }

    private func sendError(requestID: String, to handle: LoomConnectionHandle, message: String) async {
        try? await handle.send(.capture(.screenshotError(requestID: requestID, message: message)))
    }
}
