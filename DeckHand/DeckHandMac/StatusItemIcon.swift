//
//  StatusItemIcon.swift
//  DeckHandMac
//
//  The menu-bar hand (UX-019, `06-Pixel-Identity.md` §8): the app icon's
//  dot hand as a template image, so it follows light, dark and tinted menu
//  bars. Which dots each state lights is Core's `MenuBarHand`:
//
//  | State | Look |
//  | --- | --- |
//  | Not ready (starting, failed) | whole hand at 50 % |
//  | Ready | outline dots |
//  | A device is asking | fingertip blinks at 1 Hz |
//  | Connected | fill dots on |
//  | Being controlled | fill dots and tap rays |
//  | Receiving | a 3-dot beam runs along the cuff |
//  | Locked (a device connected) | a padlock in the palm |
//
//  Reduce Motion holds the first frame: a steady fingertip, a still beam.
//  Drawn rather than looked up, so it can't fail to resolve and collapse
//  the item to zero width. One point per dot, each dot a whole point, keeps
//  it crisp at 1× and 2×; at this size a gap between dots would vanish.
//

import AppKit

enum StatusItemIcon {
    static func image(for state: MenuBarHandState, frame: Int) -> NSImage {
        let dots = MenuBarHand.dots(for: state, frame: frame)
        let size = NSSize(width: MenuBarHand.width, height: MenuBarHand.height)
        let image = NSImage(size: size, flipped: true) { _ in
            for dot in dots {
                NSColor.black.withAlphaComponent(dot.alpha).setFill()
                NSRect(x: dot.x, y: dot.y, width: 1, height: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }
}

/// Keeps the status item's hand in step with the app: whether Loom is
/// running, pending requests, live connections, the Mac's lock state and
/// recent input or arrivals (`MenuBarActivity`).
@MainActor
final class StatusItemIconController {
    private weak var button: NSStatusBarButton?
    private var pendingRequests = 0
    private var liveConnections = 0
    private var state: MenuBarHandState = .notReady
    private var frame = 0
    private var shown: (MenuBarHandState, Int)?
    private var tickTask: Task<Void, Never>?

    /// Whether the app is up: `running` once Loom has started, `failed`
    /// after a fatal start error. Unset reads as running.
    var readiness: (() -> (running: Bool, failed: Bool))? {
        didSet { refresh() }
    }

    init(button: NSStatusBarButton) {
        self.button = button
        MenuBarActivity.shared.onChange = { [weak self] in self?.refresh() }
        refresh()
        startTicking()
    }

    func update(pendingRequests: Int, liveConnections: Int) {
        self.pendingRequests = pendingRequests
        self.liveConnections = liveConnections
        refresh()
    }

    /// Re-reads every input and redraws if the picture changed.
    private func refresh() {
        let now = Date()
        let readiness = self.readiness?() ?? (running: true, failed: false)
        let activity = MenuBarActivity.shared
        let next = MenuBarHandState.resolve(.init(
            isRunning: readiness.running,
            failedToStart: readiness.failed,
            pendingRequests: pendingRequests,
            liveConnections: liveConnections,
            isLocked: MacLockMonitor.shared.state.isLocked,
            secondsSinceInput: activity.lastInput.map { now.timeIntervalSince($0) },
            secondsSinceReceive: activity.lastReceive.map { now.timeIntervalSince($0) }
        ))
        if next != state {
            state = next
            frame = 0
        }
        render()
    }

    /// One loop for the blink, the beam, the lock state and the holds
    /// running out: 10 Hz while the beam runs, 2 Hz otherwise.
    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let fast = self?.state == .receiving
                try? await Task.sleep(for: .milliseconds(fast ? 100 : 500))
                guard let self, !Task.isCancelled else { return }
                if self.state.animates, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self.frame &+= 1
                } else {
                    self.frame = 0
                }
                self.refresh()
            }
        }
    }

    private func render() {
        if let shown, shown.0 == state, shown.1 == frame { return }
        shown = (state, frame)
        button?.image = StatusItemIcon.image(for: state, frame: frame)
        button?.setAccessibilityLabel(state.accessibilityDescription)
    }
}
