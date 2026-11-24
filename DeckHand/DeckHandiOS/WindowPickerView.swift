//
//  WindowPickerView.swift
//  DeckHandiOS
//
//  Modal sheet that shows every visible Mac window from the latest
//  `windowListResponse` so the user can pick one to capture, or to mirror
//  (S14: the live mirror's "Window…" entry).
//
//  Layout: an adaptive `LazyVGrid` so wider devices (iPad, iPhone Pro Max
//  in landscape) see more cells per row and selection stays fast. Cells
//  show the owning app icon + app name + window title.
//
//  Order: most-recently-active first via the parent's `runningBundleIDs`
//  (Cmd+Tab order). Windows whose owning bundle isn't currently in the
//  Mac's running list fall to the end, sorted alphabetically by app name.
//
//  Look (UX-009): the navy stage, a header with the dot-matrix strip
//  (`CAPTURE · 7 WINDOWS`), raised navy cells with a phosphor press flash,
//  the dot wave while the list loads, and an empty state that also covers
//  the locked Mac (which answers with an empty list).
//
//  Tap routing: a `ButtonStyle` exposes press feedback, so we don't need a
//  competing `simultaneousGesture(DragGesture)` — that earlier approach
//  was eating taps inside the sheet, which is why the picker used to feel
//  unresponsive.
//

import SwiftUI
import UIKit

struct WindowPickerView: View {
    let windows: [WindowInfo]
    /// Cmd+Tab-ordered bundle IDs supplied by `RunningAppMonitor` via
    /// `ControlView`. Used purely for sorting; not displayed.
    let runningBundleIDs: [String]
    let isLoading: Bool
    let onPick: (WindowInfo) -> Void
    let onRefresh: () -> Void
    let onCancel: () -> Void
    /// Capture the picked window, or mirror it (S14: the live mirror's
    /// "Window…").
    var purpose: CaptureCoordinator.WindowPickerPurpose = .capture

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 160), spacing: PixelHandTheme.Space.md)
    ]

    private var orderedWindows: [WindowInfo] {
        // Build a rank table from `runningBundleIDs`. Lower index = more
        // recent. Bundles not present rank at `Int.max` so they sort to
        // the end, keeping a stable secondary order by app name + title.
        let rankByBundle = InstalledAppInfo.recencyRank(of: runningBundleIDs)
        return windows.sorted { lhs, rhs in
            let lRank = lhs.bundleID.flatMap { rankByBundle[$0] } ?? .max
            let rRank = rhs.bundleID.flatMap { rankByBundle[$0] } ?? .max
            if lRank != rRank { return lRank < rRank }
            let appCompare = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
            if appCompare != .orderedSame {
                return appCompare == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var strip: CaptureStrip {
        let verb = purpose == .mirror ? "MIRROR" : "CAPTURE"
        let spokenVerb = purpose == .mirror ? "Mirror a window" : "Capture a window"
        if isLoading && windows.isEmpty {
            return CaptureStrip(items: [verb, "READING WINDOWS"], spoken: "\(spokenVerb), reading windows")
        }
        let noun = windows.count == 1 ? "WINDOW" : "WINDOWS"
        return CaptureStrip(
            items: [verb, "\(windows.count) \(noun)"],
            spoken: "\(spokenVerb), \(windows.count) \(windows.count == 1 ? "window" : "windows")"
        )
    }

    var body: some View {
        CaptureStage {
            VStack(spacing: PixelHandTheme.Space.md) {
                CaptureHeader(
                    strip: strip,
                    style: windows.isEmpty ? .dim : .live,
                    closeLabel: "Cancel",
                    onClose: onCancel
                ) {
                    CaptureIconButton(
                        glyph: CaptureGlyphs.refresh,
                        label: "Refresh windows",
                        isEnabled: !isLoading,
                        action: onRefresh
                    )
                }

                Group {
                    if isLoading && windows.isEmpty {
                        VStack(spacing: PixelHandTheme.Space.lg) {
                            DotWave(label: "Reading windows from the Mac")
                            DotMatrixText("READING WINDOWS", pitch: 1.6, label: "Reading windows")
                                .foregroundStyle(PixelHandTheme.Brand.phosphor)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if windows.isEmpty {
                        PHEmptyState(
                            glyph: PixelGlyphs.screen,
                            title: "No windows",
                            message: CaptureSheetChrome.emptyWindowsMessage(isMirror: purpose == .mirror),
                            primaryTitle: "Refresh",
                            primaryAction: onRefresh
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        grid
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: PixelHandTheme.Space.md) {
                ForEach(orderedWindows) { window in
                    Button {
                        GestureHaptic.medium.trigger()
                        onPick(window)
                    } label: {
                        WindowCell(window: window)
                    }
                    .buttonStyle(WindowCellButtonStyle())
                    .accessibilityLabel(window.title.isEmpty ? window.appName : "\(window.appName), \(window.title)")
                    .accessibilityHint(purpose == .mirror ? "Mirrors this window." : "Captures this window.")
                    .accessibilityIdentifier("ph.capture.window")
                    .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.key)
                }
            }
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .padding(.bottom, PixelHandTheme.Space.xl)
        }
    }
}

// MARK: - Cell

private struct WindowCell: View {
    let window: WindowInfo

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
        VStack(spacing: 6) {
            icon
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(window.appName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            Text(window.title.isEmpty ? " " : window.title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
        .padding(.vertical, PixelHandTheme.Space.md)
        .padding(.horizontal, PixelHandTheme.Space.sm)
        .background(PixelHandTheme.Brand.screenRaised, in: shape)
        .overlay(shape.strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline))
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private var icon: some View {
        if let data = window.appIconData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(PixelHandTheme.Brand.screenHigh)
                .overlay(
                    PHGlyph(glyph: PixelGlyphs.screen, pitch: 2.6)
                        .foregroundStyle(Color.white.opacity(0.6))
                )
        }
    }
}

// MARK: - Button style
//
// Press feedback via `ButtonStyleConfiguration.isPressed` so we can drop the
// previous `simultaneousGesture(DragGesture(minimumDistance: 0))` hack.
// That hack was the reason taps weren't reaching `onPick` — it intercepted
// the sheet's gesture pipeline and either swallowed the press or blocked
// the scroll, depending on platform.

private struct WindowCellButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
                    .strokeBorder(PixelHandTheme.Brand.phosphor.opacity(configuration.isPressed ? 0.9 : 0), lineWidth: PixelHandTheme.Stroke.selection)
                    .shadow(color: PixelHandTheme.Brand.glow.opacity(configuration.isPressed ? 0.6 : 0), radius: 4)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}
