//
//  MirrorToolbarPlan.swift
//  PixelHandCore
//
//  The docked mirror pane's toolbar on every device (build 23):
//
//  - VQ-060: the iPhone toolbar had no Picture in Picture button. The
//    button was dropped wherever `AVPictureInPictureController` said PiP
//    isn't supported, which iPhone simulators say while iPhones (iOS 14
//    and later) support it. Phones always show the button; where the
//    system really can't start PiP, a tap says so instead of doing nothing.
//  - VQ-061: the iPhone toolbar never hid. The 3 s timer ran once, when
//    the pane appeared; if the first frame hadn't arrived yet it gave up
//    and never ran again. The timer now restarts whenever anything that
//    can hold the toolbar up changes (`hideKey`).
//

import Foundation

public enum MirrorToolbarPlan {
    /// The toolbar hides this long after the last touch (as on iPad).
    public static let hideDelay: TimeInterval = 3

    /// The PiP button.
    public enum PiPButton: Equatable, Sendable {
        /// Not shown: a device that can't do PiP (an iPad without it).
        case hidden
        /// Shown and works.
        case available
        /// Shown, but a tap explains that PiP can't start here.
        case explainsUnavailable
    }

    public static func pipButton(systemSupportsPiP: Bool, isPhone: Bool) -> PiPButton {
        if systemSupportsPiP { return .available }
        return isPhone ? .explainsUnavailable : .hidden
    }

    /// What the hide timer depends on: it restarts whenever this changes,
    /// so a toolbar held up by a missing frame, a sheet or VoiceOver hides
    /// 3 s after that ends.
    public struct HideKey: Hashable, Sendable {
        public var touches: Int
        public var hasPicture: Bool
        public var isPickerPresented: Bool
        public var voiceOverOn: Bool

        public init(touches: Int, hasPicture: Bool, isPickerPresented: Bool, voiceOverOn: Bool) {
            self.touches = touches
            self.hasPicture = hasPicture
            self.isPickerPresented = isPickerPresented
            self.voiceOverOn = voiceOverOn
        }
    }

    /// Whether the timer for `key` may hide the toolbar when it fires.
    public static func mayHide(_ key: HideKey) -> Bool {
        key.hasPicture && !key.isPickerPresented && !key.voiceOverOn
    }
}
