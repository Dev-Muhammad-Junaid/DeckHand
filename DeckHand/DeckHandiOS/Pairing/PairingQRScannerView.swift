//
//  PairingQRScannerView.swift
//  DeckHandiOS
//
//  Reads the Mac's pairing QR code (S4) with the camera: AVFoundation's
//  metadata output, QR only, public API. Hands back the first payload that
//  is a valid `PairingInvite`; anything else is ignored, so pointing the
//  camera at another QR code does nothing.
//
//  Needs `NSCameraUsageDescription` in Info.plist.
//

import AVFoundation
import SwiftUI
import UIKit

/// A sheet with the camera, a frame, and what to do if the camera is off.
struct PairingQRScannerSheet: View {
    let onInvite: (PairingInvite) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch access {
                case .authorized:
                    PairingQRScanner { invite in
                        onInvite(invite)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel("Camera, scanning for a pairing code")
                    .accessibilityHint("Point your camera at the QR code on your Mac")
                    .accessibilityIdentifier("ph.pairing.scanner")
                    DottedViewfinder()
                        .frame(width: 240, height: 240)
                        .accessibilityHidden(true)
                case .notDetermined:
                    DotWave(pitch: 6, label: "Waiting for the camera")
                default:
                    cameraOff
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: PixelHandTheme.Space.sm) {
                    Text("Point at the code on your Mac")
                        .phText(.display)
                        .foregroundStyle(.white)
                    Text("Menu bar › Pixel Hand › Pair a Device…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .padding(.horizontal, PixelHandTheme.Space.xl)
                .padding(.vertical, PixelHandTheme.Space.lg)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.45))
            }
            .navigationTitle("Scan pairing code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            guard access == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private var cameraOff: some View {
        VStack(spacing: PixelHandTheme.Space.lg) {
            PHGlyph(glyph: PixelGlyphs.capture, pitch: CGFloat(PixelPitch.emptyState), showsUnlit: true)
                .foregroundStyle(PixelHandTheme.Brand.phosphor)
                .pixelOnNavy()
            Text("Pixel Hand can’t use the camera.")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Allow Camera for Pixel Hand in Settings, or type the code instead.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.ph(.primary, size: .regular))
            .accessibilityIdentifier("ph.pairing.openSettings")
        }
        .padding(32)
    }
}

/// The camera preview that reports a pairing invite once.
/// The scanner's frame: 6 pt square dots along each corner (no solid
/// stroke), and a phosphor scanline sweeping down. Reduce Motion: the line
/// rests in the middle.
private struct DottedViewfinder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Canvas { context, size in
                let dot: CGFloat = 6, step: CGFloat = 9, arm = 6
                let maxX = size.width - dot, maxY = size.height - dot
                var path = Path()
                func add(_ x: CGFloat, _ y: CGFloat) {
                    path.addRoundedRect(in: CGRect(x: x, y: y, width: dot, height: dot), cornerSize: CGSize(width: 2, height: 2))
                }
                for i in 0..<arm {
                    let d = CGFloat(i) * step
                    add(d, 0); add(0, d)
                    add(maxX - d, 0); add(maxX, d)
                    add(d, maxY); add(0, maxY - d)
                    add(maxX - d, maxY); add(maxX, maxY - d)
                }
                context.fill(path, with: .color(PixelHandTheme.Brand.phosphor))
            }
            .shadow(color: PixelHandTheme.Brand.glow.opacity(0.8), radius: 4)

            if reduceMotion {
                scanline.offset(y: 120)
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (sin(t * .pi / 1.4) + 1) / 2
                    scanline.offset(y: 16 + CGFloat(phase) * 208)
                }
            }
        }
    }

    private var scanline: some View {
        Rectangle()
            .fill(PixelHandTheme.Brand.phosphor)
            .frame(height: 1.5)
            .shadow(color: PixelHandTheme.Brand.glow, radius: 6)
            .padding(.horizontal, 12)
    }
}

struct PairingQRScanner: UIViewControllerRepresentable {
    let onInvite: (PairingInvite) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onInvite = onInvite
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onInvite = onInvite
    }

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onInvite: ((PairingInvite) -> Void)?
        /// `AVCaptureSession` is used from its own queue, as Apple advises
        /// (start/stop block). The box carries it there.
        private final class SessionBox: @unchecked Sendable {
            let session = AVCaptureSession()
        }
        private let box = SessionBox()
        private var session: AVCaptureSession { box.session }
        private let sessionQueue = DispatchQueue(label: "com.widgetsflow.pixelhand.qr")
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didFinish = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            previewLayer = preview
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let box = self.box
            sessionQueue.async { if !box.session.isRunning { box.session.startRunning() } }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let box = self.box
            sessionQueue.async { if box.session.isRunning { box.session.stopRunning() } }
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            let payloads = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            MainActor.assumeIsolated {
                guard !didFinish else { return }
                for payload in payloads {
                    guard let invite = PairingInvite(payload: payload) else { continue }
                    didFinish = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onInvite?(invite)
                    return
                }
            }
        }
    }
}
