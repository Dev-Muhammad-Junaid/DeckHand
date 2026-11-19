//
//  MirrorVideoRenderer.swift
//  DeckHandiOS
//
//  Shows the HEVC mirror (S5): an `AVSampleBufferDisplayLayer` the session
//  model feeds on the main actor, and the `UIViewRepresentable` that puts
//  it where `MirrorThumbnailView` used to draw the JPEG image. The Mac's
//  pointer stays a SwiftUI overlay on top (`MirrorCursorLayer`).
//
//  Hardware decode happens inside the layer. A decode failure (the
//  renderer's "failed to decode" notification, or a `.failed` status) is
//  reported to the session model, whose `MirrorVideoWatchdog` asks for a
//  key frame and, if that doesn't help, falls back to JPEG.
//

import AVFoundation
import SwiftUI
import UIKit
import VideoToolbox

@MainActor
final class MirrorVideoRenderer {
    let layer = AVSampleBufferDisplayLayer()
    /// The layer couldn't decode a frame.
    var onDecodeFailure: (() -> Void)?
    private var observer: NSObjectProtocol?

    /// Whether this device can decode HEVC in hardware.
    static var hevcDecodeAvailable: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    }

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        observer = NotificationCenter.default.addObserver(
            forName: AVSampleBufferVideoRenderer.didFailToDecodeNotification,
            object: layer.sampleBufferRenderer,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDecodeFailure?()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Queues a frame for decode and display. Returns `false` when the
    /// renderer has failed (it is flushed, ready for a key frame).
    func enqueue(_ sample: CMSampleBuffer) -> Bool {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
            if renderer.status == .failed { return false }
        }
        renderer.enqueue(sample)
        return renderer.status != .failed
    }

    /// Empties the layer (mirror stopped, or back to JPEG).
    func flush() {
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }
}

/// Hosts the renderer's layer in SwiftUI. Doesn't take touches: the
/// mirror's gestures belong to the SwiftUI view around it.
struct MirrorVideoLayerView: UIViewRepresentable {
    let renderer: MirrorVideoRenderer

    func makeUIView(context: Context) -> MirrorVideoHostView {
        let view = MirrorVideoHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .black
        view.attach(renderer.layer)
        return view
    }

    func updateUIView(_ view: MirrorVideoHostView, context: Context) {
        view.attach(renderer.layer)
    }
}

final class MirrorVideoHostView: UIView {
    private weak var videoLayer: CALayer?

    func attach(_ newLayer: CALayer) {
        guard videoLayer !== newLayer else { return }
        videoLayer?.removeFromSuperlayer()
        layer.addSublayer(newLayer)
        videoLayer = newLayer
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        CATransaction.commit()
    }
}
