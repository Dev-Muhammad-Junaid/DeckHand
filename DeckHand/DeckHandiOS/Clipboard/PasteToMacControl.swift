//
//  PasteToMacControl.swift
//  DeckHandiOS
//
//  Paste to Mac: the system paste control (`UIPasteControl`), so reading
//  this device's clipboard never shows the "Allow Paste" prompt. The
//  control pastes into an invisible target view that accepts plain text
//  and hands it on.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PasteToMacControl: UIViewRepresentable {
    /// The clipboard icon alone (the Type panel's compact field column,
    /// OT-7); otherwise icon and "Paste".
    var iconOnly = false
    var onPaste: (String) -> Void

    func makeUIView(context: Context) -> PasteTargetView {
        let target = PasteTargetView()
        target.onPaste = onPaste
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = iconOnly ? .iconOnly : .iconAndLabel
        configuration.cornerStyle = .capsule
        let control = UIPasteControl(configuration: configuration)
        control.target = target
        control.translatesAutoresizingMaskIntoConstraints = false
        target.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            control.topAnchor.constraint(equalTo: target.topAnchor),
            control.bottomAnchor.constraint(equalTo: target.bottomAnchor),
        ])
        return target
    }

    func updateUIView(_ view: PasteTargetView, context: Context) {
        view.onPaste = onPaste
    }
}

/// Accepts plain text from the paste control.
final class PasteTargetView: UIView {
    var onPaste: (String) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.plainText.identifier])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let text = object as? String else { return }
            Task { @MainActor in
                self?.onPaste(text)
            }
        }
    }
}
