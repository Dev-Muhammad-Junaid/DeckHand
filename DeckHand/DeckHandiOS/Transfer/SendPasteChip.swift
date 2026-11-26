//
//  SendPasteChip.swift
//  DeckHandiOS – Transfer
//
//  The Send sheet's Clipboard chip: the system paste control
//  (`UIPasteControl`), so reading the clipboard is the person's own tap on
//  a system control and iOS never shows "Allow Paste" (DECISIONS.md,
//  2026-11-26, "Send sheet clipboard uses the system Paste button";
//  `PasteToMacControl` does the same for Paste to Mac).
//
//  `UIPasteControl` rather than SwiftUI `PasteButton`: only the UIKit
//  control takes a background colour, a foreground colour and a fixed
//  corner radius, which is what the chip spec needs (`07-Polish-Spec.md`,
//  Sources: 44 tall, a third of the row, `raised`, hairline, radius 14).
//  The system draws its own icon and "Paste" label in one foreground
//  colour and its own font: no pixel glyph, no custom title and no font
//  can be set on a paste control. So the other two chips follow it (owner
//  testing, build 27, OT-17: Paste had accent text and looked different):
//  all three draw icon and label in `ink` (`SendSheetLayout.SourceChip`),
//  Photos and Files use system symbols like Paste's, and their labels use
//  the paste control's own label font, read from the control once it has
//  laid out (`onLabelFont`; reading a font covers nothing).
//
//  What to load from each pasted provider is `SendPastePlan` (Core):
//  a web link, then text, then an image (an image first when there is no
//  text). Text and links are staged as text, images as photo files, the
//  same staging the old chip (text) and the Photos chip (images) use.
//

import PixelHandCore
import SwiftUI
import UIKit

/// Something the paste control brought in, ready to stage.
enum SendPastedItem: Sendable, Equatable {
    case text(String)
    /// A private copy in its own temporary folder.
    case image(url: URL, contentType: String?)
}

/// The chip: the system paste control styled to the source chips, with
/// the hairline drawn behind it (nothing may cover a paste control).
struct SendPasteChip: View {
    /// Called once per paste with everything that loaded, in clipboard
    /// order; empty when nothing usable was there.
    var onPaste: @MainActor ([SendPastedItem]) -> Void
    /// The font the paste control set its "Paste" label in, once laid out,
    /// so Photos and Files can use the same (OT-17).
    var onLabelFont: @MainActor (UIFont) -> Void = { _ in }

    var body: some View {
        // The control fills the chip's whole 44 pt frame (build 27 bug 3:
        // inset by its hairline it measured 43 pt). The hairline is drawn
        // just outside it, behind, so nothing covers the system control.
        SendPasteControl(onPaste: onPaste, onLabelFont: onLabelFont)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip + PixelHandTheme.Stroke.hairline, style: .continuous)
                    .fill(PixelHandTheme.hairline)
                    .padding(-PixelHandTheme.Stroke.hairline)
            }
            .accessibilityElement(children: .contain)
    }
}

private struct SendPasteControl: UIViewRepresentable {
    var onPaste: @MainActor ([SendPastedItem]) -> Void
    var onLabelFont: @MainActor (UIFont) -> Void

    func makeUIView(context: Context) -> SendPasteTargetView {
        let target = SendPasteTargetView()
        target.onPaste = onPaste
        target.onLabelFont = onLabelFont
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = CGFloat(SendSheetLayout.SourceChip.cornerRadius)
        configuration.baseBackgroundColor = UIColor(token: SendSheetLayout.SourceChip.background)
        // Ink, like the other chips' icon and label (OT-17; was accent).
        configuration.baseForegroundColor = UIColor(token: SendSheetLayout.SourceChip.foreground)
        let control = UIPasteControl(configuration: configuration)
        control.target = target
        control.translatesAutoresizingMaskIntoConstraints = false
        // The identifier the old chip had, so UI tests still find it.
        control.accessibilityIdentifier = "ph.send.source.clipboard"
        target.addSubview(control)
        target.control = control
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            control.topAnchor.constraint(equalTo: target.topAnchor),
            control.bottomAnchor.constraint(equalTo: target.bottomAnchor),
        ])
        return target
    }

    func updateUIView(_ view: SendPasteTargetView, context: Context) {
        view.onPaste = onPaste
        view.onLabelFont = onLabelFont
    }
}

/// Takes the paste: loads each planned provider's candidates in order
/// (falling through when one yields nothing) and reports once all are in.
final class SendPasteTargetView: UIView {
    var onPaste: @MainActor ([SendPastedItem]) -> Void = { _ in }
    var onLabelFont: @MainActor (UIFont) -> Void = { _ in }
    weak var control: UIView?
    /// The last font reported, so a re-layout doesn't report it again.
    private var reportedFont: UIFont?

