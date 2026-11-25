//
//  AppDock.swift
//  DeckHandiOS – Shell
//
//  The app dock (UX-005): the Mac's running apps on a glass capsule, 56 pt,
//  with the Mac Dock's running dots (4 pt, `ink3`; the front app's lit mint
//  with a 2 pt accent ring around its icon) and a warning dot on an app
//  that's showing a dialog. A hairline, then the keyboard button, which sits
//  in the dock so the keyboard can never cover its own toggle.
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
                    HStack(spacing: PixelHandTheme.Space.sm) {
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

/// One app: 36 pt icon, 44 pt target. The front app shows by its accent
/// ring only; no dot under it (owner's glyph rule).
private struct DockApp: View {
    let app: InstalledAppInfo
    let entry: AppDockEntry
    let onActivate: () -> Void
    let onShortcuts: () -> Void
    let onHide: () -> Void
    let onQuit: () -> Void

    private let iconSide: CGFloat = 36

    var body: some View {
        Button {
            GestureHaptic.medium.trigger()
            onActivate()
        } label: {
            AppIconTile(app: app, side: iconSide)
                .overlay {
                    if entry.isFront {
                        // 2 pt of canvas, then a 2 pt accent ring.
                        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd + 4, style: .continuous)
                            .strokeBorder(PixelHandTheme.accent, lineWidth: PixelHandTheme.Stroke.selection)
                            .padding(-4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if entry.hasDialog {
                        StatusPixel(state: .needsYou, size: 8)
                            .padding(2)
                            .background(PixelHandTheme.canvas, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .offset(x: 5, y: -5)
                    }
                }
            .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.kbd + 4)
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

/// The Mac's icon for an app, or a neutral tile with its initial when the
/// Mac didn't send one.
struct AppIconTile: View {
    let app: InstalledAppInfo
    var side: CGFloat = 36

    var body: some View {
        Group {
            if let data = app.iconData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
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
/// reads as "more this way" (board `.fade-r`).
struct TrailingFade: View {
    var width: CGFloat = 24

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
