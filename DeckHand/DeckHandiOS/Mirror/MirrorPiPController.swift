//
//  MirrorPiPController.swift
//  DeckHandiOS
//
//  UX-041: Picture in Picture for the live mirror. Wraps
//  `AVPictureInPictureController` with a sample-buffer content source: its
//  own `AVSampleBufferDisplayLayer`, fed composited frames (pointer drawn
//  in) by `MirrorPiPCompositor`.
//
//  - Starts automatically when the app leaves while the mirror is open
//    (`canStartPictureInPictureAutomaticallyFromInline`, only when the
//    person turned it on and has Pro), or from the mirror's PiP button.
//    Never started in code otherwise.
//  - Live: `requiresLinearPlayback`, an infinite time range, no skipping.
//  - Play/pause = freeze: the session model holds the picture and asks the
//    Mac for keep-alive frames (`MirrorPiPState`).
//  - Its layer sits under the inline picture (`MirrorPiPLayerView`): PiP
//    needs the layer in a window to be possible, and the inline picture
//    covers it.
//
//  Delegate callbacks arrive on the main thread.
//

import AVFoundation
import AVKit
import SwiftUI
import UIKit

@MainActor
final class MirrorPiPController: NSObject {
    let layer = AVSampleBufferDisplayLayer()

    /// PiP appeared / went away.
    var onActiveChanged: ((Bool) -> Void)?
    /// PiP's play/pause button.
    var onPausedChanged: ((Bool) -> Void)?
    /// The PiP window's new width in points.
    var onWindowWidthChanged: ((Double) -> Void)?
    /// Whether PiP can be started now changed (the button's state).
    var onPossibleChanged: ((Bool) -> Void)?
    /// The person tapped PiP to return to the app.
    var onRestore: (() -> Void)?

    /// What the playback delegate reports; set by the session model.
    var isPaused = false

    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var wantsAutoStart = false
    private var showsPassthrough = false

    /// This device can show PiP at all.
    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    override init() {
        super.init()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
    }

    /// Makes the PiP controller once the layer is in a window.
    func layerDidMoveToWindow() {
        guard controller == nil, Self.isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = wantsAutoStart
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onPossibleChanged?(possible) }
            }
        }
        self.controller = controller
    }

    var isActive: Bool { controller?.isPictureInPictureActive ?? false }
    var isPossible: Bool { controller?.isPictureInPicturePossible ?? false }

    /// Whether leaving the app starts PiP.
    func setAutoStart(_ enabled: Bool) {
        wantsAutoStart = enabled
        controller?.canStartPictureInPictureAutomaticallyFromInline = enabled
    }

    /// The PiP button.
    func start() {
        guard let controller, controller.isPictureInPicturePossible, !controller.isPictureInPictureActive else { return }
        controller.startPictureInPicture()
    }

    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    /// The pause state changed from our side: PiP redraws its button.
    func playbackStateChanged() {
        controller?.invalidatePlaybackState()
    }

    // MARK: Frames

    /// A composited frame.
    func enqueue(_ sample: CMSampleBuffer) {
        if showsPassthrough {
            showsPassthrough = false
            layer.sampleBufferRenderer.flush()
        }
        enqueueOnRenderer(sample)
    }

    /// A compressed sample shown as it is (the compositor gave up).
    func enqueuePassthrough(_ sample: CMSampleBuffer) {
        if !showsPassthrough {
            showsPassthrough = true
            layer.sampleBufferRenderer.flush()
        }
        enqueueOnRenderer(sample)
    }

    /// Empties the layer (mirror stopped).
    func flush() {
        showsPassthrough = false
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    private func enqueueOnRenderer(_ sample: CMSampleBuffer) {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
        }
        renderer.enqueue(sample)
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension MirrorPiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            DeckHandLog.connection.info("PiP: started")
            onActiveChanged?(true)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            DeckHandLog.connection.info("PiP: stopped")
            onActiveChanged?(false)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let text = error.localizedDescription
        MainActor.assumeIsolated {
            DeckHandLog.connection.error("PiP: couldn't start: \(text, privacy: .public)")
            onActiveChanged?(false)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated {
            onRestore?()
        }
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension MirrorPiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated {
            onPausedChanged?(!playing)
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Live: no start, no end, no scrubber.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { isPaused }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        let width = Double(newRenderSize.width)
        MainActor.assumeIsolated {
            // The render size is in pixels.
            let scale = Double(UITraitCollection.current.displayScale)
            guard width > 0, scale > 0 else { return }
            onWindowWidthChanged?(width / scale)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        // Live: nothing to skip to.
        completionHandler()
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        // The Mac's sound (S17) keeps playing while PiP shows.
        false
    }
}

// MARK: - Host view

/// Puts PiP's layer in the window, under the inline picture (PiP is only
/// possible for a layer in a window). Doesn't take touches.
struct MirrorPiPLayerView: UIViewRepresentable {
    let controller: MirrorPiPController

    func makeUIView(context: Context) -> MirrorPiPHostView {
        let view = MirrorPiPHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .black
        view.controller = controller
        view.attach(controller.layer)
        return view
    }

    func updateUIView(_ view: MirrorPiPHostView, context: Context) {
        view.controller = controller
        view.attach(controller.layer)
    }
}

final class MirrorPiPHostView: UIView {
    weak var controller: MirrorPiPController?
    private weak var hostedLayer: CALayer?

    func attach(_ newLayer: CALayer) {
        guard hostedLayer !== newLayer || newLayer.superlayer !== layer else { return }
        newLayer.removeFromSuperlayer()
        layer.addSublayer(newLayer)
        hostedLayer = newLayer
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // Another host may have taken the layer while this one was away.
        if let hostedLayer, hostedLayer.superlayer !== layer {
            attach(hostedLayer)
        }
        controller?.layerDidMoveToWindow()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostedLayer?.frame = bounds
        CATransaction.commit()
    }
}
