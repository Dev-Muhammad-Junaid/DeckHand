//
//  LiveTypingField.swift
//  DeckHandiOS
//
//  The Type panel's text field (owner testing, build 24, OT-3). One
//  `UITextView` serves both modes, so switching Live ⇄ Compose never hands
//  the keyboard to another view (and never drops it, OT-2):
//
//  Live: every committed change is typed on the Mac. It keeps a small
//  local buffer so the system keyboard works fully: autocorrect, QuickPath,
//  dictation, and the input methods that compose text (Chinese, Japanese,
//  Korean, …). Nothing is sent while the input method is composing (marked
//  text); when the text is committed, Core's `TypingEdit` diffs it against
//  the last commit and the Mac replays it as Backspaces plus text at its
//  own cursor. The caret is kept at the end so the diff and the Mac's
//  cursor agree. Hardware keyboards: arrows, Escape, Tab, Home/End, Page
//  Up/Down, Forward Delete and any ⌘ / ⌃ chord go to the Mac as key
//  presses instead of editing the local buffer. Backspace in an empty field
//  still deletes on the Mac.
//
//  Compose: an ordinary local field (caret, selection, paste, dictation),
//  up to a few lines. Return sends (the keyboard's key reads "Send");
//  ⇧Return adds a line. Nothing reaches the Mac until Send.
//
//  Focus is driven from outside: the field takes the keyboard when
//  `wantsFocus` is on and `focusRequest` changes, and gives it up when
//  `wantsFocus` goes off (the Numpad tab, the panel closing).
//

import SwiftUI
import UIKit

