//
//  SettingsPickerPlan.swift
//  PixelHandCore
//
//  Settings' few-choice pickers. Segmented controls don't grow with
//  Dynamic Type, so at AX3 they stayed small while the rows around them
//  grew (build 23, VQ-089). At the Huge band they become menus.
//

import Foundation

public enum SettingsPickerPlan {
    public static func usesMenu(band: TypeBand) -> Bool {
        band == .huge
    }
}
