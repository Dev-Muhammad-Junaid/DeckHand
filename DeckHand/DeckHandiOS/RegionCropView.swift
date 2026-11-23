//
//  RegionCropView.swift
//  DeckHandiOS
//
//  Two-step region capture flow:
//
//   1. iPad already has the most recent full-screen capture (the "preview"
//      it just showed in `ScreenshotPreviewView`). User drags out a
//      rectangle on top of that preview, then refines it freely:
//         • Drag inside the rect to move it.
//         • Drag any of 8 handles (4 corners + 4 edge midpoints) to resize.
//         • Drag outside the rect to start a fresh selection.
//   2. On confirm, we ship the *normalized* rect (0…1, origin top-left)
//      back to the Mac, which performs a fresh capture and crops on its
//      side — much sharper than re-scaling the iPad-side JPEG, since the
//      Mac still has access to the native pixel grid.
//
//  Visual (UX-009): the capture in a black well on the navy stage, the
//  selection as a phosphor rim with a cyan glow and pixel-square handles,
//  everything outside dimmed. The header strip reads the selection's size
//  in the capture's pixels (`REGION · 812X540`); Reset is always there.
//

import SwiftUI
import UIKit

struct RegionCropView: View {
    /// The full-screen reference image to crop against.
    let image: UIImage
    /// Called with a normalized `CGRect` (0…1, origin top-left). `nil` means
    /// the user cancelled.
    let onConfirm: (CGRect?) -> Void

    /// Current rectangle, in the picture well's coordinates. `nil` means
    /// "no selection yet": the next drag lays one down.
    @State private var selection: CGRect?
    /// What kind of drag we're currently servicing. Decided at the *first*
    /// onChanged tick of a gesture and stays fixed until onEnded.
    @State private var dragKind: DragKind = .none
    /// Snapshot of `selection` at gesture start (for moves and resizes
    /// where we need to know the original frame the drag is editing).
    @State private var dragStartSelection: CGRect?
    @State private var dragStartLocation: CGPoint?
    /// Where the picture is drawn inside the well (aspect fit).
    @State private var imageFrame: CGRect = .zero

    /// Minimum drag length before we treat a fresh-draw gesture as a real
    /// rectangle. Prevents accidental taps from queuing degenerate crops.
    private let minimumDragLength: CGFloat = 24
    private let handleVisualSize: CGFloat = 10
    /// Inflated touch target for handles: 44 pt around a 10 pt square.
    private let handleHitInset: CGFloat = -22
    /// Minimum size the user can shrink the rect to during a resize, so
    /// they can't accidentally squish it into a degenerate strip and have
    /// to start over.
    private let minimumRectSide: CGFloat = 32

