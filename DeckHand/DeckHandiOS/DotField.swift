//
//  DotField.swift
//  DeckHandiOS
//
//  The trackpad surface as the icon's dot screen: a faint grid of dots that
//  light up under each finger, leave a short afterglow behind a drag, and
//  send a ring outward on a tap. Lit dots mean the remote is talking to the
//  Mac, so the field only lights in response to input.
//

import SwiftUI

/// A finger position recorded for the afterglow behind a drag.
struct DotSample: Sendable {
    let point: CGPoint
    let time: TimeInterval
}

/// A ring sent out by a tap. `filled` lights the inside too, for the
/// long-press right-click.
struct DotPulse: Sendable {
    let center: CGPoint
    let time: TimeInterval
    let filled: Bool
}

/// Touch state for `DotField`. The trackpad writes finger positions here at
/// touch rate; only the dot layer reads them, so the rest of the trackpad
/// view doesn't re-render while a finger moves.
@MainActor
@Observable
final class DotFieldModel {
    /// Fingers on the glass right now, in the field's coordinate space.
    private(set) var touches: [CGPoint] = []
    /// Recent finger positions, newest last.
    private(set) var trail: [DotSample] = []
    private(set) var pulses: [DotPulse] = []
    /// Nothing is lit: the field stops redrawing until the next touch.
    private(set) var isIdle = true

    @ObservationIgnored private var lastSampleTime: TimeInterval = 0
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// How long a dot keeps glowing after a finger moves off it.
    nonisolated static let afterglow: TimeInterval = 0.3
    nonisolated static let pulseDuration: TimeInterval = 0.6

    func setTouches(_ points: [CGPoint]) {
        let now = Date.timeIntervalSinceReferenceDate
        touches = points
        // Sample at most 60 times a second; the afterglow doesn't need more.
        if now - lastSampleTime >= 1.0 / 60 {
            lastSampleTime = now
            trail.removeAll { now - $0.time > Self.afterglow }
            trail.append(contentsOf: points.map { DotSample(point: $0, time: now) })
            if trail.count > 64 { trail.removeFirst(trail.count - 64) }
        }
        if isIdle { isIdle = false }
        if points.isEmpty {
            scheduleSettle()
        } else {
            settleTask?.cancel()
        }
    }

    func pulse(at point: CGPoint, filled: Bool = false) {
        let now = Date.timeIntervalSinceReferenceDate
        pulses.removeAll { now - $0.time > Self.pulseDuration }
        pulses.append(DotPulse(center: point, time: now, filled: filled))
        if isIdle { isIdle = false }
        if touches.isEmpty { scheduleSettle() }
    }

    /// Stops the redraw once the last afterglow and ring have faded.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(Self.afterglow, Self.pulseDuration) + 0.1))
            guard !Task.isCancelled, let self, self.touches.isEmpty else { return }
            self.trail.removeAll()
            self.pulses.removeAll()
            self.isIdle = true
        }
    }
}

/// The dot grid both layers of the field share, centred in its size.
struct DotGrid {
    let pitch: CGFloat
    let columns: Int
    let rows: Int
    let origin: CGPoint

    init(size: CGSize, pitch: CGFloat) {
        self.pitch = pitch
        columns = max(1, Int(size.width / pitch))
        rows = max(1, Int(size.height / pitch))
        origin = CGPoint(
            x: (size.width - CGFloat(columns - 1) * pitch) / 2,
            y: (size.height - CGFloat(rows - 1) * pitch) / 2
        )
    }

    func center(column: Int, row: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(column) * pitch, y: origin.y + CGFloat(row) * pitch)
    }

    func forEach(_ body: (CGPoint) -> Void) {
        for row in 0..<rows {
            for column in 0..<columns {
                body(center(column: column, row: row))
            }
        }
    }

    /// Visits only the dots inside the square around `point`, with an index
    /// that's stable for the grid's size.
    func forEach(near point: CGPoint, radius: CGFloat, _ body: (Int, CGPoint) -> Void) {
        guard point.x.isFinite, point.y.isFinite, radius.isFinite else { return }
        let c0 = max(0, Int(((point.x - radius - origin.x) / pitch).rounded(.down)))
        let c1 = min(columns - 1, Int(((point.x + radius - origin.x) / pitch).rounded(.up)))
        let r0 = max(0, Int(((point.y - radius - origin.y) / pitch).rounded(.down)))
        let r1 = min(rows - 1, Int(((point.y + radius - origin.y) / pitch).rounded(.up)))
        guard c0 <= c1, r0 <= r1 else { return }
        for row in r0...r1 {
            for column in c0...c1 {
                body(row * columns + column, center(column: column, row: row))
            }
        }
    }
}

