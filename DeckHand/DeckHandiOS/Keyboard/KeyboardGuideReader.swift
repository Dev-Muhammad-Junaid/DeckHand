//
//  KeyboardGuideReader.swift
//  DeckHandiOS – Keyboard
//
//  A second reading of the on-screen keyboard for the Type panel (build 30
//  bug 1, P1). In iPad portrait the panel drew under the keyboard when
//  Live's field took focus: only its header showed, so the keyboard's top
//  had been lost from the frame notifications (`TypePanelModel`). UIKit's
//  keyboard layout guide (public, iOS 15; `usesBottomSafeArea`, iOS 17) is
//  laid out in the view itself whenever the keyboard, the window or the
//  orientation changes, with no conversion between coordinate spaces, so
//  it can't come back turned or stale.
//
//  An invisible, full-window view pins a marker to the guide and reports
//  the marker's frame in window space; Core's
//  `KeyboardFrameReading.guideReading` turns it into a reading, and the
//  model merges it with the notifications' (`merged`): covered when
//  either says so, up to the higher top.
//

import PixelHandCore
import SwiftUI
import UIKit

struct KeyboardGuideReader: UIViewRepresentable {
    /// The guide's reading (`nil`: not usable) and the window's bottom
    /// safe area, on the main queue after each layout that changed them.
    var onChange: (KeyboardFrameReading.Reading?, Double) -> Void

    func makeUIView(context: Context) -> KeyboardGuideView {
        let view = KeyboardGuideView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: KeyboardGuideView, context: Context) {
        view.onChange = onChange
    }
}

final class KeyboardGuideView: UIView {
    var onChange: (KeyboardFrameReading.Reading?, Double) -> Void = { _, _ in }

    private let marker = KeyboardGuideMarker()
    private var lastReported: (reading: KeyboardFrameReading.Reading?, inset: Double)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        marker.isUserInteractionEnabled = false
        marker.backgroundColor = .clear
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.onLayout = { [weak self] in self?.report() }
        addSubview(marker)
        // The docked keyboard only: a floating or undocked one covers no
        // edge (the panel moves around it by hand). Hidden, the guide is
        // zero tall at the bottom, not the home indicator's height.
        keyboardLayoutGuide.followsUndockedKeyboard = false
        keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor),
            marker.trailingAnchor.constraint(equalTo: trailingAnchor),
            marker.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
            marker.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        lastReported = nil
        setNeedsLayout()
    }

    /// The marker's frame (the guide) in window space, as a reading.
    private func report() {
        guard let window else { return }
        let guide = marker.convert(marker.bounds, to: window)
        let view = convert(bounds, to: window)
        let reading = KeyboardFrameReading.guideReading(
            PanelRect(x: Double(guide.minX), y: Double(guide.minY), width: Double(guide.width), height: Double(guide.height)),
            viewMaxY: Double(view.maxY),
            windowHeight: Double(window.bounds.height)
        )
        let inset = Double(window.safeAreaInsets.bottom)
        if let last = lastReported, last.reading == reading, last.inset == inset { return }
        lastReported = (reading, inset)
        // Not during the layout pass: the model is observed by SwiftUI.
        DispatchQueue.main.async { [weak self] in self?.deliver(reading, inset) }
    }

    private func deliver(_ reading: KeyboardFrameReading.Reading?, _ inset: Double) {
        onChange(reading, inset)
    }
}

/// Reports every layout of the guide's marker to the reader.
final class KeyboardGuideMarker: UIView {
    var onLayout: () -> Void = {}

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout()
    }

    override var frame: CGRect {
        didSet { if frame != oldValue { onLayout() } }
    }

    override var center: CGPoint {
        didSet { if center != oldValue { onLayout() } }
    }

    override var bounds: CGRect {
        didSet { if bounds != oldValue { onLayout() } }
    }
}
