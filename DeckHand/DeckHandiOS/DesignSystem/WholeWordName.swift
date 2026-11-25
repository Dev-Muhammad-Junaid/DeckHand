//
//  WholeWordName.swift
//  DeckHandiOS – Design system
//
//  A Mac's name on one or two lines, broken only between words and never
//  hyphenated or cut mid-word (`ShellHeaderPlan.pillNameLayout`). Each line
//  is its own one-line `Text`; `ViewThatFits` takes the first layout that
//  fits whole: the name, its word splits, the tail ones ("Muhammad’s /
//  MacBook…"), the word splits at smaller real font sizes, then the first
//  word alone (build 23, VQ-085). Used by the header's Mac pill and the
//  picker's Mac card (VQ-084).
//

import PixelHandCore
import SwiftUI

struct WholeWordName: View {
    let name: String
    /// 1 at the Standard and Large bands (one line, tail truncation); 2 at
    /// the Huge band.
    let lines: Int
    /// The font size at the current Dynamic Type size (a `@ScaledMetric`).
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var color: Color = PixelHandTheme.ink

    var body: some View {
        let layout = ShellHeaderPlan.pillNameLayout(name, lines: lines)
        if layout.candidates.count == 1, layout.shrinkCandidates.isEmpty {
            line(layout.fallback.first ?? name, size: size)
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(layout.candidates.indices, id: \.self) { index in
                    stack(layout.candidates[index], size: size)
                }
                ForEach(Self.shrinkSteps(layout), id: \.self) { step in
                    stack(step.lines, size: size * CGFloat(step.scale))
                }
                stack(layout.lastResort, size: size * CGFloat(ShellHeaderPlan.pillNameMinimumScale))
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private struct ShrinkStep: Hashable {
        let lines: [String]
        let scale: Double
    }

    private static func shrinkSteps(_ layout: ShellHeaderPlan.PillNameLayout) -> [ShrinkStep] {
        ShellHeaderPlan.pillNameShrinkScales.flatMap { scale in
            layout.shrinkCandidates.map { ShrinkStep(lines: $0, scale: scale) }
        }
    }

    private func stack(_ lines: [String], size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                line(lines[index], size: size)
            }
        }
        // Its full height, even in a tight row (build 22: the second line
        // was lost and the first cut).
        .fixedSize(horizontal: false, vertical: true)
    }

    private func line(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
