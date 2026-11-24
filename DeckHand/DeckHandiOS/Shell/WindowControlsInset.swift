//
//  WindowControlsInset.swift
//  DeckHandiOS – Shell
//
//  How far Stage Manager's window controls (close, minimise, full screen;
//  iPadOS 26) reach into the top-leading corner of this view, so the shell
//  header can start after them instead of under them (build 18 QA,
//  VQ-080). Reads UIKit's corner-adapted safe area: the difference between
//  `.safeArea(cornerAdaptation: .horizontal)` and the plain safe area is
//  the controls' width. 0 on iOS 17–18, full screen, and iPhone.
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
                let adapted = directionalEdgeInsets(for: .safeArea(cornerAdaptation: .horizontal))
                let plain = safeAreaInsets
                let leadingPlain = effectiveUserInterfaceLayoutDirection == .rightToLeft ? plain.right : plain.left
                return max(0, adapted.leading - leadingPlain)
            }
            #endif
            return 0
        }
    }
}
