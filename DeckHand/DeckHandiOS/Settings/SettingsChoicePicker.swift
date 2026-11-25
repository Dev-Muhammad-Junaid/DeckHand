//
//  SettingsChoicePicker.swift
//  DeckHandiOS – Settings
//
//  Settings' few-choice pickers (frame rate, send rate, quality, theme,
//  haptics): segmented at the Standard and Large bands; at the Huge band a
//  menu, whose rows grow with the text, since segments stayed small at AX3
//  while the rows around them grew (build 23, VQ-089;
//  `SettingsPickerPlan`).
//

import PixelHandCore
import SwiftUI

private struct SettingsChoicePickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        if SettingsPickerPlan.usesMenu(band: typeSize.typeBand) {
            content
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

extension View {
    /// Segmented, or a menu at the Huge band (VQ-089).
    func settingsChoicePickerStyle() -> some View {
        modifier(SettingsChoicePickerStyle())
    }
}
