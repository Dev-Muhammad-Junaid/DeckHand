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
    var onPaste: (String) -> Void

    func makeUIView(context: Context) -> PasteTargetView {
        let target = PasteTargetView()
        target.onPaste = onPaste
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
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

/// The panel's clipboard line: Paste to Mac, and what last came from the
/// Mac.
struct ClipboardRow: View {
    let sender: TrackpadSender
    var clipboard: RemoteClipboard?
    let colorScheme: ColorScheme
    var onActivity: () -> Void = {}

    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        HStack(spacing: 10) {
            PasteToMacControl { text in
                onActivity()
                clipboard?.pasteToMac(text, paste: settings.pasteRightAway, sender: sender)
            }
            .fixedSize()
            .frame(height: 36)
            .accessibilityHint("Sends this device's clipboard text to the Mac")

            VStack(alignment: .leading, spacing: 2) {
                Text(settings.pasteRightAway ? "to the Mac, where its cursor is" : "to the Mac's clipboard")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
                if let status = clipboard?.pasteStatus {
                    Text(status)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                } else if settings.clipboardSync, let fromMac = clipboard?.lastFromMac {
                    Text("Copied on the Mac: “\(fromMac)”")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .requiresPro(.sharing) // Store lane
    }
}