    var body: some View {
        CaptureStage {
            VStack(spacing: PixelHandTheme.Space.md) {
                CaptureHeader(
                    strip: strip,
                    style: canConfirm ? .live : .dim,
                    closeLabel: "Cancel region",
                    onClose: { onConfirm(nil) }
                ) {
                    // Always enabled: with no selection it simply clears
                    // nothing (UX-009: region reset always enabled).
                    CaptureIconButton(glyph: CaptureGlyphs.reset, label: "Reset selection") {
                        withAnimation(.easeOut(duration: 0.15)) { selection = nil }
                    }
                }

                CapturePictureWell {
                    GeometryReader { geo in
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .accessibilityLabel("The Mac's screen")

                            if let rect = selection {
                                DimOutside(selection: rect)

                                Rectangle()
                                    .strokeBorder(PixelHandTheme.Brand.phosphor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .shadow(color: PixelHandTheme.Brand.glow.opacity(0.8), radius: 3)
                                    .allowsHitTesting(false)

                                ForEach(Handle.allCases, id: \.self) { handle in
                                    HandleSquare(size: handleVisualSize)
                                        .position(handle.position(in: rect))
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    handleDragChange(value)
                                }
                                .onEnded { _ in
                                    dragKind = .none
                                    dragStartSelection = nil
                                    dragStartLocation = nil
                                }
                        )
                        .onAppear { imageFrame = CaptureGeometry.fitted(image, in: geo.size) }
                        .onChange(of: geo.size) { _, size in
                            // A new fit invalidates an on-screen selection.
                            imageFrame = CaptureGeometry.fitted(image, in: size)
                            selection = nil
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityHint("Drag to mark a region. Drag inside it to move, corners and edges to resize.")

                Text(headlineText)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, PixelHandTheme.Space.lg)

                Button {
                    GestureHaptic.medium.trigger()
                    guard let normalized = normalizedSelection() else { return }
                    onConfirm(normalized)
                } label: {
                    Label {
                        Text("Capture Region")
                    } icon: {
                        PHGlyph(glyph: PixelGlyphs.region, pitch: 2)
                    }
                }
                .buttonStyle(.ph(.primary, size: .large, fullWidth: true))
                .disabled(!canConfirm)
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .padding(.bottom, PixelHandTheme.Space.sm)
            }
        }
    }

    private var strip: CaptureStrip {
        if let selection,
           let size = CaptureGeometry.selectionPixels(
               MirrorRect(selection),
               fitted: MirrorRect(imageFrame),
               imageWidth: Double(image.size.width * image.scale),
               imageHeight: Double(image.size.height * image.scale)
           ) {
            return CaptureStrip(items: ["REGION", size], spoken: "Region, \(size.replacingOccurrences(of: "X", with: " by ")) pixels")
        }
        return CaptureStrip(items: ["REGION", "DRAG TO MARK"], spoken: "Region, nothing marked yet")
    }

    private var headlineText: String {
        if selection == nil {
            return "Drag across the screen to mark a region."
        }
        if !canConfirm {
            return "Make the region a little bigger."
        }
        return "Drag inside to move it, corners and edges to resize."
    }

    // MARK: - Drag dispatch

    private func handleDragChange(_ value: DragGesture.Value) {
        // First tick of a gesture decides what kind it is and stashes the
        // original rect so we can compute deltas without drift.
        if dragKind == .none {
            dragStartLocation = value.startLocation
            dragStartSelection = selection
            dragKind = classifyDrag(start: clampToImage(value.startLocation),
                                    rect: selection)
        }

        let current = clampToImage(value.location)
        switch dragKind {
        case .none:
            break

        case .drawing:
            guard let start = dragStartLocation else { return }
            let clampedStart = clampToImage(start)
            selection = CGRect(
                x: min(clampedStart.x, current.x),
                y: min(clampedStart.y, current.y),
                width: abs(current.x - clampedStart.x),
                height: abs(current.y - clampedStart.y)
            )

        case .moving:
            guard let original = dragStartSelection,
                  let start = dragStartLocation else { return }
            let dx = current.x - start.x
            let dy = current.y - start.y
            var moved = original.offsetBy(dx: dx, dy: dy)
            // Clamp the rect inside the image bounds, preserving size.
            if moved.minX < imageFrame.minX { moved.origin.x = imageFrame.minX }
            if moved.minY < imageFrame.minY { moved.origin.y = imageFrame.minY }
            if moved.maxX > imageFrame.maxX {
                moved.origin.x = imageFrame.maxX - moved.width
            }
            if moved.maxY > imageFrame.maxY {
                moved.origin.y = imageFrame.maxY - moved.height
            }
            selection = moved

        case let .resizing(handle):
            guard let original = dragStartSelection else { return }
            selection = resize(original, with: handle, toward: current)
        }
    }

    private func classifyDrag(start: CGPoint, rect: CGRect?) -> DragKind {
        guard let rect else { return .drawing }

        // Handle hits first (with the inflated touch target so corners
        // are easy to grab).
        for handle in Handle.allCases {
            let handleRect = CGRect(origin: handle.position(in: rect), size: .zero)
                .insetBy(dx: handleHitInset, dy: handleHitInset)
            if handleRect.contains(start) {
                return .resizing(handle)
            }
        }

        // Inside the existing rect (but missing a handle) → move.
        if rect.contains(start) {
            return .moving
        }

        // Otherwise the user has tapped outside their previous rect, so
        // re-use the existing "fresh draw" path. Wipe the old selection
        // so the geometry math during this drag matches the drawing case.
        selection = nil
        return .drawing
    }

    private func resize(_ original: CGRect, with handle: Handle, toward point: CGPoint) -> CGRect {
        // Each handle pins the *opposite* corner / edge — mirroring how
        // macOS's window resize works. Corner handles drag both axes;
        // midpoints constrain to one axis.
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY

        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minimumRectSide)
            minY = min(point.y, maxY - minimumRectSide)
        case .topRight:
            maxX = max(point.x, minX + minimumRectSide)
            minY = min(point.y, maxY - minimumRectSide)
        case .bottomLeft:
            minX = min(point.x, maxX - minimumRectSide)
            maxY = max(point.y, minY + minimumRectSide)
        case .bottomRight:
            maxX = max(point.x, minX + minimumRectSide)
            maxY = max(point.y, minY + minimumRectSide)
        case .top:
            minY = min(point.y, maxY - minimumRectSide)
        case .bottom:
            maxY = max(point.y, minY + minimumRectSide)
        case .left:
            minX = min(point.x, maxX - minimumRectSide)
        case .right:
            maxX = max(point.x, minX + minimumRectSide)
        }

        // Clamp to image bounds.
        minX = max(minX, imageFrame.minX)
        minY = max(minY, imageFrame.minY)
        maxX = min(maxX, imageFrame.maxX)
        maxY = min(maxY, imageFrame.maxY)

        return CGRect(x: minX, y: minY,
                      width: max(0, maxX - minX),
                      height: max(0, maxY - minY))
    }

    // MARK: - Geometry helpers

    private func clampToImage(_ point: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return point }
        return CGPoint(
            x: min(max(point.x, imageFrame.minX), imageFrame.maxX),
            y: min(max(point.y, imageFrame.minY), imageFrame.maxY)
        )
    }

