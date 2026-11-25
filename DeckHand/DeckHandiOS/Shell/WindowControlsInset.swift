//
//  WindowControlsInset.swift
//  DeckHandiOS – Shell
//
//  How far Stage Manager's window controls (close, minimise, full screen;
//  iPadOS 26) reach into the top-leading corner of this view, so the shell
//  header can start after them instead of under them (build 18 QA,
//  VQ-080). Reads UIKit's corner-adapted safe area: the gap between the
//  `.safeArea(cornerAdaptation: .horizontal)` layout guide and the plain
//  safe-area guide is the controls' width. 0 on iOS 17–18, full screen, and iPhone.
//

import SwiftUI
import UIKit

struct WindowControlsInset: UIViewRepresentable {
    @Binding var inset: CGFloat

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onChange = { value in
            // Whole points, and only on a real change, so layout settles.
            let rounded = value.rounded(.up)
            if abs(rounded - inset) >= 1 {
                DispatchQueue.main.async { inset = rounded }
            }
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.setNeedsLayout()
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onChange?(measure())
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            onChange?(measure())
        }

        private func measure() -> CGFloat {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                // The corner-adapted guide starts after the window controls;
                // the plain safe-area guide doesn't.
                let adapted = layoutGuide(for: .safeArea(cornerAdaptation: .horizontal)).layoutFrame
                let plain = safeAreaLayoutGuide.layoutFrame
                let inset = effectiveUserInterfaceLayoutDirection == .rightToLeft
                    ? plain.maxX - adapted.maxX
                    : adapted.minX - plain.minX
                return max(0, inset)
            }
            #endif
            return 0
        }
    }
}
