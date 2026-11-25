//
//  SidebarTogglePlacement.swift
//  PixelHandCore – Design
//
//  OR-05: the Macs sidebar's show/hide button stays in one leading spot.
//  While the sidebar shows, the button leads the sidebar's title row; while
//  it is hidden, the same button leads the header row, before the Mac pill.
//  Both rows start at the window margin after Stage Manager's window
//  controls and share one height and button size, so the button doesn't
//  move when it's tapped.
//

import Foundation

public enum SidebarTogglePlacement {
    /// The button's side (a standard glass circle).
    public static let buttonSide = 44.0
    /// The height of the row it sits in: the header's dock height. The
    /// sidebar's title row uses it too.
    public static let rowHeight = 56.0

    /// Where the button's leading edge sits, from the window's leading edge.
    /// The sidebar's own leading padding equals the wide-class margin, so
    /// the answer doesn't depend on `sidebarShown`.
    public static func leadingX(sidebarShown: Bool, margin: Double, windowControlsInset: Double) -> Double {
        let start = sidebarShown ? sidebarLeadingPadding : margin
        return start + windowControlsInset
    }

    /// The sidebar's leading padding: the wide-class margin.
    public static let sidebarLeadingPadding = 24.0

    /// The button's centre, from the top of its row.
    public static var centreY: Double { rowHeight / 2 }

    /// VoiceOver label for the button.
    public static func label(sidebarShown: Bool) -> String {
        sidebarShown ? "Hide the Macs sidebar" : "Show the Macs sidebar"
    }
}
