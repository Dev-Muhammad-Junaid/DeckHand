//
//  MirrorPicturePointer.swift
//  DeckHandiOS – Mirror
//
//  OR-16, pointer control on the mirror picture. When the toolbar toggle is
//  on (screen-only arrangement), this layer lies over the picture and works
//  like the Pointer surface's pad, trackpad style: a finger anywhere moves
//  the Mac's pointer relative to where it is (the Pointer surface's
//  sensitivity, divided by the zoom: `PicturePointerMapping`), a tap
//  clicks, a two-finger tap right-clicks, two fingers scroll, rest until
//  the haptic then move to drag, three fingers for Mission Control and
//  Spaces. It is the same `TrackpadInputLayer` and `MultiTouchTrackpad`
//  as UX-004, with two-finger arbitration turned on (`TwoFingerArbiter`):
//  a pinch zooms the picture, and sliding the pinch pans it.
//
//  Feedback: a faint dotted ring under each finger (pixel identity §5's
//  focus-ring dots, `glow`, low opacity), so the hand on the glass reads as
//  a trackpad touch, not a tap on what's under it. Reduce Motion: the rings
//  appear and go without a fade. The Mac's pointer itself is drawn by the
//  picture (`MirrorCursorLayer`), through the same zoom and pan.
//

import SwiftUI

struct MirrorPicturePointerLayer: View {
    let sender: TrackpadSender
    let macName: String
    /// The picture's zoom, for the pointer's speed (`PicturePointerMapping`).
    let zoom: PictureZoom
    let onZoom: (_ scale: CGFloat, _ anchor: CGPoint, _ pan: CGSize) -> Void
    var onZoomEnded: () -> Void = { }

    @State private var dots = DotFieldModel()
    @State private var gestureMap = GestureMap()

    var body: some View {
        ZStack {
            input
            MirrorFingerRings(dots: dots)
        }
    }

    private var input: some View {
        TrackpadInputLayer(
            sender: sender,
            dots: dots,
            gestureMap: $gestureMap,
            drawsDotField: false,
            sensitivityScale: Float(PicturePointerMapping.sensitivity(1, zoom: zoom)),
            picture: PictureGestureHandlers(onZoom: onZoom, onZoomEnded: onZoomEnded)
        )
        // A direct-touch area for VoiceOver, with the clicks as actions,
        // as on the Pointer surface's pad.
        .accessibilityElement()
        .accessibilityLabel("Trackpad on the screen of \(macName)")
        .accessibilityHint("Touch directly to move the pointer. Pinch to zoom the picture. Actions has clicks.")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityIdentifier("ph.mirror.pointerSurface")
        .accessibilityAction(named: "Click") { click(.left) }
        .accessibilityAction(named: "Double-click") {
            gestureMap.forget()
            Task { await sender.sendDoubleClick(.left) }
        }
        .accessibilityAction(named: "Right-click") { click(.right) }
    }

    private func click(_ button: MouseButton) {
        gestureMap.forget()
        Task { await sender.sendClick(button) }
    }
}

/// A faint dotted ring under each finger on the picture.
private struct MirrorFingerRings: View {
    let dots: DotFieldModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let diameter: CGFloat = 44

    var body: some View {
        let touches = dots.touches
        ZStack(alignment: .topLeading) {
            ForEach(touches.indices, id: \.self) { index in
                Circle()
                    .stroke(
                        PixelHandTheme.Brand.glow.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.01, 4])
                    )
                    .frame(width: Self.diameter, height: Self.diameter)
                    .shadow(color: PixelHandTheme.Brand.glow.opacity(0.3), radius: 6)
                    .position(touches[index])
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: touches.count)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Hands each Mac pointer update to the pane while the zoomed picture
/// follows it. A view of its own so only it reads the 60 Hz cursor state.
struct MirrorCursorFollower: View {
    let session: ControlSessionModel
    let onMove: (MirrorCursorState) -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.mirrorCursor) { _, state in
                if let state { onMove(state) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Feeds the sender's picture guard (VQ-095): the mirrored display's size
/// and the Mac's cursor stream, so a flick on the picture can't throw the
/// pointer off the mirrored display. Clears the guard when the picture
/// stops driving the pointer. Its own view so only it reads the 60 Hz
/// cursor state.
struct MirrorPicturePointerGuardFeed: View {
    let session: ControlSessionModel
    let sender: TrackpadSender

    var body: some View {
        let size = session.mirroredDisplayPointSize
        Color.clear
            .onAppear { setDisplay(size) }
            .onChange(of: size?.width) { _, _ in setDisplay(session.mirroredDisplayPointSize) }
            .onChange(of: size?.height) { _, _ in setDisplay(session.mirroredDisplayPointSize) }
            .onChange(of: session.mirrorCursor, initial: true) { _, state in
                guard let state else { return }
                Task {
                    await sender.syncPicturePointer(x: state.x, y: state.y, isOnMirroredDisplay: state.isOnMirroredDisplay)
                }
            }
            .onDisappear {
                Task { await sender.stopPicturePointer() }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func setDisplay(_ size: (width: Double, height: Double)?) {
        // With no display size (a window, or not known yet) the guard still
        // caps the gain; it only clamps once it knows the display.
        let width = size?.width ?? 0
        let height = size?.height ?? 0
        Task { await sender.startPicturePointer(displayWidth: width, height: height) }
    }
}
