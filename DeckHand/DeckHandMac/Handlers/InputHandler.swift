//
//  InputHandler.swift
//  DeckHandMac
//
//  Domain: input. Pointer, scroll, clicks, drags, key chords, typed text
//  and media keys, posted through `InputInjector`. Owned by the iOS
//  interaction lane. Typed text and chords go through `TypingQueue` so a
//  chord never overtakes the text before it; held buttons through
//  `DragGuard`, which releases them if the remote vanishes.
//

import AppKit
import LoomKit

@MainActor
final class InputHandler: DomainHandler {
    private let injector = InputInjector.shared

    func handle(_ message: InputMessage, from connection: LoomConnectionHandle) async {
        MenuBarActivity.shared.noteInput() // UX Mac lane: the menu-bar hand's "being controlled" state
        switch message {
        case let .mouseDelta(dx, dy):
            injector.moveCursor(dx: dx, dy: dy)

        case let .mouseScroll(dx, dy, phase):
            injector.scroll(dx: dx, dy: dy, phase: Self.injectorPhase(for: phase))

        case let .mouseClick(button):
            injector.click(button: button)

        case let .mouseDoubleClick(button):
            injector.click(button: button, double: true)

        case let .mouseDown(button):
            DragGuard.shared.mouseDown(button, from: connection.id)

        case let .mouseUp(button):
            DragGuard.shared.mouseUp(button, from: connection.id)

        case let .keyboardShortcut(keys):
            // Live text sync: behind an edit still being placed or typed.
            FocusTextSync.shared.inOrder { TypingQueue.shared.shortcut(keys) }

        case let .typeText(text):
            FocusTextSync.shared.inOrder { TypingQueue.shared.type(text) }

        case let .textEdit(edit):
            // Live text sync (protocol 17): select, then type; never AXValue.
            FocusTextSync.shared.edit(edit, from: connection)

        case let .textSelect(selection):
            FocusTextSync.shared.select(selection, from: connection)

        case let .caretMove(move):
            FocusTextSync.shared.caretMove(move)

        case let .media(key):
            switch key {
            case .playPause: injector.sendMediaKey(NX_KEYTYPE_PLAY)
            case .next:      injector.sendMediaKey(NX_KEYTYPE_NEXT)
            case .previous:  injector.sendMediaKey(NX_KEYTYPE_PREVIOUS)
            }
        }
    }

    /// Bridge from the Shared wire enum to the Mac-internal `InputInjector`
    /// phase. We keep them as separate types so the iOS target doesn't
    /// pull in `InputInjector` and the Mac internals stay free to evolve.
    private static func injectorPhase(for phase: ScrollPhase) -> InputInjector.ScrollPhase {
        switch phase {
        case .begin:           return .begin
        case .changed:         return .changed
        case .end:             return .end
        case .momentumBegin:   return .momentumBegin
        case .momentumChanged: return .momentumChanged
        case .momentumEnd:     return .momentumEnd
        }
    }
}
