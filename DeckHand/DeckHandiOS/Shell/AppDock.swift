//
//  AppDock.swift
//  DeckHandiOS – Shell
//
//  The app dock (UX-005): the Mac's running apps on a glass capsule, 56 pt,
//  drawn like the macOS Dock (owner testing, build 24, OT-1): each app is
//  its real icon shape with nothing behind it (the Mac now sends icons
//  with transparency, `AppIconPolicy`), the front app has a small accent
//  dot under its icon instead of a ring box, a press dips the icon
//  slightly, and an app that's showing a dialog has a warning dot. A
//  hairline, then the keyboard button, which sits in the dock so the
//  keyboard can never cover its own toggle.
//
//  The row shows whole icons only (`AppDockFit`): it snaps its width to a
//  whole number of slots, rests on whole icons when scrolled, and fades
//  its end when more apps wait past it.
//
//  Tap brings an app to the front on the Mac. Touch and hold (or the
//  VoiceOver actions): Bring to front, Shortcuts, Hide, Quit. Order comes
//  from `AppDockPlan` (stable slots, new apps at the end).
//  Spec: `02-Design-System.md` §7 `AppDock`, `04-Interaction-Model.md` §2,
//  board `.adock`.
//

import SwiftUI
import UIKit

struct AppDock: View {
    let entries: [AppDockEntry]
    let apps: [String: InstalledAppInfo]
    var isKeyboardShown = false
    let onActivate: (InstalledAppInfo) -> Void
    let onShortcuts: (InstalledAppInfo) -> Void
    let onHide: (InstalledAppInfo) -> Void
    let onQuit: (InstalledAppInfo) -> Void
    let onKeyboard: () -> Void

    /// The room the app row may take, measured; the row then snaps to
    /// whole icons (`AppDockFit`, VQ-039).
    @State private var rowAvailable: CGFloat = 0

    private var shownCount: Int {
        entries.filter { apps[$0.bundleID] != nil }.count
    }

    var body: some View {
        let fit = AppDockFit.row(available: Double(rowAvailable), count: max(shownCount, 1))
        HStack(spacing: PixelHandTheme.Space.xs) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CGFloat(AppIconPolicy.dockSpacing)) {
                        // UX-018: never an empty capsule. The dot wave until
                        // the Mac's app list arrives, then a quiet line.
                        if !entries.contains(where: { apps[$0.bundleID] != nil }) {
                            Group {
                                if apps.isEmpty {
                                    DotWave(pitch: 3, label: "Loading apps")
                                } else {
                                    DotMatrixText("NO APPS OPEN", pitch: 1.4, label: "No apps open", glows: false)
                                        .foregroundStyle(PixelHandTheme.ink3)
                                }
                            }
                            .frame(height: PixelHandTheme.ControlHeight.hit)
                        }
                        ForEach(entries) { entry in
                            if let app = apps[entry.bundleID] {
                                DockApp(
                                    app: app,
                                    entry: entry,
                                    onActivate: { onActivate(app) },
                                    onShortcuts: { onShortcuts(app) },
                                    onHide: { onHide(app) },
                                    onQuit: { onQuit(app) }
                                )
                                .id(entry.bundleID)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, CGFloat(AppDockFit.inset), for: .scrollContent)
                // Rests on whole icons; the row shows whole slots only, and
                // fades its end when more apps wait past it.
                .scrollTargetBehavior(.viewAligned)
                .mask {
                    if fit.overflows {
                        TrailingFade(width: PixelHandTheme.Space.lg)
                    } else {
                        Rectangle()
                    }
                }
                .frame(width: rowAvailable > 0 && shownCount > 0 ? CGFloat(fit.width) : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowAvailable = $0 }
                .onChange(of: entries.first(where: \.isFront)?.bundleID) { _, front in
                    guard let front else { return }
                    withAnimation(PixelHandMotion.standard) { reader.scrollTo(front) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Apps running on the Mac")

            Rectangle()
                .fill(PixelHandTheme.hairline)
                .frame(width: 1, height: 28)
                .padding(.horizontal, PixelHandTheme.Space.xs)
                .accessibilityHidden(true)

            Button(action: onKeyboard) {
                PHGlyph(glyph: PixelGlyphs.keyboard, pitch: 1.8)
                    .foregroundStyle(isKeyboardShown ? PixelHandTheme.accent : PixelHandTheme.ink)
                    .frame(width: PixelHandTheme.ControlHeight.secondary, height: PixelHandTheme.ControlHeight.secondary)
                    .background(isKeyboardShown ? PixelHandTheme.accentTint : PixelHandTheme.fill, in: Circle())
                    .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                    .contentShape(Circle())
            }
            .buttonStyle(ChipPressStyle())
            .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.hit / 2)
            .accessibilityLabel(isKeyboardShown ? "Hide keyboard" : "Show keyboard")
            .accessibilityAddTraits(isKeyboardShown ? .isSelected : [])
            .accessibilityIdentifier("ph.dock.keyboard")
            .padding(.trailing, PixelHandTheme.Space.xs)
        }
        .frame(height: PixelHandTheme.ControlHeight.dock)
        .phGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.dock")
    }
}

/// One app: the 36 pt icon with no plate, a 44 pt target, and the
/// macOS-style indicator: a 4 pt accent dot under the front app.
private struct DockApp: View {
    let app: InstalledAppInfo
    let entry: AppDockEntry
    let onActivate: () -> Void
    let onShortcuts: () -> Void
    let onHide: () -> Void
    let onQuit: () -> Void

