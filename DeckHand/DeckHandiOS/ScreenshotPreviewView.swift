//
//  ScreenshotPreviewView.swift
//  DeckHandiOS
//
//  The capture sheet (UX-009): one presentation from Control with three
//  steps inside it, never a sheet on a sheet:
//
//    preview   → the capture fitted into all the room between the header
//                and the dock (`CapturePreviewLayout`, OT-10), in a black
//                well under a scanline; pinch, double-tap to zoom on a
//                point or back out, pan while zoomed, swipe down to close;
//                dock anchored at the bottom: Save, Copy, Share, Annotate,
//                Read text.
//    annotate  → pen on the capture (`AnnotationView.swift`); Done bakes
//                the marks in at native resolution, Cancel and Clear ask
//                before throwing marks away.
//    readText  → Vision text (`OCRResultView.swift`), selectable; dock:
//                Copy, Share, back to the picture. "Recognize Text" from
//                the capture menu opens straight here.
//
//  The header is a close glyph and a dot-matrix status strip
//  (`REGION · 812X540 · MARKED`); everything sits on the navy stage.
//  Words come from Core `CaptureSheetChrome`.
//

import Photos
import SwiftUI
import UIKit

struct ScreenshotPreviewView: View {
    let image: UIImage
    var kind: CaptureKind = .fullScreen
    /// `.readText` when the capture menu's "Recognize Text" opened the sheet.
    var initialStep: CaptureStep = .preview
    let onDismiss: () -> Void

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: CaptureStep = .preview
    @State private var didApplyInitialStep = false
    /// The capture with marks baked in, once annotated; every action uses it.
    @State private var annotatedImage: UIImage?

    // Preview zoom.
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var dismissDrag: CGFloat = 0
    /// While two fingers pinch, the drag that comes with them doesn't pan.
    @State private var isPinching = false
    @State private var lastDragTranslation: CGSize = .zero
    /// The drag's translation when a pinch ended mid-drag.
    @State private var dragBase: CGSize = .zero
    @State private var revealed = false

    // Annotate.
    @State private var strokes: [AnnotationStroke] = []
    @State private var ink: CaptureSheetChrome.Ink = CaptureSheetChrome.defaultInk
    @State private var penWidth = CGFloat(CaptureSheetChrome.defaultPenWidth)
    @State private var confirmClear = false
    @State private var confirmDiscard = false

    // Read text.
    @State private var textState: TextReadState = .reading
    /// Which picture `textState` was read from, so annotating re-reads.
    @State private var textSource: ObjectIdentifier?

    // Save / share / toast.
    @State private var didAutoSave = false
    @State private var isSaving = false
    @State private var showShareSheet = false
    @State private var toast: (message: String, failed: Bool)?
    @State private var toastTask: Task<Void, Never>?

    private var current: UIImage { annotatedImage ?? image }

