//
//  CaptureCoordinator.swift
//  DeckHandiOS
//
//  The capture state machine that used to live in `ControlView`: full
//  screen, region (pick then capture), window and OCR captures, the window
//  list, and the error alert (which the live mirror also uses). Owned by
//  `ControlSessionModel`; the sheets that show its state are in
//  `ControlCaptureSheets`.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class CaptureCoordinator {
    /// Set by `ControlSessionModel` once the session's sender exists.
    @ObservationIgnored var sender: TrackpadSender?

    var screenshotImage: UIImage?
    var isRequestingScreenshot = false   // in-flight guard
    var isScreenshotPresented = false
    @ObservationIgnored var screenshotTimeoutTask: Task<Void, Never>?
    var screenshotErrorMessage: String?
    /// The error alert is about the live mirror, not a capture.
    var screenshotErrorIsMirror = false
    /// Token of the most recently issued screenshot request. Responses
    /// echo this value back; any mismatch is dropped on the floor so a
    /// slow, late-arriving capture from a previous tap can't show up
    /// inside the next request's full-screen cover.
    var screenshotRequestID: String?

    // ── Capture-menu state ──────────────────────────────────────────
    /// What the *next* `screenshotData` payload is for. Drives whether we
    /// jump to the preview, the region cropper, or the OCR sheet. Set at
    /// request time and cleared on response / error / timeout.
    var screenshotIntent: ScreenshotIntent = .fullScreen
    /// Full-screen reference shipped to `RegionCropView` so the user can
    /// draw a rect against actual Mac pixels rather than a black canvas.
    var regionReferenceImage: UIImage?
    var isRegionCropPresented = false
    /// What the capture on screen is (the sheet's status strip), and the
    /// step the capture sheet opens at: "Recognize Text" opens straight at
    /// read text (UX-009: one sheet, no separate OCR sheet).
    var capturedKind: CaptureKind = .fullScreen
    var captureInitialStep: CaptureStep = .preview
    /// Latest window list pushed back from the Mac and the picker's load
    /// state. We re-fetch every time the picker opens so the user never
    /// sees stale entries for windows that were closed since the last request.
    var availableWindows: [WindowInfo] = []
    var isWindowPickerPresented = false
    var isWindowListLoading = false
    var windowListRequestID: String?
    /// What a pick in the window picker does: capture the window, or (S14)
    /// mirror it, through `onPickMirrorWindow` (set by the session model).
    var windowPickerPurpose: WindowPickerPurpose = .capture
    @ObservationIgnored var onPickMirrorWindow: ((WindowInfo) -> Void)?

    enum WindowPickerPurpose: Equatable {
        case capture
        case mirror
    }

    /// Drives post-arrival routing for `screenshotData`. Each tap path sets
    /// the matching intent so the response flows into the right UI without
    /// a global "what was the last button?" state machine.
    enum ScreenshotIntent: Equatable {
        case fullScreen
        /// First leg of the region flow: we asked for a full-screen capture
        /// that's about to feed into `RegionCropView`.
        case regionPicking
        /// Second leg of the region flow: the actual cropped capture the
        /// user wants to save / share / annotate.
        case regionFinal
        /// Capturing a single window picked from the window list sheet.
        case window(WindowInfo)
        /// Capturing for OCR rather than for visual presentation.
        case ocr
    }

    // MARK: - Capture flow

    /// Runs whichever capture the user set as the tap action on the capture
    /// button.
    func beginDefaultCapture(settings: DeckHandSettings) {
        switch settings.defaultCapture {
        case .fullScreen: beginCapture(intent: .fullScreen, mode: .fullScreen, quality: settings.screenshotQuality)
        case .region: beginCapture(intent: .regionPicking, mode: .fullScreen, quality: settings.screenshotQuality)
        case .window: openWindowPicker()
        }
    }

    /// Common entry point for every "ask the Mac to capture something" flow.
    /// Sets the routing intent, allocates a fresh request token, opens the
    /// loading overlay, and arms the 8 s timeout. Sheets that branch off
    /// the eventual response (region crop, OCR) are presented in the
    /// `screenshotData` handler based on `screenshotIntent`.
    func beginCapture(intent: ScreenshotIntent, mode: CaptureMode, quality: CaptureQuality) {
        guard let sender, !isRequestingScreenshot else { return }
        GestureHaptic.light.trigger()

        screenshotImage = nil
        screenshotErrorMessage = nil
        screenshotErrorIsMirror = false
        isRequestingScreenshot = true
        // Region-picking and OCR intents don't show the loading overlay
        // until the user has confirmed the capture path; the loading
        // overlay only fronts for "you'll see this image directly" intents.
        switch intent {
        case .fullScreen, .window, .regionFinal:
            isScreenshotPresented = true
        case .regionPicking, .ocr:
            isScreenshotPresented = true   // keep a uniform loader
        }
        screenshotIntent = intent
        let requestID = UUID().uuidString
        screenshotRequestID = requestID

        Task {
            await sender.requestScreenshot(
                requestID: requestID,
                mode: mode,
                quality: quality
            )
        }

        screenshotTimeoutTask?.cancel()
        screenshotTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 8_000_000_000)
            } catch {
                return
            }
            guard let self, self.screenshotRequestID == requestID else { return }
            self.screenshotRequestID = nil
            self.isRequestingScreenshot = false
            self.isScreenshotPresented = false
            self.isRegionCropPresented = false
            self.screenshotIntent = .fullScreen
            self.screenshotErrorMessage = "The Mac didn't respond in time. Make sure Screen Recording is allowed in System Settings > Privacy & Security > Screen Recording."
        }
    }

    /// The loading cover's Cancel button.
    func cancelPendingCapture() {
        screenshotTimeoutTask?.cancel()
        screenshotRequestID = nil
        isRequestingScreenshot = false
        isScreenshotPresented = false
    }

    /// Triggered from the capture menu's "Window…" item. Opens the picker
    /// sheet with whatever cached list we have, then refreshes from the Mac
    /// in parallel so the rows update under the user's finger.
    func openWindowPicker(purpose: WindowPickerPurpose = .capture) {
        guard sender != nil else { return }
        GestureHaptic.light.trigger()
        windowPickerPurpose = purpose
        isWindowPickerPresented = true
        refreshWindowList()
    }

    func refreshWindowList() {
        guard let sender else { return }
        let requestID = UUID().uuidString
        windowListRequestID = requestID
        isWindowListLoading = true
        Task { await sender.requestWindowList(requestID: requestID) }

        // 6 s safety net so the spinner doesn't hang forever if the Mac
        // never replies (TCC pulled, app crashed, etc.).
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self else { return }
            if self.windowListRequestID == requestID {
                self.windowListRequestID = nil
                self.isWindowListLoading = false
            }
        }
    }

    /// A window was picked in the picker: capture it, or mirror it.
    func handleWindowPicked(_ window: WindowInfo, quality: CaptureQuality) {
        isWindowPickerPresented = false
        switch windowPickerPurpose {
        case .capture:
            beginCapture(intent: .window(window), mode: .window(windowID: window.windowID), quality: quality)
        case .mirror:
            onPickMirrorWindow?(window)
        }
        windowPickerPurpose = .capture
    }

    // MARK: - Region crop confirmation

    /// Called by `RegionCropView` once the user picks a rect. We tear down
    /// the crop sheet and immediately ask the Mac for a *fresh* capture
    /// of just that rect — much sharper than re-cropping the iPad-side
    /// JPEG, since the Mac still has the native pixel grid.
    func handleRegionConfirm(_ normalizedRect: CGRect?, quality: CaptureQuality) {
        isRegionCropPresented = false
        regionReferenceImage = nil
        guard let rect = normalizedRect else {
            // User cancelled — go back to idle state.
            screenshotIntent = .fullScreen
            return
        }
        let mode = CaptureMode.region(
            x: Float(rect.origin.x),
            y: Float(rect.origin.y),
            width: Float(rect.width),
            height: Float(rect.height)
        )
        beginCapture(intent: .regionFinal, mode: mode, quality: quality)
    }

    // MARK: - Replies from the Mac

    func handleScreenshotData(requestID: String, data: Data) {
        // Drop responses for a request we've already given up on
        // (timeout fired, user dismissed, or a newer request
        // overwrote the token).
        guard requestID == screenshotRequestID else {
            #if DEBUG
            print("DeckHandiOS: ⏭️ dropping stale screenshotData (\(requestID))")
            #endif
            return
        }
        screenshotTimeoutTask?.cancel()
        isRequestingScreenshot = false
        screenshotRequestID = nil

        guard let img = UIImage(data: data) else {
            // Data arrived but was not a valid image
            isScreenshotPresented = false
            isRegionCropPresented = false
            screenshotErrorMessage = "Received invalid image data from Mac."
            screenshotIntent = .fullScreen
            return
        }

        // Branch on the intent that requested this capture so the
        // image lands in the right UI surface — preview sheet,
        // crop overlay, or OCR sheet.
        switch screenshotIntent {
        case .fullScreen, .window, .regionFinal, .ocr:
            capturedKind = switch screenshotIntent {
            case .window(let window): .window(appName: window.appName)
            case .regionFinal: .region
            default: .fullScreen
            }
            captureInitialStep = screenshotIntent == .ocr ? .readText : .preview
            // isScreenshotPresented is already true; the cover swaps its
            // loading state for the capture sheet.
            screenshotImage = img
            screenshotIntent = .fullScreen
        case .regionPicking:
            // Tear down the loading overlay; hand off to crop UI.
            isScreenshotPresented = false
            regionReferenceImage = img
            isRegionCropPresented = true
        }
    }

    func handleScreenshotError(requestID: String, message: String) {
        guard requestID == screenshotRequestID else {
            #if DEBUG
            print("DeckHandiOS: ⏭️ dropping stale screenshotError (\(requestID))")
            #endif
            return
        }
        screenshotTimeoutTask?.cancel()
        isRequestingScreenshot = false
        screenshotRequestID = nil
        isScreenshotPresented = false
        isRegionCropPresented = false
        screenshotIntent = .fullScreen
        screenshotErrorMessage = message
    }

    func handleWindowList(requestID: String, windows: [WindowInfo]) {
        // The window picker may have been dismissed before the
        // list arrived; we still keep the cached list so the
        // next open is instant.
        if windowListRequestID == requestID {
            windowListRequestID = nil
            isWindowListLoading = false
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            availableWindows = windows
        }
    }

    /// Shows a live-mirror failure in the shared error alert.
    func showMirrorError(_ message: String) {
        screenshotErrorIsMirror = true
        screenshotErrorMessage = message
    }

    func dismissError() {
        screenshotErrorMessage = nil
        screenshotErrorIsMirror = false
    }
}
