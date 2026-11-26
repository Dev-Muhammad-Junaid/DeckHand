//
//  KeyboardAvoidance.swift
//  PixelHandCore
//
//  Keeping a focused row above the on-screen keyboard where the system
//  doesn't (build 26, VQ-104). The shell lays out under the keyboard on
//  purpose (OT-2: the Type panel rides on it), so a scroll view inside the
//  shell, such as Ask in the right column, never learns the keyboard is
//  there. Ask's Save as key then left its Save and Cancel under the
//  keyboard. The view measures itself and adds the overlap as bottom
//  margin, then scrolls the row into view.
//

import Foundation

public enum KeyboardAvoidance {
    /// The bottom margin a scroll view needs so its last row can scroll
    /// above the keyboard: how far the keyboard's top rises over the
    /// view's bottom, plus `gap`. 0 when the keyboard is down or doesn't
    /// reach the view (a sheet the system already lifted). Both in the
    /// window's coordinates.
    public static func bottomInset(viewMaxY: Double, keyboardMinY: Double?, gap: Double = 8) -> Double {
        guard let keyboardMinY, keyboardMinY.isFinite, viewMaxY.isFinite else { return 0 }
        let overlap = viewMaxY - keyboardMinY
        guard overlap > 0 else { return 0 }
        return (overlap + gap).rounded(.up)
    }
}
