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
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .accessibilityHidden(true)
                case .notDetermined:
                    ProgressView().tint(.white)
                default:
                    cameraOff
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("On your Mac, open Pixel Hand in the menu bar and choose “Pair a Device…”.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Scan Pairing Code")
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
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.6))
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
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

/// The camera preview that reports a pairing invite once.
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
