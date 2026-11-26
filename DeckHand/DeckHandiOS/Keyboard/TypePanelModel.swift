//
//  TypePanelModel.swift
//  DeckHandiOS – Keyboard
//
//  The one owner of "the Type panel is open" (owner testing, build 24,
//  OT-2). The shell makes one per window and hands it down the
//  environment; the dock's keyboard button, the pad's keyboard button and
//  the lock banner's Keyboard button all go through it, and the shell
//  draws the panel in one place from it, so the panel (and the text field
//  that holds the keyboard) keeps one identity whatever the arrangement.
//
//  It also follows the keyboard: how much of the window the on-screen
//  keyboard covers (keyboard frame notifications, converted to the
//  window) and whether a hardware keyboard is attached (GameController's
//  `GCKeyboard`, public API), which `TypePanelLayout` turns into the full
//  panel or the keys row only. The arrangement never reads any of this:
//  the shell plans from the window (`ShellPlanningSize`).
//

import GameController
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class TypePanelModel {
    /// Open/closed, tab, mode, fn row and the sticky modifiers (Core).
    var presence: TypePanelPresence

    /// Live or Compose, remembered for next time.
    var mode: TypeMode {
        get { presence.mode }
        set {
            guard newValue != presence.mode else { return }
            presence.mode = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey)
        }
    }

    /// Compose's draft (kept while the panel is closed, so nothing typed is
    /// lost).
    var draft = ""
    /// Compose: Send adds a Return after the text.
    var sendsReturn = false

    /// How many points of the window's bottom the on-screen keyboard
    /// covers (0 when none, floating or undocked).
    private(set) var keyboardOverlap: Double = 0
    /// The on-screen keyboard's top in window coordinates (SwiftUI's
    /// `.global`), while it covers the window.
    private(set) var keyboardMinY: Double?
    private(set) var hardwareKeyboardAttached = false
    /// The app dock's top in global coordinates, while it shows under the
    /// panel; the panel sits above it when no keyboard covers the dock.
    var dockMinY: CGFloat?

    static let modeKey = "pixelhand.type.mode"

    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        presence = TypePanelPresence(mode: TypeMode.restored(UserDefaults.standard.string(forKey: Self.modeKey)))
        hardwareKeyboardAttached = GCKeyboard.coalesced != nil
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            MainActor.assumeIsolated { self?.keyboardFrameChanged(frame) }
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keyboardOverlap = 0
                self?.keyboardMinY = nil
            }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hardwareKeyboardAttached = true }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hardwareKeyboardAttached = GCKeyboard.coalesced != nil }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Reading

    var isShown: Bool { presence.isShown }

    /// What covers the window now.
    var keyboard: KeyboardKind {
        KeyboardKind.classify(overlap: keyboardOverlap, hardwareAttached: hardwareKeyboardAttached)
    }

    // MARK: Buttons

    func toggle() {
        GestureHaptic.light.trigger()
        presence.toggle()
    }

    func open() { presence.open() }

    func close() { presence.close() }

    /// Fold to the pill (OT-6); the keyboard steps down.
    func collapse() { presence.collapse() }

    /// Open the pill back up.
    func expand() { presence.expand() }

    var isCollapsed: Bool { presence.isCollapsed }

    // MARK: Keyboard frame

    /// The keyboard's end frame (screen space) against the key window.
    private func keyboardFrameChanged(_ screenFrame: CGRect?) {
        guard let screenFrame,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first
        else {
            keyboardOverlap = 0
            keyboardMinY = nil
            return
        }
        let frame = window.convert(screenFrame, from: window.screen.coordinateSpace)
        keyboardOverlap = KeyboardKind.overlap(
            windowMaxY: Double(window.bounds.maxY),
            keyboardMinY: Double(frame.minY),
            keyboardMaxY: Double(frame.maxY),
            keyboardHeight: Double(frame.height)
        )
        keyboardMinY = keyboardOverlap > 0 ? Double(frame.minY) : nil
    }
}

// MARK: - Environment

private struct TypePanelModelKey: EnvironmentKey {
    static let defaultValue: TypePanelModel? = nil
}

extension EnvironmentValues {
    /// The window's Type panel, set by the shell. `nil` outside it (the
    /// classic layout keeps its own).
    var typePanel: TypePanelModel? {
        get { self[TypePanelModelKey.self] }
        set { self[TypePanelModelKey.self] = newValue }
    }
}
