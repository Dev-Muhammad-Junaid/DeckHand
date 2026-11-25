//
//  MultiTouchTrackpad.swift
//  DeckHandiOS
//
//  UIViewRepresentable that wraps a custom UIView for raw multi-touch
//  tracking. SwiftUI's DragGesture only tracks one finger; this gives
//  1/2/3/4-finger awareness for the pointer, scrolling, drags and the Mac's
//  system gestures, plus Apple Pencil hover.
//
//  The decisions live in PixelHandCore, tested on Linux:
//  - `DragStateMachine`: press-hold-move drags, the two-finger drag lock,
//    and the long-press right click (now on lift, after the hold).
//  - `GestureStroke` / `GestureClassifier`: three- and four-finger swipes
//    and pinches, decided when the first finger lifts (S11).
//  - `HoverPointerTracker`: Pencil hover moves the pointer (S12).
//  - `TwoFingerArbiter` (OR-16, the mirror picture only): two fingers
//    scroll the Mac, pinch (then slide) zooms and pans the picture, and a
//    quick two-finger tap right-clicks.
//

import QuartzCore
import SwiftUI
import UIKit

// MARK: - Gesture event types reported to the parent view

enum TrackpadGestureKind: Equatable {
    case cursor           // 1-finger move
    case scroll           // 2-finger move
    case dragArmed        // held still: moving now drags
    case dragging         // the Mac's button is down
    case dragLocked       // two-finger drag lock
    case system(MultiFingerGesture) // 3+ fingers, decided at lift
    case pencilHover      // Apple Pencil hovering
}

/// Callbacks from the multi-touch surface to the SwiftUI host.
struct TrackpadCallbacks {
    /// Pointer movement: a finger, a drag, or Pencil hover.
    var onCursorDelta: (Float, Float) -> Void = { _, _ in }
    /// Continuous delta during 2-finger drag (scroll).
    var onScrollDelta: (Float, Float) -> Void = { _, _ in }
    /// Fired once all fingers driving an active scroll gesture lift, so
    /// the host can ship `ScrollPhase.end` to the Mac. Required for AppKit's
    /// rubber-banding + momentum animations to play out instead of just
    /// stopping abruptly.
    var onScrollEnded: () -> Void = { }
    /// A three- or four-finger swipe or pinch, once per stroke, at lift.
    var onSystemGesture: (MultiFingerGesture) -> Void = { _ in }
    /// 1-finger tap (fast touch < 0.3s with < 6pt movement).
    var onTap: (CGPoint) -> Void = { _ in }
    /// 1-finger double-tap (two taps within 0.35s).
    var onDoubleTap: (CGPoint) -> Void = { _ in }
    /// 1-finger long press lifted without moving: a right click.
    var onLongPress: (CGPoint) -> Void = { _ in }
    /// The left button went down (`true`) or up (`false`) for a drag.
    var onDragButton: (Bool) -> Void = { _ in }
    /// Reports the active gesture kind for the UI indicator (nil = idle).
    var onGestureChanged: (TrackpadGestureKind?) -> Void = { _ in }
    /// Every finger on the surface, in the view's coordinates, whenever one
    /// lands, moves or lifts. Drives the dot field; empty when all have lifted.
    var onTouchesChanged: ([CGPoint]) -> Void = { _ in }
    /// OR-16, arbitrated surfaces only: a two-finger touch decided as a
    /// pinch zooms the picture by `scale` (relative to the last call)
    /// around `anchor`, and pans it by `pan`.
    var onPictureZoom: (_ scale: CGFloat, _ anchor: CGPoint, _ pan: CGSize) -> Void = { _, _, _ in }
    /// The pinch's fingers lifted.
    var onPictureZoomEnded: () -> Void = { }
    /// Arbitrated surfaces only: a quick two-finger tap (a right click).
    var onTwoFingerTap: (CGPoint) -> Void = { _ in }
}

// MARK: - SwiftUI bridge