    private let iconSide = CGFloat(AppIconPolicy.dockIconSide)

    var body: some View {
        Button {
            GestureHaptic.medium.trigger()
            onActivate()
        } label: {
            AppIconTile(app: app, side: iconSide)
                .overlay(alignment: .topTrailing) {
                    if entry.hasDialog {
                        StatusPixel(state: .needsYou, size: 8)
                            .padding(2)
                            .background(PixelHandTheme.canvas, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .offset(x: 5, y: -5)
                    }
                }
                // The front app: a small dot under the icon in the accent
                // colour, like the Mac's own Dock (OT-1).
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(PixelHandTheme.accent)
                        .frame(width: CGFloat(AppIconPolicy.frontDotSide), height: CGFloat(AppIconPolicy.frontDotSide))
                        .offset(y: CGFloat(AppIconPolicy.frontDotGap + AppIconPolicy.frontDotSide))
                        .opacity(entry.isFront ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(DockIconPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd + 4)
        .animation(PixelHandMotion.standard, value: entry.isFront)
        .contextMenu {
            Button("Bring to front", action: onActivate)
            Button("Shortcuts", action: onShortcuts)
            Divider()
            Button("Hide", action: onHide)
            Button("Quit", role: .destructive, action: onQuit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(entry.isFront ? .isSelected : [])
        .accessibilityHint("Brings it to the front on the Mac.")
        .accessibilityAction(named: "Shortcuts", onShortcuts)
        .accessibilityAction(named: "Hide", onHide)
        .accessibilityAction(named: "Quit", onQuit)
        .accessibilityIdentifier("ph.dock.app")
        .accessibilityShowsLargeContentViewer {
            Label {
                Text(app.displayName)
            } icon: {
                AppIconTile(app: app, side: iconSide)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [app.displayName]
        if entry.isFront { parts.append("in front") }
        if entry.hasDialog { parts.append("showing a dialog") }
        return parts.joined(separator: ", ")
    }
}

/// A dock icon's press: a small dip in scale and a touch of fade, with no
/// plate appearing behind the icon (OT-1).
private struct DockIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? CGFloat(AppIconPolicy.pressedScale) : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(PixelHandMotion.quick, value: configuration.isPressed)
    }
}

/// The Mac's icon for an app, drawn as its own shape with nothing behind
/// it (the Mac sends it with transparency, OT-1), or, when the Mac didn't
/// send one, an icon-shaped stand-in with its initial.
struct AppIconTile: View {
    let app: InstalledAppInfo
    var side: CGFloat = 36

    var body: some View {
        Group {
            if let data = app.iconData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                // macOS icons sit on a 22 % rounded square inside a small
                // margin; the stand-in follows that shape.
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(PixelHandTheme.Brand.screenGradient)
                    .overlay(
                        Text(String(app.displayName.prefix(1)).uppercased())
                            .font(.phDisplay(.headline))
                            .foregroundStyle(PixelHandTheme.Brand.phosphor)
                    )
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Fades the last `width` points of a scrolling row, so a row that runs on
/// reads as "more this way" (board `.fade-r`). Build 23 (VQ-034, VQ-088):
/// 16–24 pt fades went unseen at a mid-label cut, so rows use
/// `overflowWidth`, about one key, with the same trailing padding so a row
/// that fits shows no fade at all.
struct TrailingFade: View {
    /// The fade every scrolling row uses (and its trailing padding).
    static let overflowWidth: CGFloat = 48

    var width: CGFloat = overflowWidth

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
        }
    }
}

#Preview("App dock") {
    let apps = [
        InstalledAppInfo(bundleID: "a", displayName: "Xcode", iconData: nil),
        InstalledAppInfo(bundleID: "b", displayName: "Safari", iconData: nil),
        InstalledAppInfo(bundleID: "c", displayName: "Terminal", iconData: nil),
        InstalledAppInfo(bundleID: "d", displayName: "Music", iconData: nil),
    ]
    let lookup = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })
    let entries = AppDockPlan.entries(order: ["a", "b", "c", "d"], known: Set(lookup.keys), front: "a", frontHasDialog: true)
    return VStack {
        Spacer()
        AppDock(entries: entries, apps: lookup, onActivate: { _ in }, onShortcuts: { _ in }, onHide: { _ in }, onQuit: { _ in }, onKeyboard: {})
            .padding(.horizontal, 12)
    }
    .background(.phCanvas)
}
