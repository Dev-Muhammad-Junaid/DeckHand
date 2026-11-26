//
//  ControlSessionModel+MacSystem.swift
//  DeckHandiOS
//
//  The Mac system control lane's part of the session model: the Mac's lock
//  state and its displays / Spaces snapshot (`system.lockState`,
//  `system.displayState`, protocol 3), and the focused text field while
//  the Type panel's loupe watches it (`system.focusState`, protocol 16).
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
        case .run, .switchSpace, .watchFocus:
            break // remote → Mac only
        }
    }
}
