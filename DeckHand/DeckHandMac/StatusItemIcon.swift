//
//  StatusItemIcon.swift
//  DeckHandMac
//
//  The menu bar icon: the app icon's dot hand as a template image, in three
//  states. An outline means ready, rays blinking beside the fingertip mean
//  an iPad is asking to connect, and a filled hand means one is connected.
//

import AppKit

enum StatusItemState: Equatable {
    case ready
    case request
    case connected

    var accessibilityDescription: String {
        switch self {
        case .ready: "Deck Hand"
        case .request: "Deck Hand, connection request waiting"
        case .connected: "Deck Hand, iPad connected"
        }
    }
}

enum StatusItemIcon {
    /// Rows above the hand for the tap rays. The full icon uses three; two
    /// keep the menu bar icon within 20 pt while leaving a one-dot gap.
    private static let headroom = 2
    /// Tap rays above the fingertip (columns 5–6) in icon rows: straight up,
    /// and one out to each side.
    private static let rays: [(x: Int, y: Int)] = [(5, 0), (6, 0), (3, 1), (8, 1)]

    /// One point per dot keeps the pixel art crisp on Retina displays.
    private static let pitch: CGFloat = 1

    static func image(for state: StatusItemState, raysLit: Bool) -> NSImage {
        let hand = PixelArt.hand
        let pitch = Self.pitch
        let headroom = Self.headroom
        let rays = Self.rays
        let size = NSSize(width: CGFloat(hand.width) * pitch, height: CGFloat(hand.height + headroom) * pitch)
        let image = NSImage(size: size, flipped: true) { _ in
            func dot(_ x: Int, _ y: Int, alpha: CGFloat) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSRect(x: CGFloat(x) * pitch, y: CGFloat(y) * pitch, width: pitch, height: pitch).fill()
            }
            for y in 0..<hand.height {
                for x in 0..<hand.width {
                    switch hand[x, y] {
                    case .outline:
                        dot(x, y + headroom, alpha: 1)
                    case .fill where state == .connected:
                        // Lighter than the outline so the knuckle lines still read.
                        dot(x, y + headroom, alpha: 0.45)
                    default:
                        break
                    }
                }
            }
            if state == .request, raysLit {
                rays.forEach { dot($0.x, $0.y, alpha: 1) }
            }
            return true
        }
        // Template: the menu bar tints it for light, dark and tinted bars.
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }
}

/// Keeps the status item's image in step with pending requests and live
/// connections, and blinks the rays while a request waits.
@MainActor
final class StatusItemIconController {
    private weak var button: NSStatusBarButton?
    private var state: StatusItemState = .ready
    private var raysLit = true
    private var blinkTask: Task<Void, Never>?

    init(button: NSStatusBarButton) {
        self.button = button
        render()
    }

    func update(pendingRequests: Int, liveConnections: Int) {
        let next: StatusItemState = pendingRequests > 0
            ? .request
            : (liveConnections > 0 ? .connected : .ready)
        guard next != state else { return }
        state = next
        raysLit = true
        render()

        blinkTask?.cancel()
        blinkTask = nil
        // A held still icon under Reduce Motion: the rays stay lit.
        guard state == .request, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(520))
                guard let self, !Task.isCancelled else { return }
                self.raysLit.toggle()
                self.render()
            }
        }
    }

    private func render() {
        button?.image = StatusItemIcon.image(for: state, raysLit: raysLit)
    }
}
