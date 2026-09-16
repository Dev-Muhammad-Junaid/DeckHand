//
//  MirrorThumbnailView.swift
//  DeckHandiOS
//
//  Floating live-mirror thumbnail (WID-403). Renders the latest frame the
//  Mac streamed, draggable anywhere over the control surface, pinchable
//  from a corner tile up to nearly the whole screen, with a close
//  affordance. Edge chevrons switch Mission Control Spaces; the current
//  frame slides off in the direction of travel while the live stream
//  comes in from the other side.
//
//  The view is intentionally dumb: frame decode, sequencing, and the
//  start/stop protocol all live in `ControlView`, which owns the single
//  host-message loop. This just shows whatever `image` it's handed, and
//  reports the stream width its current size warrants.
//

import SwiftUI

struct MirrorThumbnailView: View {
    let image: UIImage?
    /// Size of the region the mirror floats in. Zoom limits and drag bounds
    /// are derived from it, so the mirror can't be pinched larger than the
    /// screen or dragged out of reach on any device.
    let containerSize: CGSize
    let onClose: () -> Void
    var onSwitchSpace: (SpaceDirection) -> Void = { _ in }
    /// Fired with the pixel width the host should stream, whenever the
    /// mirror settles into a different resolution tier.
    var onStreamWidthChanged: (Int) -> Void = { _ in }
    /// Size and position to open at. Values are stored unclamped and bounded
    /// at render time, because the container is not measured yet on appear.
    var initialLayout: MirrorLayout?
    /// Fired whenever a drag or pinch settles, so the layout can be persisted.
    var onLayoutChanged: (MirrorLayout) -> Void = { _ in }

    /// Persisted drag offset (committed at drag end) + live in-drag delta.
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero

    /// Persisted width (committed at pinch end) + live in-pinch scale.
    @State private var committedWidth: CGFloat = Layout.compactWidth
    @GestureState private var pinchScale: CGFloat = 1

    /// Width a tap restores to after minimising. Tracks the last size the
    /// user pinched to, so once they've chosen a working size, tap becomes
    /// minimise/restore rather than a fixed two-step toggle.
    @State private var restoreWidth: CGFloat = Layout.expandedWidth

    /// Snapshot of the frame that is sliding out during a Space switch.
    @State private var outgoingSnapshot: UIImage?
    /// `.next` slides the current desktop left; `.previous` slides it right.
    @State private var spaceDirection: SpaceDirection?
    /// 0 at tap, 1 when the slide has settled.
    @State private var spaceProgress: CGFloat = 0

    private enum Layout {
        static let compactWidth: CGFloat = 200
        /// Where a tap expands to before the user has pinched to anything.
        static let expandedWidth: CGFloat = 340
        /// Fraction of the container the mirror may fill at full zoom.
        static let maxFill: CGFloat = 0.94
        static let edgeMargin: CGFloat = 8
        static let trailingInset: CGFloat = 16
        /// Clears the gesture button bar along the bottom of the control surface.
        static let bottomInset: CGFloat = 96
        static let cornerRadius: CGFloat = 10
    }

    // MARK: - Geometry

    /// Aspect (height / width) of the streamed frame. Falls back to 16:10
    /// until the first frame lands, matching the placeholder.
    private var frameAspect: CGFloat {
        guard let image, image.size.width > 0 else { return 10.0 / 16.0 }
        return image.size.height / image.size.width
    }

