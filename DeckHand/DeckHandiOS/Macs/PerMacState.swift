//
//  PerMacState.swift
//  DeckHandiOS – Macs
//
//  Each Mac keeps its own surface, mirror settings and glance (UX-030,
//  `03-Layout-Strategy.md` "Each Mac keeps its own surface, deck page,
//  mirror layout and preset"). The deck page is kept by `MacSwitcher`; the
//  layout preset was already per Mac (`LayoutPresetMemory`).
//
//  - `.perMacSurface(_:)` on the shell: restores the focused Mac's surface
//    when the shell appears (it is rebuilt for every Mac) and records
//    changes.
//  - `.perMacMirrorSettings()` on the root: applies the entered Mac's
//    mirror sharpness, frame rate and layout, and records changes.
//  - `.macSessionGlance(_:)` on the control view: hands the session's front
//    app, lock state and link to the Mac cards.
//

import SwiftUI

extension View {
    /// Keeps `surface` (a `ControlSurface.rawValue`) per Mac.
    func perMacSurface(_ surface: Binding<String>) -> some View {
        modifier(PerMacSurfaceModifier(surface: surface))
    }

    /// Keeps the mirror settings per Mac.
    func perMacMirrorSettings() -> some View {
        modifier(PerMacMirrorModifier())
    }

    /// Feeds the session's glance to My Macs and the sidebar.
    func macSessionGlance(_ session: ControlSessionModel) -> some View {
        modifier(MacSessionGlance(session: session))
    }
}

private struct PerMacSurfaceModifier: ViewModifier {
    @Binding var surface: String
    private let switcher = MacSwitcher.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let saved = switcher.focusedMemory?.surface, saved != surface {
                    surface = saved
                } else {
                    switcher.noteSurface(surface)
                }
            }
            .onChange(of: surface) { _, newValue in
                switcher.noteSurface(newValue)
            }
    }
}

private struct PerMacMirrorModifier: ViewModifier {
    @EnvironmentObject private var settings: DeckHandSettings
    private let switcher = MacSwitcher.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: switcher.focusedDeviceID, initial: true) { _, focused in
                guard focused != nil else { return }
                if let saved = switcher.focusedMemory?.mirror {
                    apply(saved)
                } else {
                    switcher.noteMirror(current)
                }
            }
            .onChange(of: settings.mirrorSharpness) { switcher.noteMirror(current) }
            .onChange(of: settings.mirrorFrameRate) { switcher.noteMirror(current) }
            .onChange(of: settings.mirrorLayout) { switcher.noteMirror(current) }
    }

    private var current: MacMirrorMemory {
        MacMirrorMemory(
            sharpness: settings.mirrorSharpness.rawValue,
            frameRate: settings.mirrorFrameRate.rawValue,
            layout: settings.mirrorLayout.flatMap { try? JSONEncoder().encode($0) }
        )
    }

    private func apply(_ saved: MacMirrorMemory) {
        if let sharpness = MirrorSharpness(rawValue: saved.sharpness), sharpness != settings.mirrorSharpness {
            settings.mirrorSharpness = sharpness
        }
        if let rate = MirrorFrameRate(rawValue: saved.frameRate), rate != settings.mirrorFrameRate {
            settings.mirrorFrameRate = rate
        }
        if settings.rememberMirrorLayout {
            let layout = saved.layout.flatMap { try? JSONDecoder().decode(MirrorLayout.self, from: $0) }
            if layout != settings.mirrorLayout { settings.mirrorLayout = layout }
        }
    }
}

private struct MacSessionGlance: ViewModifier {
    let session: ControlSessionModel
    private let switcher = MacSwitcher.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: session.activeAppName, initial: true) { note() }
            .onChange(of: session.macLockState) { note() }
            .onChange(of: session.link) { note() }
    }

    private func note() {
        switcher.noteGlance(session.macGlance, for: session.macDeviceID)
    }
}
