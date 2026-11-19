//
//  DeliveryStrip.swift
//  DeckHandiOS – Design system
//
//  The receipt under a chip (3 dots) or key (4 dots): idle `fill2`; sending
//  lights the dots one by one; delivered turns mint and ends with a check;
//  refused turns danger and ends with a cross, so the result reads without
//  colour. Keeps `DeliveryDots`' timing and `DeliveryState`.
//  Spec: `Product/Design/02-Design-System.md` §6, `06-Pixel-Identity.md` §7.
//

import SwiftUI

struct DeliveryStrip: View {
    var state: DeliveryState
    var count: Int = 3
    var dotSize: CGFloat = 4
    var spacing: CGFloat = 3
    /// White-on-cobalt variant for the default dialog chip.
    var onAccent = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.pixelOnNavy) private var onNavy

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: dotSize * 0.26, style: .continuous)
                    .fill(color(for: index))
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: glows ? sendingColor.opacity(0.8) : .clear, radius: glows ? 2 : 0)
                    .animation(animation(for: index), value: state)
            }
            receiptMark
        }
        .frame(height: max(dotSize, 6))
        .accessibilityHidden(true)
    }

    private var glows: Bool {
        state == .sending && (onNavy || scheme == .dark)
    }

    /// Sending: glow on dark and navy, accent on light (glow is navy-only).
    private var sendingColor: Color {
        onAccent ? .white : (onNavy || scheme == .dark ? PixelHandTheme.Brand.glow : PixelHandTheme.accent)
    }

    private func color(for index: Int) -> Color {
        switch state {
        case .idle: onAccent ? .white.opacity(0.35) : PixelHandTheme.fill2
        case .sending, .sent: sendingColor
        case .confirmed: onAccent ? .white : PixelHandTheme.success
        case .failed: onAccent ? .white : PixelHandTheme.danger
        }
    }

    @ViewBuilder
    private var receiptMark: some View {
        switch state {
        case .confirmed:
            mark(PixelHandTheme.success, path: { size in
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size * 0.55))
                p.addLine(to: CGPoint(x: size * 0.38, y: size))
                p.addLine(to: CGPoint(x: size, y: 0))
                return p
            })
        case .failed:
            mark(PixelHandTheme.danger, path: { size in
                var p = Path()
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: size, y: size))
                p.move(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: 0, y: size))
                return p
            })
        default:
            EmptyView()
        }
    }

    private func mark(_ color: Color, path: @escaping (CGFloat) -> Path) -> some View {
        let side = dotSize + 2
        return path(side)
            .stroke(onAccent ? .white : color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side)
            .transition(.opacity)
    }

    private func animation(for index: Int) -> Animation {
        guard state == .sending, !reduceMotion else { return .easeOut(duration: 0.2) }
        return .easeOut(duration: 0.12).delay(Double(index) * PixelHandMotion.deliveryStagger)
    }
}

#Preview("Delivery strip") {
    VStack(spacing: 12) {
        ForEach(Array([DeliveryState.idle, .sending, .confirmed, .failed].enumerated()), id: \.offset) { _, state in
            HStack(spacing: 24) {
                DeliveryStrip(state: state)
                DeliveryStrip(state: state, count: 4, dotSize: 3.5, spacing: 2.5)
            }
        }
    }
    .padding(24)
    .background(.phCanvas)
}