    /// Largest the mirror may be pinched. Bounded on both axes so a wide
    /// frame can't overflow a short container, or vice versa.
    private var maxWidth: CGFloat {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return Layout.expandedWidth
        }
        let byWidth = containerSize.width * Layout.maxFill
        let byHeight = containerSize.height * Layout.maxFill / frameAspect
        return max(Layout.compactWidth, min(byWidth, byHeight))
    }

    private var minWidth: CGFloat { min(Layout.compactWidth, maxWidth) }

    /// On-screen width right now, including any in-flight pinch.
    private var width: CGFloat { clampWidth(committedWidth * pinchScale) }

    private func clampWidth(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, minWidth), maxWidth)
    }

    /// Keeps the mirror on screen regardless of how large it has been
    /// pinched, or how far it was dragged back when it was smaller. Home is
    /// the bottom-trailing corner, so offsets are measured from there.
    private func clampOffset(_ proposed: CGSize, width: CGFloat) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else { return proposed }
        let height = width * frameAspect
        let homeX = containerSize.width - Layout.trailingInset - width
        let homeY = containerSize.height - Layout.bottomInset - height

        let lowX = Layout.edgeMargin - homeX
        let highX = containerSize.width - Layout.edgeMargin - width - homeX
        let lowY = Layout.edgeMargin - homeY
        let highY = containerSize.height - Layout.edgeMargin - height - homeY

        return CGSize(
            width: min(max(proposed.width, min(lowX, highX)), max(lowX, highX)),
            height: min(max(proposed.height, min(lowY, highY)), max(lowY, highY))
        )
    }

    private var liveOffset: CGSize {
        clampOffset(
            CGSize(
                width: committedOffset.width + dragDelta.width,
                height: committedOffset.height + dragDelta.height
            ),
            width: width
        )
    }

    // MARK: - Stream resolution

    /// Stream width for a given on-screen size. Tiered rather than
    /// continuous because changing resolution restarts the stream, and that
    /// hiccup shouldn't fire on every pinch frame. The top tier is the
    /// host's ceiling.
    static func streamWidth(for width: CGFloat) -> Int {
        switch width {
        case ..<260: return 640
        case ..<480: return 1024
        case ..<760: return 1440
        default: return 1920
        }
    }

    private func commitWidth(_ proposed: CGFloat) {
        let before = Self.streamWidth(for: committedWidth)
        committedWidth = clampWidth(proposed)
        let after = Self.streamWidth(for: committedWidth)
        if after != before { onStreamWidthChanged(after) }
    }

    private func toggleSize() {
        withAnimation(.snappy(duration: 0.2)) {
            if committedWidth > minWidth * 1.05 {
                restoreWidth = committedWidth
                commitWidth(minWidth)
            } else {
                commitWidth(restoreWidth)
            }
        }
        publishLayout()
    }

    private func publishLayout() {
        onLayoutChanged(
            MirrorLayout(
                width: Double(committedWidth),
                offsetX: Double(committedOffset.width),
                offsetY: Double(committedOffset.height)
            )
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            frameStack
                .onTapGesture { toggleSize() }

            HStack {
                spaceChevron(direction: .previous, symbol: "chevron.left", label: "Previous desktop")
                Spacer(minLength: 0)
                spaceChevron(direction: .next, symbol: "chevron.right", label: "Next desktop")
            }
            .padding(.horizontal, 8)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding(6)
            .accessibilityLabel("Close live mirror")
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(.trailing, Layout.trailingInset)
        .padding(.bottom, Layout.bottomInset)
        .offset(x: liveOffset.width, y: liveOffset.height)
        .gesture(
            DragGesture()
                .updating($dragDelta) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    committedOffset = clampOffset(
                        CGSize(
                            width: committedOffset.width + value.translation.width,
                            height: committedOffset.height + value.translation.height
                        ),
                        width: width
                    )
                    publishLayout()
                }
                .simultaneously(
                    with: MagnifyGesture()
                        .updating($pinchScale) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            commitWidth(committedWidth * value.magnification)
                            restoreWidth = max(committedWidth, Layout.compactWidth)
                            // A pinch that shrank the mirror can leave it
                            // parked outside the container it was dragged to.
                            committedOffset = clampOffset(committedOffset, width: committedWidth)
                            publishLayout()
                        }
                )
        )
        .onAppear {
            guard let initialLayout else { return }
            committedWidth = CGFloat(initialLayout.width)
            committedOffset = CGSize(
                width: CGFloat(initialLayout.offsetX),
                height: CGFloat(initialLayout.offsetY)
            )
            restoreWidth = max(committedWidth, Layout.compactWidth)
        }
        .animation(.snappy(duration: 0.2), value: committedWidth)
        .accessibilityLabel("Live mirror of the Mac screen")
        .accessibilityHint("Drag to move. Pinch to resize. Tap to shrink or restore. Chevrons switch desktops.")
    }

    // MARK: - Frame + Space transition

    /// Live frame, with the outgoing snapshot sliding off when a Space
    /// switch is in flight. Direction matches macOS: next desktop comes
    /// from the right.
    private var frameStack: some View {
        ZStack {
            liveFrame
                .offset(x: incomingOffset)
                .opacity(incomingOpacity)

            if let outgoingSnapshot {
                Image(uiImage: outgoingSnapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .offset(x: outgoingOffset)
                    .opacity(1 - spaceProgress * 0.35)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var liveFrame: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                Rectangle().fill(.black.opacity(0.85))
                ProgressView()
                    .tint(.white)
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
        }
    }

    /// Next = current Space exits left. Previous = exits right.
    private var travelSign: CGFloat {
        spaceDirection == .previous ? 1 : -1
    }

    private var outgoingOffset: CGFloat {
        travelSign * width * spaceProgress
    }

    private var incomingOffset: CGFloat {
        guard spaceProgress > 0, spaceProgress < 1 else { return 0 }
        return -travelSign * width * (1 - spaceProgress) * 0.45
    }

    private var incomingOpacity: Double {
        guard spaceProgress > 0 else { return 1 }
        return 0.55 + 0.45 * Double(spaceProgress)
    }

    private func performSpaceSwitch(_ direction: SpaceDirection) {
        GestureHaptic.medium.trigger()
        outgoingSnapshot = image
        spaceDirection = direction
        spaceProgress = 0
        onSwitchSpace(direction)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            spaceProgress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            outgoingSnapshot = nil
            spaceDirection = nil
            spaceProgress = 0
        }
    }

    private func spaceChevron(
        direction: SpaceDirection,
        symbol: String,
        label: String
    ) -> some View {
        Button {
            performSpaceSwitch(direction)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(label)
    }
}

private struct ScalePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
