//
//  ControlCaptureSheets.swift
//  DeckHandiOS
//
//  The covers, sheets and alert that show `CaptureCoordinator`'s state:
//  the capture preview (with its loading state), the error alert (shared
//  with the live mirror), the region cropper, the window picker and the
//  OCR result.
//

import SwiftUI

struct ControlCaptureSheets: ViewModifier {
    @Bindable var capture: CaptureCoordinator
    let runningBundleIDs: [String]
    @EnvironmentObject private var settings: DeckHandSettings

    func body(content: Content) -> some View {
        content
            // Screenshot sheet
            .fullScreenCover(isPresented: $capture.isScreenshotPresented) {
                ZStack {
                    if let img = capture.screenshotImage {
                        ScreenshotPreviewView(image: img) {
                            capture.isScreenshotPresented = false
                        }
                    } else {
                        // Loading state while waiting for Mac response
                        ZStack {
                            Color.black.ignoresSafeArea()
                            VStack(spacing: 18) {
                                DeckHandLoadingStateView(
                                    title: "Capturing screen…",
                                    verticalPadding: 0,
                                    titleColor: .white.opacity(0.88)
                                )
                                Button("Cancel") {
                                    capture.cancelPendingCapture()
                                }
                                .font(DeckHandTheme.TypeStyle.captionRounded)
                                .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                }
                // Release the captured image once the preview is fully gone.
                // A native-resolution capture of a 5K display decodes to
                // ~50 MB; holding it in state after dismissal kept that
                // memory resident until the *next* capture overwrote it.
                .onDisappear { capture.screenshotImage = nil }
            }
            .alert(capture.screenshotErrorIsMirror ? "Live Mirror Unavailable" : "Screenshot Failed", isPresented: Binding(
                get: { capture.screenshotErrorMessage != nil },
                set: { if !$0 { capture.dismissError() } }
            )) {
                Button("OK", role: .cancel) { capture.dismissError() }
            } message: {
                Text(capture.screenshotErrorMessage ?? "")
            }
            // Region picker — fronts after a regionPicking-intent capture lands.
            .fullScreenCover(isPresented: $capture.isRegionCropPresented) {
                if let reference = capture.regionReferenceImage {
                    RegionCropView(image: reference) { rect in
                        capture.handleRegionConfirm(rect, quality: settings.screenshotQuality)
                    }
                } else {
                    // Defensive: shouldn't happen because we only set the flag
                    // after the reference image is captured.
                    Color.black.ignoresSafeArea()
                        .onAppear { capture.isRegionCropPresented = false }
                }
            }
            // Window picker — independent of the capture state machine; the
            // user can refresh / cancel without disturbing an in-flight request.
            .sheet(isPresented: $capture.isWindowPickerPresented) {
                WindowPickerView(
                    windows: capture.availableWindows,
                    runningBundleIDs: runningBundleIDs,
                    isLoading: capture.isWindowListLoading,
                    onPick: { window in
                        // Capture it, or mirror it (S14, the mirror's "Window…").
                        capture.handleWindowPicked(window, quality: settings.screenshotQuality)
                    },
                    onRefresh: {
                        capture.refreshWindowList()
                    },
                    onCancel: { capture.isWindowPickerPresented = false },
                    title: capture.windowPickerPurpose == .mirror ? "Mirror Window" : "Capture Window"
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            // OCR result sheet — fronts after an ocr-intent capture lands.
            .sheet(isPresented: $capture.isOCRPresented) {
                if let img = capture.ocrImage {
                    OCRResultView(image: img) {
                        capture.isOCRPresented = false
                        capture.ocrImage = nil
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
    }
}
