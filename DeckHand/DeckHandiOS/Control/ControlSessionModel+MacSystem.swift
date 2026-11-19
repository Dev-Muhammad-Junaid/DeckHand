//
//  ControlSessionModel+MacSystem.swift
//  DeckHandiOS
//
//  The Mac system control lane's part of the session model: the Mac's lock
//  state and its displays / Spaces snapshot (`system.lockState`,
//  `system.displayState`, protocol 3).
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
        case .run, .switchSpace:
            break // remote → Mac only
        }
    }
}
