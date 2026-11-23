//
//  ControlCaptureSheets.swift
//  DeckHandiOS
//
//  The presentations that show `CaptureCoordinator`'s state (UX-009):
//
//  - the capture sheet (full-screen cover): a dot-wave `CAPTURING` state
//    while the Mac works, then `ScreenshotPreviewView` with its preview,
//    annotate and read-text steps inside it ("Recognize Text" opens at read
//    text). One modal level from Control.
//  - the region picker (full-screen cover, so its drags never fight a
//    sheet's swipe);
//  - the window picker (sheet, medium and large);
//  - the error alert, shared with the live mirror. The locked-Mac refusal
//    gets its own title and tells the user to unlock (`CaptureSheetChrome`).
//

import SwiftUI

struct ControlCaptureSheets: ViewModifier {
    @Bindable var capture: CaptureCoordinator
    let runningBundleIDs: [String]
    @EnvironmentObject private var settings: DeckHandSettings

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $capture.isScreenshotPresented) {
                ZStack {
                    if let img = capture.screenshotImage {
                        ScreenshotPreviewView(
                            image: img,
                            kind: capture.capturedKind,
                            initialStep: capture.captureInitialStep
                        ) {
                            capture.isScreenshotPresented = false
                        }
                        .transition(.opacity)
                    } else {
                        CaptureLoadingView(
                            title: capture.screenshotIntent == .ocr ? "READING SCREEN" : "CAPTURING",
                            onCancel: { capture.cancelPendingCapture() }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: capture.screenshotImage == nil)
                // Release the captured image once the sheet is fully gone.
                // A native-resolution capture of a 5K display decodes to
                // ~50 MB; holding it after dismissal kept that memory
                // resident until the *next* capture overwrote it.
                .onDisappear {
                    capture.screenshotImage = nil
                    capture.captureInitialStep = .preview
                }
            }
            .alert(alertTitle, isPresented: Binding(
                get: { capture.screenshotErrorMessage != nil },
                set: { if !$0 { capture.dismissError() } }
            )) {
                Button("OK", role: .cancel) { capture.dismissError() }
            } message: {
                Text(CaptureSheetChrome.errorMessage(
                    message: capture.screenshotErrorMessage ?? "",
                    isMirror: capture.screenshotErrorIsMirror
                ))
            }
            // Region picker: fronts after a regionPicking-intent capture lands.
            .fullScreenCover(isPresented: $capture.isRegionCropPresented) {
                if let reference = capture.regionReferenceImage {
                    RegionCropView(image: reference) { rect in
                        capture.handleRegionConfirm(rect, quality: settings.screenshotQuality)
                    }
                } else {
                    // Defensive: the flag is only set once the reference
                    // image is in.
                    PixelHandTheme.Brand.screen.ignoresSafeArea()
                        .onAppear { capture.isRegionCropPresented = false }
                }
            }
            // Window picker: independent of the capture state machine; the
            // user can refresh or cancel without disturbing a request.
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
                    purpose: capture.windowPickerPurpose
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(PixelHandTheme.Radius.sheet)
            }
    }

    private var alertTitle: String {
        CaptureSheetChrome.errorTitle(
            message: capture.screenshotErrorMessage ?? "",
            isMirror: capture.screenshotErrorIsMirror
        )
    }
}

/// While the Mac takes the capture: the dot wave over a dot-matrix word on
/// the navy stage, and Cancel.
struct CaptureLoadingView: View {
    let title: String
    let onCancel: () -> Void

    var body: some View {
        CaptureStage {
            VStack(spacing: PixelHandTheme.Space.xl) {
                Spacer()
                PHGlyph(glyph: PixelGlyphs.capture, pitch: PixelPitch.emptyState, showsUnlit: true)
                    .foregroundStyle(PixelHandTheme.Brand.phosphor)
                    .accessibilityHidden(true)
                VStack(spacing: PixelHandTheme.Space.md) {
                    DotWave(label: title.capitalized)
                    DotMatrixText(title, pitch: 1.8, label: title.capitalized)
                        .foregroundStyle(PixelHandTheme.Brand.phosphor)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.ph(.secondary, size: .regular))
                    .padding(.bottom, PixelHandTheme.Space.xl)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
