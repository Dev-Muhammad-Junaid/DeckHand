//
//  DuoCrease.swift
//  DeckHandiOS – Shell
//
//  Reads the iPhone Duo's crease for the shell (UX-040). The pose and the
//  pane maths live in Core (`DuoPoseMachine`, `DuoPanes`); this file only
//  turns SwiftUI's geometry into `DuoPoseInput`.
//
//  Two sources, best first:
//    1. iOS 27.1 SDK: `GeometryProxy.reservedRegions(kind: .division)`
//       (with inactive regions, so the layout doesn't jump as the device
//       goes from half-folded to flat) and `onHingeChange` for the closed
//       status. Compiled only with the Xcode 27 toolchain (Swift 6.4) and
//       used only on iOS 27.1+.
//    2. Otherwise Core infers the crease from the window size on a phone
//       (`DuoPoseMachine.inferredBand`): the window's centre line, 40 pt.
//

import PixelHandCore
import SwiftUI
import UIKit

enum DuoCrease {
    /// The shell's pose input for one layout pass.
    @MainActor
    static func input(proxy: GeometryProxy, hingeStatus: DuoHingeStatus?) -> DuoPoseInput {
        let size = proxy.size
        let global = proxy.frame(in: .global)
        let insets = proxy.safeAreaInsets
        // The crease runs through the window's centre: work it out from
        // the shell's place in the window and the insets around it.
        let windowWidth = global.minX + size.width + insets.trailing
        let windowHeight = global.minY + size.height + insets.bottom
        let centre = (
            x: Double(windowWidth / 2 - global.minX),
            y: Double(windowHeight / 2 - global.minY)
        )
        return DuoPoseInput(
            width: Double(size.width),
            height: Double(size.height),
            windowCentre: centre,
            division: division(proxy: proxy),
            hingeStatus: hingeStatus,
            isPhone: UIDevice.current.userInterfaceIdiom == .phone
        )
    }

    /// The system's division region (frame with its margins) in the
    /// proxy's coordinates, or `nil` before iOS 27.1 / without the SDK.
    @MainActor
    static func division(proxy: GeometryProxy) -> DuoRect? {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            for region in proxy.reservedRegions(kind: .division, options: [.includeInactive]) {
                let frame = region.frame
                return DuoRect(
                    x: Double(frame.minX),
                    y: Double(frame.minY),
                    width: Double(frame.width),
                    height: Double(frame.height)
                )
            }
        }
        #endif
        return nil
    }
}

/// Keeps `status` in step with the hinge on iOS 27.1+; does nothing before.
struct DuoHingeReader: ViewModifier {
    @Binding var status: DuoHingeStatus?

    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, newContext in
                // The status type is inferred, so only the case names matter.
                guard let hinge = newContext.hinge else {
                    status = nil
                    return
                }
                switch hinge.status {
                case .closed: status = .closed
                case .partiallyOpen: status = .partiallyOpen
                case .fullyOpen: status = .fullyOpen
                default: status = nil
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Reads the hinge status into `status` where the SDK has it.
    func duoHingeStatus(_ status: Binding<DuoHingeStatus?>) -> some View {
        modifier(DuoHingeReader(status: status))
    }
}
