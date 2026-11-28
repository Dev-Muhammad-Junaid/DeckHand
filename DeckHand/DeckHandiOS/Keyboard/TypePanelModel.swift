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
import PixelHandCore
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
    /// How far the app dock rises to sit on the iPadOS keyboard bar (a
    /// hardware or minimised keyboard's slim bar; 0 under a full keyboard,
    /// OT-11).
    private(set) var dockLift: Double = 0
    /// The last keyboard end frame, in screen space (`nil` once hidden).
    @ObservationIgnored private var keyboardScreenFrame: CGRect?
    /// What the keyboard notifications last said (`nil` before any, or
    /// once the keyboard hid).
    @ObservationIgnored private var notificationReading: KeyboardFrameReading.Reading?
    /// What UIKit's keyboard layout guide last said (build 30 bug 1;
    /// `KeyboardGuideReader`), `nil` before it was laid out.
    @ObservationIgnored private var guideReading: KeyboardFrameReading.Reading?
    /// The key window's bottom safe area (the home indicator), for the
    /// dock's lift.
    @ObservationIgnored private var bottomInset: Double = 0
    /// The app dock's top in global coordinates, while it shows under the
    /// panel; the panel sits above it when no keyboard covers the dock.
    var dockMinY: CGFloat?

    static let modeKey = "pixelhand.type.mode"

    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        presence = TypePanelPresence(mode: TypeMode.restored(UserDefaults.standard.string(forKey: Self.modeKey)))
        hardwareKeyboardAttached = GCKeyboard.coalesced != nil
        let center = NotificationCenter.default
        // Will and Did both: on rotation the Will can arrive while the
        // window still has its old bounds, which put the keyboard below a
        // portrait window and the panel behind it (build 25 bug 1). The
        // Did carries the same end frame once the window has turned.
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                MainActor.assumeIsolated { self?.keyboardFrameChanged(frame) }
            })
        }
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keyboardScreenFrame = nil
                self?.notificationReading = nil
                self?.applyReadings()
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
        keyboardScreenFrame = screenFrame
        refreshKeyboard()
    }

    /// Measures the last keyboard frame against the window as it is now.
    /// The host calls it when the window's size changes (rotation, Stage
    /// Manager), so a frame reported before the window turned is read
    /// again against the turned window.
    func refreshKeyboard() {
        guard let screenFrame = keyboardScreenFrame,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first
        else {
            notificationReading = nil
            applyReadings()
            return
        }
        bottomInset = Double(window.safeAreaInsets.bottom)
        // Build 28 bug 6 (P1): in iPad landscape the conversion against
        // the screen's interface-oriented space could come back turned a
        // quarter, so the keyboard read as none and the panel drew under
        // it. Every conversion is tried; Core keeps the one that reads as
        // a keyboard in this window (wider than tall, shorter than the
        // window), and a frame that reads as none leaves the last reading.
        let screen = window.windowScene?.screen ?? window.screen
        let candidates = [
            window.convert(screenFrame, from: screen.coordinateSpace),
            window.convert(screenFrame, from: screen.fixedCoordinateSpace),
            window.convert(screenFrame, from: nil as UIWindow?),
            screenFrame,
        ].map { PanelRect(x: Double($0.minX), y: Double($0.minY), width: Double($0.width), height: Double($0.height)) }
        guard let reading = KeyboardFrameReading.read(
            candidates,
            windowWidth: Double(window.bounds.width),
            windowHeight: Double(window.bounds.height)
        ) else {
            applyReadings()
            return
        }
        notificationReading = reading
        applyReadings()
    }

    /// UIKit's keyboard layout guide, measured in the window by
    /// `KeyboardGuideReader` (build 30 bug 1, P1). It is laid out again
    /// whenever the keyboard moves, so it holds the keyboard's top even
    /// when a notification is missed, arrives for the old orientation, or
    /// converts wrongly (iPad portrait, when Live's field took focus).
    func keyboardGuideChanged(_ reading: KeyboardFrameReading.Reading?, bottomInset inset: Double) {
        if inset.isFinite { bottomInset = max(0, inset) }
        guard reading != guideReading else { return }
        guideReading = reading
        applyReadings()
    }

    /// The keyboard as both sources see it (Core's `merged`): covered when
    /// either says so, up to the higher top.
    private func applyReadings() {
        let merged = KeyboardFrameReading.merged([notificationReading, guideReading])
        var overlap = 0.0
        var top: Double?
        if case let .covers(t, o)? = merged {
            overlap = o
            top = t
        }
        if keyboardOverlap != overlap { keyboardOverlap = overlap }
        if keyboardMinY != top { keyboardMinY = top }
        let lift = KeyboardKind.barLift(overlap: overlap, bottomInset: bottomInset)
        if dockLift != lift { dockLift = lift }
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
