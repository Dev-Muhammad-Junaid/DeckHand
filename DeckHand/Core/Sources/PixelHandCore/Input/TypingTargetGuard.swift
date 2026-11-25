//
//  TypingTargetGuard.swift
//  PixelHandCore
//
//  Keys go to whatever app is in front on the Mac (VQ-036). The keyboard
//  bar names that app, and a Return pressed after the front app changed
//  under the person, to one they haven't typed into yet, asks first: one
//  Return can send a message in a chat app.
//
//  Pure, so it is tested here; the keyboard bar holds one.
//

import Foundation

public struct TypingTargetGuard: Equatable, Sendable {
    /// The app the person last typed into (or confirmed).
    public private(set) var acknowledgedApp: String?

    public init() {}

    /// The person typed text while `app` was in front: it is the app they
    /// mean.
    public mutating func typed(into app: String?) {
        guard let app, !app.isEmpty else { return }
        acknowledgedApp = app
    }

    /// The person confirmed sending to `app`.
    public mutating func confirmed(_ app: String?) {
        typed(into: app)
    }

    /// Whether a Return should ask first: the front app is known, differs
    /// from the one typed into, and something was typed before. The first
    /// key of a session never asks.
    public func shouldConfirmReturn(frontApp: String?) -> Bool {
        guard let frontApp, !frontApp.isEmpty, let acknowledgedApp else { return false }
        return frontApp != acknowledgedApp
    }

    /// The keyboard bar's line: "Typing into Messages", or a neutral line
    /// when the Mac hasn't said.
    public static func caption(frontApp: String?) -> String {
        guard let frontApp, !frontApp.isEmpty else { return "Typing goes to the app in front on the Mac" }
        return "Typing into \(frontApp)"
    }
}