struct LiveTypingField: UIViewRepresentable {
    var mode: TypeMode = .live
    var placeholder: String
    /// Modifiers latched in the key row: the next typed letter goes as a
    /// chord with them (⌘ + C), and they're used up.
    var latchedModifiers: [KeyModifier]
    /// Compose's draft, kept by the panel's model.
    var draft: Binding<String>? = nil
    var wantsFocus = true
    var focusRequest = 0
    /// Lines Compose may grow to before it scrolls.
    var composeLines = 2
    /// Take the height the parent proposes (the Type panel's field fills
    /// its band, OT-11) instead of sizing to the text; scrolls past it.
    var fillsHeight = false
    var onEdit: (TypingEdit) -> Void
    var onKey: (RemoteKey, [KeyModifier]) -> Void
    var onChord: ([String]) -> Void
    var onModifiersUsed: () -> Void
    /// Compose: Return (or ⌘Return) asked to send.
    var onSubmit: () -> Void = {}
    /// The field took focus (a tap while the numpad shows, OT-7).
    var onFocus: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastFocusRequest = -1
        var lastMode: TypeMode?
    }

    func makeUIView(context: Context) -> LiveTypingTextView {
        let view = LiveTypingTextView()
        view.accessibilityIdentifier = "ph.type.field"
        apply(to: view, context: context)
        return view
    }

    func updateUIView(_ view: LiveTypingTextView, context: Context) {
        apply(to: view, context: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LiveTypingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        if fillsHeight, let height = proposal.height, height.isFinite, height > 0 {
            let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            uiView.isScrollEnabled = fitted > height + 0.5
            return CGSize(width: width, height: height)
        }
        let lineHeight = uiView.font?.lineHeight ?? 20
        let lines = mode == .compose ? CGFloat(max(1, composeLines)) : 1
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let maxHeight = lineHeight * lines + uiView.textContainerInset.top + uiView.textContainerInset.bottom
        let minHeight = lineHeight + uiView.textContainerInset.top + uiView.textContainerInset.bottom
        uiView.isScrollEnabled = fitted > maxHeight + 0.5
        return CGSize(width: width, height: min(max(fitted, minHeight), maxHeight).rounded(.up))
    }

    private func apply(to view: LiveTypingTextView, context: Context) {
        view.placeholder = placeholder
        view.latchedModifiers = latchedModifiers
        view.onEdit = onEdit
        view.onKey = onKey
        view.onChord = onChord
        view.onModifiersUsed = onModifiersUsed
        view.onSubmit = onSubmit
        view.onFocus = onFocus
        view.onDraftChange = { text in draft?.wrappedValue = text }

        if context.coordinator.lastMode != mode {
            context.coordinator.lastMode = mode
            view.setMode(mode, draft: draft?.wrappedValue ?? "")
        } else if mode == .compose, let draft, view.text != draft.wrappedValue, view.markedTextRange == nil {
            // The model changed the draft (Send cleared it, Paste or the
            // numpad added to it).
            view.text = draft.wrappedValue
            view.refreshPlaceholder()
        }

        if wantsFocus {
            if context.coordinator.lastFocusRequest != focusRequest {
                context.coordinator.lastFocusRequest = focusRequest
                // After this layout pass, so the view is in a window.
                DispatchQueue.main.async {
                    if !view.isFirstResponder { view.becomeFirstResponder() }
                }
            }
        } else {
            context.coordinator.lastFocusRequest = focusRequest
            if view.isFirstResponder {
                DispatchQueue.main.async { view.resignFirstResponder() }
            }
        }
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
    var onSubmit: () -> Void = {}
    var onFocus: () -> Void = {}
    var onDraftChange: (String) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus() }
        return became
    }

    private(set) var mode: TypeMode = .live
    /// What the Mac has been sent, as this field showed it (Live).
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
        textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        // What the Mac receives should be what the person typed: no
        // curly quotes or em dashes behind their back. Autocorrect and
        // predictions stay on; their replacements are diffed and replayed.
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        accessibilityLabel = "Type on the Mac"

        placeholderLabel.font = font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textContainer.lineFragmentPadding),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: textContainerInset.top),
        ])
        setMode(.live, draft: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Switches mode without giving up the keyboard: Live starts from an
    /// empty buffer (nothing typed here is on the Mac yet); Compose shows
    /// the kept draft.
    func setMode(_ newMode: TypeMode, draft: String) {
        mode = newMode
        committed = ""
        textContainer.maximumNumberOfLines = newMode == .live ? 1 : 0
        textContainer.lineBreakMode = newMode == .live ? .byTruncatingHead : .byWordWrapping
        returnKeyType = newMode == .compose ? .send : .default
        accessibilityLabel = newMode == .live ? "Type on the Mac" : "Compose text for the Mac"
        accessibilityHint = newMode.spokenHint
        text = newMode == .compose ? draft : ""
        refreshPlaceholder()
        if isFirstResponder { reloadInputViews() }
    }

    func refreshPlaceholder() {
        placeholderLabel.isHidden = !(text ?? "").isEmpty
    }

    // MARK: - Software keyboard

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
        // Compose: the keyboard's Send key sends; a pasted or dictated
        // line break stays text.
        if mode == .compose, replacement == "\n" {
            onSubmit()
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        refreshPlaceholder()
        if mode == .compose {
            onDraftChange(text ?? "")
            return
        }
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
                refreshPlaceholder()
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
        // Live keeps the caret at the end: the Mac's cursor can't follow a
        // caret moved here, so edits always apply at the end.
        guard mode == .live, markedTextRange == nil else { return }
        let end = (text as NSString?)?.length ?? 0
        if selectedRange.location != end || selectedRange.length != 0 {
            selectedRange = NSRange(location: end, length: 0)
        }
    }

    override func deleteBackward() {
        // Live, nothing left here to delete: delete on the Mac anyway.
        if mode == .live, markedTextRange == nil, (text ?? "").isEmpty {
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

    /// Live: sends `key` to the Mac if it isn't text. Compose: only ⌘Return
    /// (send) is taken; the rest edits the draft. Returns whether it did.
    private func handle(_ key: UIKey) -> Bool {
        let modifiers = Self.modifiers(key.modifierFlags)
        if mode == .compose {
            if key.keyCode == .keyboardReturnOrEnter, modifiers == [.command] {
                onSubmit()
                return true
            }
            // ⇧Return: a new line in the draft.
            if key.keyCode == .keyboardReturnOrEnter, modifiers == [.shift] {
                insertText("\n")
                return true
            }
            return false
        }
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