    /// Final 0…1 normalized rect in image space, ready to ship to the Mac.
    /// `nil` if the rect is too small or doesn't exist yet.
    private func normalizedSelection() -> CGRect? {
        guard let selection else { return nil }
        return CaptureGeometry.normalizedSelection(
            MirrorRect(selection),
            fitted: MirrorRect(imageFrame),
            minimumSide: Double(minimumDragLength)
        ).map { CGRect($0) }
    }

    private var canConfirm: Bool {
        normalizedSelection() != nil
    }
}

// MARK: - Drag classification

private enum DragKind: Equatable {
    case none
    /// Fresh rect being drawn.
    case drawing
    /// Existing rect being translated.
    case moving
    /// Existing rect being resized via a particular handle.
    case resizing(Handle)
}

private enum Handle: CaseIterable, Hashable {
    case topLeft, top, topRight
    case left,           right
    case bottomLeft, bottom, bottomRight

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .top:         return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

// MARK: - Subviews

/// A pixel-square handle: phosphor with a navy core, glowing, readable on
/// light and dark screens alike.
private struct HandleSquare: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(PixelHandTheme.Brand.phosphor)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(PixelHandTheme.Brand.screen)
                    .frame(width: size * 0.4, height: size * 0.4)
            )
            .shadow(color: PixelHandTheme.Brand.glow, radius: 3)
    }
}

/// Dims everything outside `selection` with the navy scrim. One even-odd
/// `Path`, so there are no seams between four sub-rects.
private struct DimOutside: View {
    let selection: CGRect

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addRect(selection)
            }
            .fill(PixelHandTheme.Brand.screen.opacity(0.62), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
        }
    }
}