    /// The paste in progress; a newer paste replaces it.
    private var batch = UUID()
    private var providers: [NSItemProvider] = []
    private var results: [SendPastedItem?] = []
    private var remaining = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: SendPastePlan.acceptedTypeIdentifiers)
        // A text size change: measure the paste control's label again.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: SendPasteTargetView, _: UITraitCollection) in
            view.reportedFont = nil
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// After the paste control lays out, finds its label and reports the
    /// label's font (OT-17). Reads only; nothing is added to or drawn over
    /// the control. When the label can't be found the chips keep their
    /// fallback font.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let control, let label = Self.firstLabel(in: control), let font = label.font else { return }
        guard font != reportedFont else { return }
        reportedFont = font
        // Next turn of the main actor: not inside SwiftUI's update.
        Task { @MainActor [weak self] in self?.onLabelFont(font) }
    }

    private static func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, !(label.text ?? "").isEmpty { return label }
        for child in view.subviews {
            if let found = firstLabel(in: child) { return found }
        }
        return nil
    }

    override func paste(itemProviders: [NSItemProvider]) {
        let plan = SendPastePlan.plan(providers: itemProviders.map(\.registeredTypeIdentifiers))
        guard !plan.isEmpty else {
            onPaste([])
            return
        }
        let token = UUID()
        batch = token
        providers = plan.map { itemProviders[$0.index] }
        results = Array(repeating: nil, count: plan.count)
        remaining = plan.count
        let numbered = plan.count > 1
        for (slot, entry) in plan.enumerated() {
            attempt(slot: slot, candidates: entry.candidates[...], ordinal: numbered ? slot + 1 : 1, token: token)
        }
    }

    private func attempt(slot: Int, candidates: ArraySlice<SendPastePlan.Candidate>, ordinal: Int, token: UUID) {
        guard token == batch else { return }
        guard let candidate = candidates.first else {
            settle(slot: slot, item: nil, token: token)
            return
        }
        let rest = candidates.dropFirst()
        let provider = providers[slot]
        switch candidate {
        case .webLink:
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                let item = url.flatMap(SendPastePlan.stagedText(fromLink:)).map(SendPastedItem.text)
                Task { @MainActor in
                    self?.loaded(item, slot: slot, rest: rest, ordinal: ordinal, token: token)
                }
            }
        case .text:
            _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                let item = (object as? String).flatMap(SendPastePlan.stagedText(fromText:)).map(SendPastedItem.text)
                Task { @MainActor in
                    self?.loaded(item, slot: slot, rest: rest, ordinal: ordinal, token: token)
                }
            }
        case let .image(typeIdentifier, fileExtension, needsConversion):
            let name = SendPastePlan.imageFileName(fileExtension: fileExtension, ordinal: ordinal)
            let contentType = SendPastePlan.stagedContentType(for: candidate)
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
                let file = data.flatMap { SendPasteFiles.write($0, named: name, convertToPNG: needsConversion) }
                let item = file.map { SendPastedItem.image(url: $0, contentType: contentType) }
                Task { @MainActor in
                    self?.loaded(item, slot: slot, rest: rest, ordinal: ordinal, token: token)
                }
            }
        }
    }

    private func loaded(_ item: SendPastedItem?, slot: Int, rest: ArraySlice<SendPastePlan.Candidate>, ordinal: Int, token: UUID) {
        if let item {
            settle(slot: slot, item: item, token: token)
        } else {
            attempt(slot: slot, candidates: rest, ordinal: ordinal, token: token)
        }
    }

    private func settle(slot: Int, item: SendPastedItem?, token: UUID) {
        guard token == batch, slot < results.count else { return }
        results[slot] = item
        remaining -= 1
        guard remaining == 0 else { return }
        let items = results.compactMap { $0 }
        providers = []
        results = []
        onPaste(items)
    }
}

/// Writes pasted image data off the main actor (provider callbacks run on
/// a background queue).
enum SendPasteFiles {
    nonisolated static func write(_ data: Data, named name: String, convertToPNG: Bool) -> URL? {
        let bytes: Data
        if convertToPNG {
            guard let png = UIImage(data: data)?.pngData() else { return nil }
            bytes = png
        } else {
            bytes = data
        }
        guard !bytes.isEmpty else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString)", isDirectory: true)
        let destination = folder.appendingPathComponent(TransferFileName.sanitized(name, kind: .photo))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }
}

private extension UIColor {
    /// A token colour that follows light / dark and Increase Contrast, like
    /// `Color(token:)`, for UIKit configurations.
    convenience init(token: ColorToken) {
        self.init { traits in
            let swatch = token.swatch(
                dark: traits.userInterfaceStyle == .dark,
                highContrast: traits.accessibilityContrast == .high
            )
            return UIColor(red: swatch.color.red, green: swatch.color.green, blue: swatch.color.blue, alpha: swatch.opacity)
        }
    }
}
