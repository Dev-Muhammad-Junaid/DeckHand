//
//  ContextStripPlan.swift
//  PixelHandCore – Design
//
//  What the context strip shows and in what order (UX-005,
//  `04-Interaction-Model.md` §2 "Context strip", `02-Design-System.md` §7
//  `ContextStrip`):
//
//    1. A dialog on the Mac takes the strip over with its buttons. On compact
//       widths the default button comes first (thumb reach); on wider
//       widths the buttons keep the Mac's order.
//    2. Otherwise the front app's chips (capped), then the text-editing
//       chips when a text field has focus ("append, don't replace").
//    3. With no front app, an idle hint.
//
//  Free tier: the media keys and a dashed "App chips · Pro" chip instead of
//  the app's chips (`04-Interaction-Model.md` §6); dialog buttons stay Pro.
//

import Foundation

public enum ContextStripPlan {
    /// Pixel Hand's own Mac app. Its menu-bar panel comes to the front
    /// whenever someone uses it; the strip, deck and dock keep the app
    /// that was in front before (build 18 QA, VQ-063).
    public static let hostBundleIDs: Set<String> = ["com.widgetsflow.pixelhand.mac"]

    /// Whether a front-app report should replace the current front app:
    /// not when it names Pixel Hand's own Mac app.
    public static func acceptsFrontApp(bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return !hostBundleIDs.contains(bundleID)
    }

    public enum Mode: Hashable, Sendable {
        /// The Mac shows a dialog: its buttons, in strip order.
        case dialog(title: String?, message: String?, buttons: [DialogButton])
        /// The front app's chips, then text editing for `editing` if set.
        case app(chipLimit: Int, editing: TextFieldContext.Kind?)
        /// Nothing is in front yet.
        case idle
        /// Free plan: media keys and the "App chips · Pro" chip.
        case free
    }

    /// The most app chips inline; the rest are one tap away in the app's
    /// shortcuts sheet.
    public static let maxChips = 6
    /// App chips kept when text-editing chips are appended.
    public static let maxChipsWithEditing = 3

    public static func mode(
        context: UIContextSnapshot,
        hasFrontApp: Bool,
        widthClass: LayoutMetrics.WidthClass,
        allowsAppChips: Bool = true
    ) -> Mode {
        guard allowsAppChips else { return .free }
        switch context {
        case .dialog(let dialog) where !dialog.buttons.isEmpty:
            return .dialog(
                title: dialog.title,
                message: dialog.message,
                buttons: buttonOrder(dialog.buttons, defaultFirst: widthClass == .compact)
            )
        case .textField(let field):
            guard hasFrontApp else { return .idle }
            return .app(chipLimit: maxChipsWithEditing, editing: field.kind)
        default:
            return hasFrontApp ? .app(chipLimit: maxChips, editing: nil) : .idle
        }
    }

    /// The dialog's buttons for the strip. `defaultFirst` moves the default
    /// button to the front and keeps the others in the Mac's order.
    public static func buttonOrder(_ buttons: [DialogButton], defaultFirst: Bool) -> [DialogButton] {
        guard defaultFirst, let index = buttons.firstIndex(where: \.isDefault), index != 0 else {
            return buttons
        }
        var ordered = buttons
        let button = ordered.remove(at: index)
        ordered.insert(button, at: 0)
        return ordered
    }

    /// The strip's spoken container label ("Actions for Xcode").
    public static func accessibilityLabel(mode: Mode, appName: String?) -> String {
        switch mode {
        case .dialog(let title, _, _):
            if let title, !title.isEmpty { return "Dialog: \(title)" }
            return "Dialog buttons"
        case .app, .free:
            if let appName, !appName.isEmpty { return "Actions for \(appName)" }
            return "Actions"
        case .idle:
            return "Actions"
        }
    }
}
