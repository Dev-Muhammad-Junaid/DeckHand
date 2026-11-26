//
//  ControlSessionModel+MacSystem.swift
//  DeckHandiOS
//
//  The Mac system control lane's part of the session model: the Mac's lock
//  state and its displays / Spaces snapshot (`system.lockState`,
//  `system.displayState`, protocol 3), and the focused text field while
//  the Type panel's loupe watches it (`system.focusState`, protocol 16),
//  and its text while the Live field is open (`system.textState`,
//  `system.textEditResult`, protocol 17).
//

import SwiftUI

extension ControlSessionModel {
    func handleSystemMessage(_ message: SystemMessage) {
        switch message {
        case let .lockState(state):
            DeckHandLog.connection.info("Mac lock state: \(state.rawValue, privacy: .public)")
            withAnimation(.easeInOut(duration: 0.2)) {
                macLockState = state
            }
        case let .displayState(layout):
            displayLayout = layout
        case let .focusState(focus):
            focusedField = focus
        case let .textState(state):
            liveText.receive(state)
        case let .textEditResult(result):
            liveText.receive(result)
        case .run, .switchSpace, .watchFocus:
            break // remote → Mac only
        }
    }

    /// The Type panel's Live field opened (`true`) or closed / left the
    /// screen: the Mac sends its focused field's text only while it's
    /// open (`watchFocus(wantsText:)`), so nothing is read otherwise.
    func setLiveTextWanted(_ wanted: Bool) {
        guard liveTextWanted != wanted else { return }
        liveTextWanted = wanted
        if !wanted { liveText.reset() }
        updateFocusWatch()
    }

    /// One `watchFocus` for the loupe (geometry) and the Live field
    /// (geometry and text).
    func updateFocusWatch() {
        liveText.sender = sender
        guard let sender else { return }
        let on = mirrorLoupeActive || liveTextWanted
        let wantsText = liveTextWanted
        Task { await sender.watchFocus(on, wantsText: wantsText) }
    }
}