struct DotField: View {
    let model: DotFieldModel
    var pitch: CGFloat = 15
    var dotSize: CGFloat = 2.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RestingDots(pitch: pitch, dotSize: dotSize)
            LitDotLayer(model: model, pitch: pitch, dotSize: dotSize, reduceMotion: reduceMotion)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The unlit grid. A separate view with plain inputs, so SwiftUI skips it
/// while the lit layer animates.
private struct RestingDots: View {
    let pitch: CGFloat
    let dotSize: CGFloat

    var body: some View {
        let pitch = self.pitch
        let dotSize = self.dotSize
        Canvas { context, size in
            var dots = Path()
            DotGrid(size: size, pitch: pitch).forEach { center in
                dots.addRoundedRect(
                    in: CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize),
                    cornerSize: CGSize(width: dotSize * 0.3, height: dotSize * 0.3)
                )
            }
            context.fill(dots, with: .color(DeckHandTheme.Brand.dotOff))
        }
    }
}

/// Redraws every frame while anything is lit, and not at all otherwise.
private struct LitDotLayer: View {
    let model: DotFieldModel
    let pitch: CGFloat
    let dotSize: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let pitch = self.pitch
        let dotSize = self.dotSize
        let reduceMotion = self.reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: model.isIdle)) { timeline in
            let lit = LitDots(
                touches: model.touches,
                trail: reduceMotion ? [] : model.trail,
                pulses: model.pulses,
                now: timeline.date.timeIntervalSinceReferenceDate,
                reduceMotion: reduceMotion
            )
            Canvas { context, size in
                lit.draw(in: &context, grid: DotGrid(size: size, pitch: pitch), dotSize: dotSize)
            }
        }
    }
}

/// One frame of lit dots, computed from a snapshot of the model.
private struct LitDots {
    let touches: [CGPoint]
    let trail: [DotSample]
    let pulses: [DotPulse]
    let now: TimeInterval
    let reduceMotion: Bool

    /// How far from a finger dots still light.
    static let reach: CGFloat = 64
    /// Width of a tap ring.
    static let band: CGFloat = 10

    func draw(in context: inout GraphicsContext, grid: DotGrid, dotSize: CGFloat) {
        var energy: [Int: Double] = [:]
        var centers: [Int: CGPoint] = [:]

        func light(around point: CGPoint, radius: CGFloat, _ value: (CGFloat) -> Double) {
            grid.forEach(near: point, radius: radius) { index, center in
                let e = value(hypot(center.x - point.x, center.y - point.y))
                guard e > energy[index, default: 0] else { return }
                energy[index] = e
                centers[index] = center
            }
        }

        func falloff(_ distance: CGFloat) -> Double {
            distance < Self.reach ? pow(Double(1 - distance / Self.reach), 1.5) : 0
        }

        for touch in touches {
            light(around: touch, radius: Self.reach, falloff)
        }

        for sample in trail {
            let fade = 1 - (now - sample.time) / DotFieldModel.afterglow
            guard fade > 0 else { continue }
            light(around: sample.point, radius: Self.reach) { falloff($0) * fade * 0.75 }
        }

        for pulse in pulses {
            let progress = (now - pulse.time) / DotFieldModel.pulseDuration
            guard progress >= 0, progress < 1 else { continue }
            let amplitude = pow(1 - progress, 1.5)
            if reduceMotion {
                // No expanding ring: the dots under the tap light and fade.
                let radius: CGFloat = 36
                light(around: pulse.center, radius: radius) { d in
                    d < radius ? amplitude * (1 - Double(d / radius) * 0.5) : 0
                }
            } else {
                let radius = 18 + CGFloat(progress) * 150
                let filled = pulse.filled
                light(around: pulse.center, radius: radius + Self.band) { d in
                    let ring = max(0, 1 - Double(abs(d - radius) / Self.band)) * amplitude
                    return filled && d < radius ? max(ring, amplitude * 0.45) : ring
                }
            }
        }

        let phosphor = DeckHandTheme.Brand.phosphor
        let ray = DeckHandTheme.Brand.ray
        let glow = DeckHandTheme.Brand.glow

        for (index, e) in energy where e > 0.02 {
            guard let center = centers[index] else { continue }
            if e > 0.35 {
                let halo = dotSize * (2 + 2 * CGFloat(e))
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - halo / 2, y: center.y - halo / 2, width: halo, height: halo)),
                    with: .color(glow.opacity(0.22 * e))
                )
            }
            let side = dotSize + CGFloat(e) * 2.4
            context.fill(
                Path(
                    roundedRect: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
                    cornerRadius: side * 0.3,
                    style: .continuous
                ),
                with: .color((e > 0.6 ? phosphor : ray).opacity(0.35 + 0.65 * e))
            )
        }
    }
}
