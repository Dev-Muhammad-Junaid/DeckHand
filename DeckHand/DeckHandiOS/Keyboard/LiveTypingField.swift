//
//  LiveTypingField.swift
//  DeckHandiOS
//
//  A real text field whose every committed change is typed on the Mac.
//
//  It keeps a small local buffer so the system keyboard works fully:
//  autocorrect, QuickPath, dictation, and the input methods that compose
//  text (Chinese, Japanese, Korean, …). Nothing is sent while the input
//  method is composing (marked text); when the text is committed, Core's
//  `TypingEdit` diffs it against the last commit and the Mac replays it as
//  Backspaces plus text at its own cursor. The caret is kept at the end so
//  the diff and the Mac's cursor agree.
//
//  Hardware keyboards: arrows, Escape, Tab, Home/End, Page Up/Down,
//  Forward Delete and any ⌘ / ⌃ chord go to the Mac as key presses instead
//  of editing the local buffer. Backspace in an empty field still deletes
//  on the Mac.
//

import SwiftUI
import UIKit

struct LiveTypingField: UIViewRepresentable {
    var placeholder: String
    /// Modifiers latched in the key row: the next typed letter goes as a
    /// chord with them (⌘ + C), and they're cleared.
    var latchedModifiers: [KeyModifier]
    var onEdit: (TypingEdit) -> Void
    var onKey: (RemoteKey, [KeyModifier]) -> Void
    var onChord: ([String]) -> Void
    var onModifiersUsed: () -> Void

    func makeUIView(context: Context) -> LiveTypingTextView {
        let view = LiveTypingTextView()
        apply(to: view)
        // Up comes the keyboard as soon as the panel opens.
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: LiveTypingTextView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: LiveTypingTextView) {
        view.placeholder = placeholder
        view.latchedModifiers = latchedModifiers
        view.onEdit = onEdit
        view.onKey = onKey
        view.onChord = onChord
        view.onModifiersUsed = onModifiersUsed
    }
}

final class LiveTypingTextView: UITextView, UITextViewDelegate {
    var placeholder = "" {
        didSet { placeholderLabel.text = placeholder }
    }
    var latchedModifiers: [KeyModifier] = []
    var onEdit: (TypingEdit) -> Void = { _ in }
    var onKey: (RemoteKey, [KeyModifier]) -> Void = { _, _ in }
    var onChord: ([String]) -> Void = { _ in }
    var onModifiersUsed: () -> Void = {}

    /// What the Mac has been sent, as this field showed it.
    private var committed = ""
    /// Presses handled here (sent to the Mac), so their ends aren't
    /// passed to UIKit either.
    private var handledPresses: Set<ObjectIdentifier> = []
    private let placeholderLabel = UILabel()

    /// Past this many characters the buffer is cut back to its end, so the
    /// diff stays cheap; autocorrect only looks at the last word anyway.
    private static let bufferLimit = 400
    private static let bufferKeep = 40

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        backgroundColor = .clear
        isScrollEnabled = false
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byTruncatingHead
        // What the Mac receives should be what the person typed: no
        // curly quotes or em dashes behind their back. Autocorrect and
        // predictions stay on; their replacements are diffed and replayed.
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        accessibilityLabel = "Type on the Mac"

        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textContainerInset.left + 5),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Software keyboard

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !text.isEmpty
        // An input method is composing: wait for the commit.
        guard markedTextRange == nil else { return }
        let current = text ?? ""
        let edit = TypingEdit.between(committed, current)
        guard !edit.isEmpty else { return }

        // A latched modifier turns the next letter into a chord (⌘C).
        if !latchedModifiers.isEmpty, edit.deletes == 0, edit.insert.count == 1,
           let character = edit.insert.first {
            let name = String(character).lowercased()
            if KeyTable.keyCode(for: name) != nil {
                text = committed
                placeholderLabel.isHidden = !committed.isEmpty
                onChord(KeyModifier.pressOrder.filter(latchedModifiers.contains).map(\.wireName) + [name])
                onModifiersUsed()
                return
            }
        }

        committed = current
        onEdit(edit)
        if committed.count > Self.bufferLimit {
            committed = String(committed.suffix(Self.bufferKeep))
            text = committed
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        // Keep the caret at the end: the Mac's cursor can't follow a caret
        // moved here, so edits always apply at the end.
        guard markedTextRange == nil else { return }
        let end = (text as NSString?)?.length ?? 0
        if selectedRange.location != end || selectedRange.length != 0 {
            selectedRange = NSRange(location: end, length: 0)
        }
    }

    override func deleteBackward() {
        // Nothing left here to delete: delete on the Mac anyway.
        if markedTextRange == nil, (text ?? "").isEmpty {
            onKey(.delete, latchedModifiers)
            if !latchedModifiers.isEmpty { onModifiersUsed() }
            return
        }
        super.deleteBackward()
    }

    // MARK: - Hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            if let key = press.key, handle(key) {
                handledPresses.insert(ObjectIdentifier(press))
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { handledPresses.remove(ObjectIdentifier($0)) == nil }
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { handledPresses.remove(ObjectIdentifier($0)) == nil }
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }

    /// Sends `key` to the Mac if it isn't text. Returns whether it did.
    private func handle(_ key: UIKey) -> Bool {
        let modifiers = Self.modifiers(key.modifierFlags)
        if let remote = Self.remoteKey(for: key.keyCode) {
            onKey(remote, modifiers)
            return true
        }
        // ⌘ / ⌃ chords (⌘C, ⌘Z, ⌃A …) are the Mac's, not this field's.
        guard modifiers.contains(.command) || modifiers.contains(.control) else { return false }
        let name: String
        switch key.keyCode {
        case .keyboardReturnOrEnter: name = RemoteKey.return.wireName
        case .keyboardDeleteOrBackspace: name = RemoteKey.delete.wireName
        case .keyboardSpacebar: name = "space"
        default: name = key.charactersIgnoringModifiers.lowercased()
        }
        guard KeyTable.keyCode(for: name) != nil else { return false }
        onChord(KeyModifier.pressOrder.filter(modifiers.contains).map(\.wireName) + [name])
        return true
    }

    private static func remoteKey(for code: UIKeyboardHIDUsage) -> RemoteKey? {
        switch code {
        case .keyboardLeftArrow: .left
        case .keyboardRightArrow: .right
        case .keyboardUpArrow: .up
        case .keyboardDownArrow: .down
        case .keyboardEscape: .escape
        case .keyboardTab: .tab
        case .keyboardHome: .home
        case .keyboardEnd: .end
        case .keyboardPageUp: .pageUp
        case .keyboardPageDown: .pageDown
        case .keyboardDeleteForward: .forwardDelete
        default: nil
        }
    }

    private static func modifiers(_ flags: UIKeyModifierFlags) -> [KeyModifier] {
        var out: [KeyModifier] = []
        if flags.contains(.command) { out.append(.command) }
        if flags.contains(.shift) { out.append(.shift) }
        if flags.contains(.alternate) { out.append(.option) }
        if flags.contains(.control) { out.append(.control) }
        return out
    }
}
