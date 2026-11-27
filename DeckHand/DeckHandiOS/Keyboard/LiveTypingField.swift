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
//  Synced Live (protocol 17, live text sync Phase 1): when the Mac can read
//  its focused field (native, non-secure; `LiveTextSync`), the field shows
//  the Mac's text, a window around the caret, with the caret at the Mac's
//  selection. Edits go out as anchored range edits with local echo, one in
//  flight (Core's `TextSyncReconciler`); the caret is free: taps, the
//  keyboard's space-bar trackpad and the selection handles move the Mac's
//  caret too (`textSelect`). Keyboard (owner decision 2): autocorrect and
//  predictions on, smart quotes and dashes off, the spell-check underline
//  off, and no local undo: undo (shake, three-finger swipe, ⌘Z) goes to the
//  Mac. Nothing goes while an input method composes. When the field can't
//  be read, it falls back to the blind buffer above and the placeholder
//  says why.
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
    /// Live text sync: the Mac's text, when it can be read (`nil` in the
    /// classic layout: always blind).
    var sync: LiveTextSync? = nil

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
        if view.sync !== sync {
            view.sync = sync
        }
        if mode == .live { sync?.display = view }

        if context.coordinator.lastMode != mode {
            context.coordinator.lastMode = mode
            view.setMode(mode, draft: draft?.wrappedValue ?? "")
        } else if mode == .compose, let draft, view.text != draft.wrappedValue, view.markedTextRange == nil {
            // The model changed the draft (Send cleared it, Paste or the
            // numpad added to it).
            view.text = draft.wrappedValue
            view.refreshPlaceholder()
        }

        view.syncStateChanged()

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

final class LiveTypingTextView: UITextView, UITextViewDelegate, LiveTextDisplay {
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
    /// Live text sync (protocol 17).
    weak var sync: LiveTextSync?
    /// The Mac's text is being put in the field: not an edit.
    private var applyingRemote = false
    /// Whether the keyboard is set up for synced text (owner decision 2).
    private var configuredSynced = false
    /// Undo in synced Live goes to the Mac (⌘Z / ⇧⌘Z).
    private lazy var macUndo = MacUndoManager(
        undo: { [weak self] in self?.onChord(["cmd", "z"]) },
        redo: { [weak self] in self?.onChord(["cmd", "shift", "z"]) }
    )

    /// Live, and the Mac's field is readable: the field holds its text.
    var isSynced: Bool { mode == .live && (sync?.isSynced ?? false) }

    override var undoManager: UndoManager? {
        isSynced ? macUndo : super.undoManager
    }

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
        if newMode == .live, let sync, sync.isSynced {
            applyingRemote = true
            text = sync.text
            selectedRange = Self.nsRange(sync.selection, in: text)
            applyingRemote = false
        }
        configuredSynced = !isSynced // force the next call to apply
        syncStateChanged()
        refreshPlaceholder()
        if isFirstResponder { reloadInputViews() }
    }

    // MARK: - Live text sync

    /// Applies the keyboard and line settings for synced or blind Live.
    func syncStateChanged() {
        let synced = isSynced
        guard synced != configuredSynced else { return }
        configuredSynced = synced
        if mode == .live {
            textContainer.maximumNumberOfLines = synced ? 0 : 1
            textContainer.lineBreakMode = synced ? .byWordWrapping : .byTruncatingHead
        }
        // Owner decision 2: autocorrect and predictions stay on; smart
        // punctuation stays off (set in init); the spell-check underline
        // goes in synced Live (the Mac app checks its own spelling).
        spellCheckingType = synced ? .no : .default
        autocorrectionType = synced ? .yes : .default
        if isFirstResponder { reloadInputViews() }
    }

    func showSynced(text newText: String, selection: TextRange) {
        guard mode == .live, markedTextRange == nil else { return }
        applyingRemote = true
        if text != newText { text = newText }
        selectedRange = Self.nsRange(selection, in: newText)
        applyingRemote = false
        syncStateChanged()
        refreshPlaceholder()
        scrollRangeToVisible(selectedRange)
        undoManager?.removeAllActions()
    }

    func becameBlind() {
        guard mode == .live else { return }
        applyingRemote = true
        committed = ""
        if markedTextRange == nil { text = "" }
        applyingRemote = false
        syncStateChanged()
        refreshPlaceholder()
    }

    private static func nsRange(_ range: TextRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let start = min(max(0, range.start), length)
        return NSRange(location: start, length: min(max(0, range.length), length - start))
    }

    private var currentSelection: TextRange {
        TextRange(start: selectedRange.location, length: selectedRange.length)
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
        if isSynced, let sync {
            guard !applyingRemote else { return }
            let current = text ?? ""
            // A latched modifier turns the next letter into a chord (⌘C).
            let change = TextEdit.between(sync.text, current)
            if markedTextRange == nil, !latchedModifiers.isEmpty, change.range.length == 0,
               change.replacement.count == 1, let character = change.replacement.first {
                let name = String(character).lowercased()
                if KeyTable.keyCode(for: name) != nil {
                    showSynced(text: sync.text, selection: sync.selection)
                    onChord(KeyModifier.pressOrder.filter(latchedModifiers.contains).map(\.wireName) + [name])
                    onModifiersUsed()
                    return
                }
            }
            // Composing (marked text): the reconciler holds it until commit.
            sync.localChange(text: current, selection: currentSelection, composing: markedTextRange != nil)
            macUndo.removeAllActions()
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
        // Synced Live: the caret is free. A tap, the space-bar trackpad or
        // the selection handles move the Mac's caret too.
        if isSynced, let sync {
            guard !applyingRemote, markedTextRange == nil else { return }
            // UIKit reports a typed character's caret before the text
            // (`textViewDidChangeSelection` before `textViewDidChange`):
            // with the field's text, the reconciler tells a caret move
            // from the start of an edit (build 29 bug 9).
            sync.localSelection(currentSelection, fieldText: text ?? "")
            return
        }
        // Blind Live keeps the caret at the end: the Mac's cursor can't follow a
        // caret moved here, so edits always apply at the end.
        guard mode == .live, markedTextRange == nil else { return }
        let end = (text as NSString?)?.length ?? 0
        if selectedRange.location != end || selectedRange.length != 0 {
            selectedRange = NSRange(location: end, length: 0)
        }
    }

    override func deleteBackward() {
        // Live, nothing left here to delete: delete on the Mac anyway.
        if mode == .live, !isSynced, markedTextRange == nil, (text ?? "").isEmpty {
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


/// Synced Live's undo manager: the field keeps no undo of its own (the
/// Mac's text replaces it), so undo and redo, from the shake, the
/// three-finger swipe or the edit menu, go to the Mac as ⌘Z / ⇧⌘Z.
final class MacUndoManager: UndoManager {
    private let onUndo: () -> Void
    private let onRedo: () -> Void

    init(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        onUndo = undo
        onRedo = redo
        super.init()
        groupsByEvent = true
    }

    override var canUndo: Bool { true }
    override var canRedo: Bool { true }
    override var undoActionName: String { "on the Mac" }
    override var redoActionName: String { "on the Mac" }
    override func undo() { onUndo() }
    override func redo() { onRedo() }
}