struct MultiTouchTrackpad: UIViewRepresentable {
    let callbacks: TrackpadCallbacks
    let sensitivity: Float
    let scrollMode: Bool
    var naturalScrolling: Bool = false
    /// Three- and four-finger gestures run Mac views (S11).
    var systemGestures: Bool = true
    /// Apple Pencil hover moves the pointer (S12).
    var pencilHover: Bool = true
    /// OR-16: two fingers go through `TwoFingerArbiter` (pinch zooms the
    /// picture, two-finger tap right-clicks). Off on the Pointer surface.
    var arbitratesTwoFingers: Bool = false

    func makeUIView(context: Context) -> TouchTrackingView {
        let view = TouchTrackingView()
        apply(to: view)
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TouchTrackingView, context: Context) {
        apply(to: uiView)
    }

    static func dismantleUIView(_ uiView: TouchTrackingView, coordinator: ()) {
        // The trackpad left the screen: never leave the Mac's button down.
        uiView.releaseEverything()
    }

    private func apply(to view: TouchTrackingView) {
        view.callbacks = callbacks
        view.sensitivity = sensitivity
        view.scrollMode = scrollMode
        view.naturalScrolling = naturalScrolling
        view.systemGestures = systemGestures
        view.pencilHover = pencilHover
        view.arbitratesTwoFingers = arbitratesTwoFingers
    }
}

// MARK: - Raw touch-tracking UIView

final class TouchTrackingView: UIView {
    var callbacks = TrackpadCallbacks()
    var sensitivity: Float = 1.8
    var scrollMode: Bool = false
    /// Flips scroll deltas so the content tracks the fingers.
    var naturalScrolling: Bool = false
    var systemGestures: Bool = true
    var pencilHover: Bool = true {
        didSet { hoverRecognizer.isEnabled = pencilHover }
    }
    var arbitratesTwoFingers: Bool = false

    private var scrollSign: Float { naturalScrolling ? -1 : 1 }

    // ── Touch tracking state ──────────────────────────────────────
    private var activeTouches: [UITouch] = []
    private var lastCentroid: CGPoint?

    // ── Tap detection ─────────────────────────────────────────────
    private var touchDownTime: Double = 0
    private var touchDownLocation: CGPoint = .zero
    private var lastSingleTapTime: Double = 0
    private var hasMoved = false

    // ── Drag (Core `DragStateMachine`) ────────────────────────────
    private var drag = DragStateMachine()
    /// Ticks the machine while a press waits to arm or a lock waits to
    /// time out.
    private var dragTicker: Task<Void, Never>?

    // ── System gestures (Core `GestureStroke`) ────────────────────
    private var stroke = GestureStroke()
    /// Once a stroke armed (three fingers), the rest of the touch sends
    /// no pointer motion, click or scroll.
    private var strokeOwnsTouch = false

    // ── Two fingers on the picture (Core `TwoFingerArbiter`, OR-16) ─
    private var twoFingers = TwoFingerArbiter()
    /// Once a pinch started, the rest of the touch zooms and pans the
    /// picture only: a finger left behind doesn't move the pointer.
    private var pinchOwnsTouch = false

    /// `true` while a scroll gesture (1-finger scrollMode or 2-finger drag)
    /// is in flight. Drives `onScrollEnded` so the host can ship a phased
    /// `.end` event when the driving fingers lift.
    private var scrollActive = false

    // ── Pencil hover (S12) ────────────────────────────────────────
    private lazy var hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    private var hover = HoverPointerTracker()

