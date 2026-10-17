//
//  DotScan.swift
//  DeckHandiOS
//
//  "Looking for your Mac": a column of light sweeping slowly across a small
//  piece of the icon's dot screen. Searching is the remote talking to the
//  network, so it's drawn in lit dots rather than a spinner.
//

import SwiftUI

struct DotScan: View {
    var columns = 21
    var rows = 9
    var pitch: CGFloat = 9
    var plateCornerRadius: CGFloat = 18
    var platePadding: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One sweep across, in seconds. Slow: this can run for a long time.
    static let period: TimeInterval = 2.6
    /// How many columns of afterglow trail behind the sweep.
    static let trail: Double = 5

    var body: some View {
        let columns = self.columns
        let rows = self.rows
        let pitch = self.pitch
        let reduceMotion = self.reduceMotion
        PixelScreen(cornerRadius: plateCornerRadius, padding: platePadding) {
            // Under Reduce Motion the schedule is paused, so this draws one
            // still frame with the sweep partway across.
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
                let phase = reduceMotion
                    ? 0.55
                    : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                let pass = Int(timeline.date.timeIntervalSinceReferenceDate / Self.period)
                Canvas { context, _ in
                    Self.draw(columns: columns, rows: rows, pitch: pitch, phase: phase, pass: pass, in: &context)
                }
            }
            .frame(width: CGFloat(columns) * pitch, height: CGFloat(rows) * pitch)
        }
        .accessibilityElement()
        .accessibilityLabel("Searching for Macs")
    }

    private static func draw(
        columns: Int,
        rows: Int,
        pitch: CGFloat,
        phase: Double,
        pass: Int,
        in context: inout GraphicsContext
    ) {
        // The head travels from just off the left edge to past the right,
        // so the trail clears before the next pass starts.
        let head = phase * (Double(columns) + trail + 2) - 1
        let dot = pitch * PixelPainter.dotRatio
        let unlit = DeckHandTheme.Brand.dotOff
        let ray = DeckHandTheme.Brand.ray
        let phosphor = DeckHandTheme.Brand.phosphor
        let glow = DeckHandTheme.Brand.glow

        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(
                    x: CGFloat(column) * pitch + (pitch - dot) / 2,
                    y: CGFloat(row) * pitch + (pitch - dot) / 2,
                    width: dot,
                    height: dot
                )
                let behind = head - Double(column)
                var e = 0.0
                if behind >= 0 && behind < trail {
                    e = pow(1 - behind / trail, 1.6)
                    // Vary each pass a little so the sweep doesn't read as a solid bar.
                    let shimmer = Double((column * 31 + row * 17 + pass * 13) % 11) / 11
                    e *= 0.7 + 0.3 * shimmer
                }
                context.fill(PixelPainter.dotPath(rect), with: .color(unlit))
                guard e > 0.02 else { continue }
                if e > 0.4 {
                    let halo = rect.insetBy(dx: -dot * 0.5, dy: -dot * 0.5)
                    context.fill(Path(ellipseIn: halo), with: .color(glow.opacity(0.25 * e)))
                }
                context.fill(PixelPainter.dotPath(rect), with: .color((e > 0.7 ? phosphor : ray).opacity(0.3 + 0.7 * e)))
            }
        }
    }
}
