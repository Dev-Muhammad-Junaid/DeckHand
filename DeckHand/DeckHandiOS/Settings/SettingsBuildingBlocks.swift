//
//  SettingsBuildingBlocks.swift
//  DeckHandiOS
//
//  Shared pieces of the Settings screen, restyled to the Pixel Hand design
//  system (`07-Polish-Spec.md` §2–§7 "Settings", board `v2Settings`):
//
//    .phSettingsSection()     raised rows, token hairlines, on the canvas
//    SettingsSectionHeader    header with an optional glyph
//    SettingsRowIcon          the 30 pt navy glyph tile that leads a row
//    SettingsRow              icon tile, title, subtitle, trailing value
//    SettingsValueText        a trailing value in tabular figures
//    SettingBlock             a titled control (segmented picker, slider)
//    SettingsVersionLine      the dot-matrix version line
//
//  Section files owned by other lanes adopt these with one-line changes;
//  the list's colours come from `SettingsView`, so they need none.
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

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            // Huge type: the value goes under the title instead of
            // squeezing it (`07-Polish-Spec.md` §6).
            let layout = typeSize.typeBand == .huge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: PixelHandTheme.Space.xs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PixelHandTheme.Space.sm))
            layout {
                Text(title)
                    .foregroundStyle(PixelHandTheme.ink)
                if let value {
                    if typeSize.typeBand != .huge { Spacer(minLength: PixelHandTheme.Space.sm) }
                    SettingsValueText(value)
                }
            }
            content
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, PixelHandTheme.Space.xs)
    }
}

// MARK: - List styling

extension View {
    /// The Settings list's row style: `raised` rows with token hairlines.
    /// Applied by `SettingsView` to every section, so section files don't
    /// need it.
    func phSettingsSection() -> some View {
        self
            .listRowBackground(PixelHandTheme.raised)
            .listRowSeparatorTint(PixelHandTheme.hairline)
    }

    /// The Settings list's container: canvas behind grouped sections,
    /// accent tint for pickers and sliders, success for switches.
    func phSettingsList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(PixelHandTheme.canvas)
            .tint(PixelHandTheme.accent)
            .toggleStyle(SwitchToggleStyle(tint: PixelHandTheme.success))
            .listSectionSpacing(PixelHandTheme.Space.xl)
            .environment(\.defaultMinListRowHeight, PixelHandTheme.ControlHeight.primary)
    }
}

// MARK: - Headers, icons, rows

/// A section header: small semibold `ink2` title, optional glyph at pitch
/// 1.6. One line in each section file: `header: { SettingsSectionHeader("Live mirror", glyph: PixelGlyphs.screen) }`.
struct SettingsSectionHeader: View {
    let title: String
    var glyph: GlyphBitmap?

    init(_ title: String, glyph: GlyphBitmap? = nil) {
        self.title = title
        self.glyph = glyph
    }

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            if let glyph {
                PHGlyph(glyph: glyph, pitch: 1.6)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PixelHandTheme.ink2)
                .textCase(.uppercase)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// The 30 pt navy tile with a pixel glyph that leads a Settings row
/// (board `.rowic`). Replaces SF Symbols in rows.
struct SettingsRowIcon: View {
    let glyph: GlyphBitmap
    var isLit = false

    var body: some View {
        PHGlyph(glyph: glyph, pitch: 2, accent: PixelHandTheme.Brand.glow)
            .foregroundStyle(isLit ? PixelHandTheme.Brand.phosphor : Color(red: 0.81, green: 0.88, blue: 1))
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [PixelHandTheme.Brand.screenRaised, PixelHandTheme.Brand.screen], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                    .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline)
            )
            .pixelOnNavy()
            .accessibilityHidden(true)
    }
}

/// A trailing value: `ink2`, tabular figures so updating numbers don't
/// jitter.
struct SettingsValueText: View {
    let value: String

    init(_ value: String) { self.value = value }

    var body: some View {
        Text(value)
            .foregroundStyle(PixelHandTheme.ink2)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// A Settings row: glyph tile, title with an optional subtitle, and any
/// trailing content (a value, a badge, a switch). At huge type sizes the
/// trailing content moves under the title.
struct SettingsRow<Trailing: View>: View {
    let glyph: GlyphBitmap?
    let title: String
    var subtitle: String?
    var isLit = false
    @ViewBuilder let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, glyph: GlyphBitmap? = nil, subtitle: String? = nil, isLit: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.glyph = glyph
        self.subtitle = subtitle
        self.isLit = isLit
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PixelHandTheme.Space.md) {
            if let glyph, typeSize.typeBand != .huge {
                SettingsRowIcon(glyph: glyph, isLit: isLit)
            }
            let layout = typeSize.typeBand == .huge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: PixelHandTheme.Space.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: PixelHandTheme.Space.sm))
            layout {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
                    Text(title)
                        .foregroundStyle(PixelHandTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(PixelHandTheme.ink2)
                    }
                }
                if typeSize.typeBand != .huge { Spacer(minLength: PixelHandTheme.Space.sm) }
                trailing
            }
        }
        .padding(.vertical, PixelHandTheme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, glyph: GlyphBitmap? = nil, subtitle: String? = nil, isLit: Bool = false) {
        self.init(title, glyph: glyph, subtitle: subtitle, isLit: isLit) { EmptyView() }
    }
}

/// The dot-matrix version line at the foot of Settings, with a spoken label.
struct SettingsVersionLine: View {
    private var version: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    private var build: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }

    var body: some View {
        DotMatrixText(
            VersionLine.text(version: version, build: build),
            pitch: 1.4,
            label: VersionLine.spoken(version: version, build: build)
        )
        .foregroundStyle(PixelHandTheme.ink3)
        .frame(maxWidth: .infinity)
        .padding(.vertical, PixelHandTheme.Space.xl)
    }
}
