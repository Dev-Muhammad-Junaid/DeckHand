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

    var body: some View {
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
                    .padding(.leading, PixelHandTheme.Space.md)
                    .padding(.trailing, PixelHandTheme.Space.xl)
                }
                .mask { TrailingFade(width: PixelHandTheme.Space.xl) }
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
            .accessibilityLabel(isKeyboardShown ? "Hide keyboard" : "Keyboard")
            .accessibilityAddTraits(isKeyboardShown ? .isSelected : [])
            .padding(.trailing, PixelHandTheme.Space.xs)
        }
        .frame(height: PixelHandTheme.ControlHeight.dock)
        .phGlass(in: Capsule())
    }
}

/// One app: 36 pt icon, running dot under it, 44 pt target.
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
            VStack(spacing: 4) {
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
                runningDot
            }
            .frame(minWidth: PixelHandTheme.ControlHeight.hit, minHeight: PixelHandTheme.ControlHeight.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle())
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
        .accessibilityShowsLargeContentViewer {
            Label {
                Text(app.displayName)
            } icon: {
                AppIconTile(app: app, side: iconSide)
            }
        }
    }

    private var runningDot: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(entry.isFront ? PixelHandTheme.Brand.mint : PixelHandTheme.ink3)
            .frame(width: 4, height: 4)
            .shadow(color: entry.isFront ? PixelHandTheme.Brand.mint.opacity(0.9) : .clear, radius: entry.isFront ? 2.5 : 0)
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