    var body: some View {
        CaptureStage {
            VStack(spacing: PixelHandTheme.Space.md) {
                header
                Group {
                    switch step {
                    case .preview: previewStage
                    case .annotate: annotateStage
                    case .readText: OCRResultView(state: textState, onRetry: { Task { await readText(force: true) } })
                    }
                }
                // Every step takes the room between the header and the dock;
                // the dock is anchored at the bottom (owner testing, build 26,
                // OT-10). The preview fits the picture into that room and
                // hugs it with its well, so there's no black band (VQ-051)
                // and no empty half screen under the dock either.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                dock
            }
            .overlay(alignment: .bottom) { toastView }
        }
        .offset(y: dismissDrag)
        .animation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion), value: step)
        .sheet(isPresented: $showShareSheet) {
            // The system share sheet is the one presentation over the
            // capture: it is Apple's, not another level of ours.
            ShareSheet(items: shareItems)
        }
        .confirmationDialog("Clear all marks?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear marks", role: .destructive) {
                withAnimation(.easeOut(duration: 0.15)) { strokes.removeAll() }
            }
        }
        .confirmationDialog("Discard your marks?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard marks", role: .destructive) { leaveAnnotate(keep: false) }
            Button("Keep annotating", role: .cancel) {}
        }
        .onAppear {
            revealed = true
            guard !didApplyInitialStep else { return }
            didApplyInitialStep = true
            step = initialStep
        }
        .task(id: step) {
            if step == .readText { await readText(force: false) }
        }
        .task {
            // Auto-save runs once per capture, on the image as it arrived.
            // Annotating afterwards is an explicit act, so it gets an
            // explicit Save rather than silently writing a second asset.
            guard settings.autoSaveToPhotos, !didAutoSave, initialStep == .preview else { return }
            didAutoSave = true
            await saveToPhotos()
        }
        .onDisappear { toastTask?.cancel() }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch step {
        case .preview:
            let size = CaptureGeometry.pixelSize(of: current)
            CaptureHeader(
                strip: CaptureSheetChrome.strip(kind: kind, pixelWidth: size.width, pixelHeight: size.height, annotated: annotatedImage != nil),
                closeLabel: "Close capture",
                onClose: onDismiss
            )
        case .annotate:
            CaptureHeader(
                strip: CaptureSheetChrome.annotateStrip(marks: strokes.count),
                closeLabel: "Cancel annotation",
                onClose: {
                    if strokes.isEmpty {
                        leaveAnnotate(keep: false)
                    } else {
                        confirmDiscard = true
                    }
                }
            ) {
                Button("Done") { leaveAnnotate(keep: true) }
                    .buttonStyle(.ph(.primary, size: .small))
                    .disabled(strokes.isEmpty)
            }
        case .readText:
            CaptureHeader(
                strip: textState.strip,
                style: textState == .reading ? .dim : .live,
                closeGlyph: initialStep == .readText ? PixelGlyphs.close : PixelGlyphs.spaceLeft,
                closeLabel: initialStep == .readText ? "Close" : "Back to the capture",
                onClose: {
                    if initialStep == .readText {
                        onDismiss()
                    } else {
                        step = .preview
                    }
                }
            )
        }
    }

    // MARK: Preview

    /// The picture fitted (aspect-fit, centred, whole points) into all the
    /// room the stage gives it, its black well hugging it
    /// (`CapturePreviewLayout.pictureFrame`). Gestures sit on the well,
    /// which doesn't move, so a double-tap lands in picture points.
    private var previewStage: some View {
        GeometryReader { proxy in
            let inset = CGFloat(CapturePreviewLayout.sideInset)
            let area = MirrorRect(x: Double(inset), y: 0, width: Double(max(0, proxy.size.width - 2 * inset)), height: Double(proxy.size.height))
            let frame = CGRect(CapturePreviewLayout.pictureFrame(
                imageWidth: Double(current.size.width),
                imageHeight: Double(current.size.height),
                in: area
            ))
            let size = frame.size
            ZStack {
                Image(uiImage: current)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(zoom)
                    .offset(pan)
                    .mirrorScanline(on: revealed)
                    .accessibilityLabel("Capture")
                    .accessibilityHint("Pinch or double-tap to zoom.")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityAction(named: CapturePreviewLayout.isZoomed(Double(zoom)) ? "Zoom out" : "Zoom in") {
                        doubleTap(at: CGPoint(x: size.width / 2, y: size.height / 2), size: size)
                    }
                    .accessibilityIdentifier("ph.capture.preview")
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                    .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline)
            )
            .contentShape(Rectangle())
            .gesture(zoomGesture(size: size).simultaneously(with: panGesture(size: size)))
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                doubleTap(at: location, size: size)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ph.capture.well")
            .position(x: frame.midX, y: frame.midY)
        }
    }

    /// Pinch between 1× and 6×, the pan scaling with it and kept inside
    /// the picture; under 1× it snaps back.
    private func zoomGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isPinching = true
                let next = CapturePreviewLayout.pinch(
                    startZoom: Double(lastZoom),
                    magnification: Double(value.magnification),
                    startPan: (Double(lastPan.width), Double(lastPan.height)),
                    width: Double(size.width),
                    height: Double(size.height)
                )
                zoom = CGFloat(next.zoom)
                pan = CGSize(width: next.pan.x, height: next.pan.y)
            }
            .onEnded { _ in
                isPinching = false
                lastZoom = zoom
                lastPan = pan
                // A drag still going on carries on from here, not from
                // where it started.
                dragBase = lastDragTranslation
            }
    }

    /// Zoomed: pans the picture, never past its edges. At 1×: a downward
    /// swipe closes the sheet.
    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                lastDragTranslation = value.translation
                guard !isPinching else { return }
                if CapturePreviewLayout.isZoomed(Double(zoom)) {
                    let clamped = CapturePreviewLayout.clampedPan(
                        x: Double(lastPan.width + value.translation.width - dragBase.width),
                        y: Double(lastPan.height + value.translation.height - dragBase.height),
                        zoom: Double(zoom),
                        width: Double(size.width),
                        height: Double(size.height)
                    )
                    pan = CGSize(width: clamped.x, height: clamped.y)
                } else {
                    dismissDrag = max(0, value.translation.height)
                }
            }
            .onEnded { value in
                defer {
                    dragBase = .zero
                    lastDragTranslation = .zero
                }
                if CapturePreviewLayout.isZoomed(Double(zoom)) {
                    lastPan = pan
                } else if !isPinching, value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                    onDismiss()
                } else {
                    withAnimation(.snappy(duration: 0.2)) { dismissDrag = 0 }
                }
            }
    }

    /// Double-tap: zoom in on the tapped point, or back out to 1×.
    private func doubleTap(at location: CGPoint, size: CGSize) {
        let next = CapturePreviewLayout.doubleTap(
            at: (Double(location.x), Double(location.y)),
            zoom: Double(zoom),
            width: Double(size.width),
            height: Double(size.height)
        )
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            zoom = CGFloat(next.zoom)
            pan = CGSize(width: next.pan.x, height: next.pan.y)
        }
        lastZoom = zoom
        lastPan = pan
    }

    private func resetZoom() {
        zoom = 1; lastZoom = 1; pan = .zero; lastPan = .zero
    }

    // MARK: Annotate

    private var annotateStage: some View {
        CapturePictureWell {
            AnnotationCanvas(image: current, strokes: $strokes, ink: ink, penWidth: penWidth)
        }
    }

    private func leaveAnnotate(keep: Bool) {
        if keep, !strokes.isEmpty {
            annotatedImage = AnnotationRenderer.render(current, strokes: strokes)
            resetZoom()
            showToast("Marks applied")
        }
        strokes.removeAll()
        step = .preview
    }

    // MARK: Dock

    @ViewBuilder
    private var dock: some View {
        switch step {
        case .preview:
            CaptureDock(maxWidth: CGFloat(CapturePreviewLayout.dockMaximumWidth)) {
                HStack(spacing: 0) {
                    CaptureActionButton(glyph: CaptureGlyphs.save, title: "Save", isBusy: isSaving) {
                        toastTask?.cancel()
                        Task { await saveToPhotos() }
                    }
                    CaptureActionButton(glyph: CaptureGlyphs.copy, title: "Copy") {
                        UIPasteboard.general.image = current
                        showToast("Copied")
                    }
                    CaptureActionButton(glyph: PixelGlyphs.share, title: "Share") { showShareSheet = true }
                    CaptureActionButton(glyph: CaptureGlyphs.annotate, title: "Annotate") {
                        resetZoom()
                        step = .annotate
                    }
                    CaptureActionButton(glyph: PixelGlyphs.readText, title: "Read text") { step = .readText }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ph.capture.dock")
            }
        case .annotate:
            CaptureDock {
                AnnotationToolbar(
                    ink: $ink,
                    penWidth: $penWidth,
                    canUndo: !strokes.isEmpty,
                    onUndo: { if !strokes.isEmpty { strokes.removeLast() } },
                    onClear: { confirmClear = true }
                )
            }
        case .readText:
            CaptureDock(maxWidth: CGFloat(CapturePreviewLayout.dockMaximumWidth)) {
                HStack(spacing: 0) {
                    CaptureActionButton(glyph: CaptureGlyphs.copy, title: "Copy all", isEnabled: textState.text != nil) {
                        UIPasteboard.general.string = textState.text
                        showToast("Text copied")
                    }
                    CaptureActionButton(glyph: PixelGlyphs.share, title: "Share", isEnabled: textState.text != nil) {
                        showShareSheet = true
                    }
                    if initialStep != .readText {
                        CaptureActionButton(glyph: PixelGlyphs.screen, title: "Picture") { step = .preview }
                    }
                }
            }
        }
    }

    private var shareItems: [Any] {
        if step == .readText, let text = textState.text { return [text] }
        return [current]
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            PHToast(message: toast.message, isFailure: toast.failed)
                .padding(.bottom, 132)
                .transition(.opacity) // Glyph rule: status rows fade, never slide.
                .allowsHitTesting(false)
        }
    }

    private func showToast(_ message: String, failed: Bool = false) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { toast = (message, failed) }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        }
    }

    // MARK: Read text

    @MainActor
    private func readText(force: Bool) async {
        let source = ObjectIdentifier(current)
        guard force || textSource != source else { return }
        textSource = source
        textState = .reading
        let result = await TextReader.read(current)
        guard textSource == source else { return }
        textState = result
    }

    // MARK: Save

    @MainActor
    private func saveToPhotos() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard !Task.isCancelled else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            showToast("Allow Photos access in Settings to save", failed: true)
            return
        }

        // Window captures arrive as PNGs with the macOS shadow halo as
        // transparent pixels; JPEG would flatten it to white. Keep JPEG
        // for opaque captures (full screen, region) so files stay compact.
        let picture = current
        let data = Self.imageHasAlpha(picture) ? picture.pngData() : picture.jpegData(compressionQuality: 0.92)
        guard let data else {
            showToast("Couldn’t encode the capture", failed: true)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges({ @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            })
            showToast("Saved to Photos")
        } catch {
            showToast("Save failed: \(error.localizedDescription)", failed: true)
        }
    }

    /// `true` when the underlying CGImage carries a real alpha channel.
    private static func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .premultipliedFirst, .premultipliedLast, .first, .last, .alphaOnly:
            return true
        @unknown default:
            return true
        }
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
