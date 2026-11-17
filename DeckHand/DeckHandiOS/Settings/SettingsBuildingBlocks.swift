//
//  SettingsBuildingBlocks.swift
//  DeckHandiOS
//
//  Shared pieces of the Settings screen: the opaque navigation bar and the
//  titled control block.
//

import SwiftUI

/// Keeps scrolled rows from showing through the "Settings" title.
///
/// In a sheet the inline bar is transparent until content scrolls under it,
/// and on iOS 26 its soft scroll-edge blur let glass controls such as the
/// segmented pickers read straight through the title in dark mode. A
/// visible bar background, plus a hard scroll edge on iOS 26, keeps the
/// title on a solid surface in both appearances.
struct OpaqueSettingsBar: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
                .toolbarBackground(.visible, for: .navigationBar)
        }
        #else
        content
            .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }
}

/// A titled control. Segmented pickers and sliders lose their `Picker` label
/// inside a `Form`, so the title is drawn explicitly above the control.
struct SettingBlock<Content: View>: View {
    let title: String
    var value: String?
    var caption: String?
    @ViewBuilder let content: Content

    init(
        _ title: String,
        value: String? = nil,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                if let value {
                    Spacer()
                    Text(value)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