    override init(frame: CGRect) {
        super.init(frame: frame)
        hoverRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(hoverRecognizer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        hoverRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(hoverRecognizer)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { releaseEverything() }
    }

    /// Releases a held button and forgets every touch.
    func releaseEverything() {
        handle(drag.reset())
        dragTicker?.cancel()
        dragTicker = nil
        stroke.cancel()
        hover.ended()
        finishTwoFingers(twoFingers.cancel())
        pinchOwnsTouch = false
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let wasEmpty = activeTouches.isEmpty
        for touch in touches where !activeTouches.contains(touch) {
            activeTouches.append(touch)
        }
        let now = CACurrentMediaTime()
        let count = activeTouches.count
        lastCentroid = centroid(of: activeTouches)
        hover.ended()

        if wasEmpty {
            touchDownTime = now
            touchDownLocation = activeTouches[0].location(in: self)
            hasMoved = false
            strokeOwnsTouch = false
            pinchOwnsTouch = false
            stroke.reset()
        }
        if count > 1 { hasMoved = true }

        handle(drag.touchBegan(fingerCount: count, at: now))
        startDragTickerIfNeeded()

        if systemGestures, !drag.routesMovementToPointer, count >= GestureClassifier.minimumFingers {
            stroke.fingers(fingerPoints())
            if stroke.isArmed, !strokeOwnsTouch {
                strokeOwnsTouch = true
                endScrollIfActive()
            }
        }

        if arbitratesTwoFingers {
            if count == 2, !drag.routesMovementToPointer, !strokeOwnsTouch, !pinchOwnsTouch, !twoFingers.isTracking {
                let points = activeTouches.map { $0.location(in: self) }
                twoFingers.begin(
                    TouchPoint(x: points[0].x, y: points[0].y),
                    TouchPoint(x: points[1].x, y: points[1].y),
                    at: now
                )
            } else if count > 2 || strokeOwnsTouch {
                // A third finger: the Mac's system gestures take over.
                finishTwoFingers(twoFingers.cancel())
            }
        }

        callbacks.onGestureChanged(currentKind(fingerCount: count))
        reportTouches()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        let count = activeTouches.count
        let currentCentroid = centroid(of: activeTouches)
        let now = CACurrentMediaTime()

        guard let last = lastCentroid else {
            lastCentroid = currentCentroid
            return
        }
        let dx = Float(currentCentroid.x - last.x)
        let dy = Float(currentCentroid.y - last.y)
        lastCentroid = currentCentroid

        // Distance from where the touch landed: tap detection and the
        // drag machine's slop.
        let distance = hypot(currentCentroid.x - touchDownLocation.x,
                             currentCentroid.y - touchDownLocation.y)
        if count == 1, distance > DragPolicy.slop {
            hasMoved = true
        }
        handle(drag.touchMoved(distance: Double(distance), at: now))

        // The Mac's button is down: every move drags, whatever the fingers.
        if drag.routesMovementToPointer {
            callbacks.onCursorDelta(dx * sensitivity, dy * sensitivity)
            reportTouches()
            return
        }

        // A system gesture owns the touch until every finger lifts.
        if strokeOwnsTouch {
            stroke.fingers(fingerPoints())
            reportTouches()
            return
        }

        // A pinch owns the touch until every finger lifts (OR-16).
        if pinchOwnsTouch, !twoFingers.isTracking {
            reportTouches()
            return
        }

        // Two fingers on the picture: scroll, or pinch and pan (OR-16).
        if arbitratesTwoFingers, twoFingers.isTracking, count == 2 {
            let points = activeTouches.map { $0.location(in: self) }
            let step = twoFingers.move(
                TouchPoint(x: points[0].x, y: points[0].y),
                TouchPoint(x: points[1].x, y: points[1].y)
            )
            switch step {
            case .none:
                break
            case let .scroll(sdx, sdy):
                scrollActive = true
                callbacks.onScrollDelta(Float(sdx) * 0.5 * scrollSign, Float(sdy) * 0.5 * scrollSign)
                callbacks.onGestureChanged(.scroll)
            case let .zoom(scale, anchor, pdx, pdy):
                pinchOwnsTouch = true
                callbacks.onPictureZoom(
                    CGFloat(scale),
                    CGPoint(x: anchor.x, y: anchor.y),
                    CGSize(width: pdx, height: pdy)
                )
            }
            reportTouches()
            return
        }

        switch count {
        case 1:
            // 1-finger: cursor OR scroll depending on mode
            if hasMoved {
                if scrollMode {
                    scrollActive = true
                    callbacks.onScrollDelta(dx * 0.5 * scrollSign, dy * 0.5 * scrollSign)
                    callbacks.onGestureChanged(.scroll)
                } else {
                    callbacks.onCursorDelta(dx * sensitivity, dy * sensitivity)
                    callbacks.onGestureChanged(.cursor)
                }
            }

        case 2:
            // Scroll — gentler multiplier
            scrollActive = true
            callbacks.onScrollDelta(dx * 0.5 * scrollSign, dy * 0.5 * scrollSign)
            callbacks.onGestureChanged(.scroll)

        default:
            break
        }
        reportTouches()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        let wasCount = activeTouches.count
        let now = CACurrentMediaTime()
        // A system gesture is decided as its first finger lifts.
        if strokeOwnsTouch, !stroke.isFinished {
            stroke.fingers(fingerPoints())
            if let gesture = stroke.lift() {
                GestureHaptic.medium.trigger()
                callbacks.onSystemGesture(gesture)
                callbacks.onGestureChanged(.system(gesture))
            }
        }
        let liftedAt = lastCentroid ?? touchDownLocation
        activeTouches.removeAll { touches.contains($0) }

        // Fewer than two fingers: the two-finger touch is decided (OR-16).
        if twoFingers.isTracking, activeTouches.count < 2 {
            let ending = twoFingers.end(at: now)
            if ending == .tap, !drag.isButtonDown {
                GestureHaptic.medium.trigger()
                callbacks.onTwoFingerTap(liftedAt)
            }
            finishTwoFingers(ending)
        }

        let machineOwnedTouch = drag.ownsTouch
        let outputs = drag.touchEnded(remaining: activeTouches.count, at: now)
        handle(outputs)

        // All fingers lifted — evaluate final gesture
        if activeTouches.isEmpty {
            endScrollIfActive()

            // 1-finger tap — not when the drag machine owned the touch (a
            // tap that ends a drag lock, an armed press) or a stroke did.
            if wasCount == 1, !hasMoved, !machineOwnedTouch, outputs.isEmpty, !strokeOwnsTouch {
                let duration = now - touchDownTime
                if duration < DragPolicy.tapMaxDuration {
                    if lastSingleTapTime > 0 && (now - lastSingleTapTime) < 0.35 {
                        // Double-tap
                        lastSingleTapTime = 0
                        GestureHaptic.medium.trigger()
                        callbacks.onDoubleTap(touchDownLocation)
                    } else {
                        // Single tap
                        lastSingleTapTime = now
                        GestureHaptic.medium.trigger()
                        callbacks.onTap(touchDownLocation)
                    }
                }
            }

            lastCentroid = nil
            strokeOwnsTouch = false
            pinchOwnsTouch = false
            if !drag.isButtonDown {
                callbacks.onGestureChanged(nil)
            }
        } else {
            // Some fingers still down — update centroid
            lastCentroid = centroid(of: activeTouches)
            if !strokeOwnsTouch {
                callbacks.onGestureChanged(currentKind(fingerCount: activeTouches.count))
            }
        }
        reportTouches()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        activeTouches.removeAll { touches.contains($0) }
        // The system took the touch (four-finger multitasking, a call):
        // a stroke sends nothing and a held button is released.
        stroke.cancel()
        handle(drag.touchesCancelled())
        if activeTouches.count < 2 {
            finishTwoFingers(twoFingers.cancel())
        }
        if activeTouches.isEmpty {
            endScrollIfActive()
            lastCentroid = nil
            strokeOwnsTouch = false
            pinchOwnsTouch = false
            callbacks.onGestureChanged(nil)
        }
        reportTouches()
    }

    // MARK: - Drag machine plumbing

    private func handle(_ outputs: [DragStateMachine.Output]) {
        for output in outputs {
            switch output {
            case .armed:
                GestureHaptic.heavy.trigger()
                callbacks.onGestureChanged(.dragArmed)
            case .buttonDown:
                GestureHaptic.light.trigger()
                callbacks.onDragButton(true)
                callbacks.onGestureChanged(.dragging)
            case .buttonUp:
                callbacks.onDragButton(false)
                callbacks.onGestureChanged(activeTouches.isEmpty ? nil : currentKind(fingerCount: activeTouches.count))
            case .rightClick:
                callbacks.onLongPress(touchDownLocation)
            case .lockEngaged:
                GestureHaptic.medium.trigger()
                callbacks.onGestureChanged(.dragLocked)
            }
        }
        startDragTickerIfNeeded()
    }

    /// Runs while the machine has something time-based pending: a press
    /// that may arm, or a lock that may time out.
    private func startDragTickerIfNeeded() {
        let needsTicks: Bool
        switch drag.phase {
        case .pressing, .locked: needsTicks = true
        default: needsTicks = false
        }
        guard needsTicks, dragTicker == nil else { return }
        dragTicker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                let outputs = self.drag.tick(at: CACurrentMediaTime())
                switch self.drag.phase {
                case .pressing, .locked:
                    if !outputs.isEmpty { self.handle(outputs) }
                default:
                    self.dragTicker = nil
                    self.handle(outputs)
                    return
                }
            }
        }
    }

    // MARK: - Pencil hover (S12)

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        // Only a hovering Apple Pencil: a pointer (trackpad or mouse) has
        // no height above the screen and already moves the iPad's pointer.
        guard pencilHover, activeTouches.isEmpty, recognizer.zOffset > 0 else {
            if hover.isHovering {
                hover.ended()
                callbacks.onGestureChanged(nil)
            }
            return
        }
        switch recognizer.state {
        case .began, .changed:
            let point = recognizer.location(in: self)
            if !hover.isHovering { callbacks.onGestureChanged(.pencilHover) }
            if let delta = hover.moved(to: TouchPoint(x: point.x, y: point.y), sensitivity: Double(sensitivity)) {
                callbacks.onCursorDelta(Float(delta.dx), Float(delta.dy))
            }
        default:
            hover.ended()
            callbacks.onGestureChanged(nil)
        }
    }

    // MARK: - Helpers

    /// Closes what a two-finger touch opened. The tap itself is sent by
    /// `touchesEnded`, which knows where the fingers were.
    private func finishTwoFingers(_ ending: TwoFingerArbiter.Ending) {
        switch ending {
        case .scrollEnded: endScrollIfActive()
        case .pinchEnded: callbacks.onPictureZoomEnded()
        case .tap, .nothing: break
        }
    }

    private func endScrollIfActive() {
        if scrollActive {
            scrollActive = false
            callbacks.onScrollEnded()
        }
    }

    private func reportTouches() {
        callbacks.onTouchesChanged(activeTouches.map { $0.location(in: self) })
    }

    /// The fingers on the glass, keyed per touch, for `GestureStroke`.
    private func fingerPoints() -> [Int: TouchPoint] {
        var points: [Int: TouchPoint] = [:]
        for touch in activeTouches {
            let p = touch.location(in: self)
            points[ObjectIdentifier(touch).hashValue] = TouchPoint(x: p.x, y: p.y)
        }
        return points
    }

    private func centroid(of touches: [UITouch]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for touch in touches {
            let loc = touch.location(in: self)
            sumX += loc.x
            sumY += loc.y
        }
        let n = CGFloat(touches.count)
        return CGPoint(x: sumX / n, y: sumY / n)
    }

    private func currentKind(fingerCount: Int) -> TrackpadGestureKind? {
        switch drag.phase {
        case .armed: return .dragArmed
        case .dragging, .lockedTouch: return .dragging
        case .lockedHolding, .locked: return .dragLocked
        case .idle, .pressing, .passive: break
        }
        switch fingerCount {
        case 1:  return scrollMode ? .scroll : .cursor
        case 2:  return .scroll
        default: return nil  // Reported when the system gesture is decided
        }
    }
}
