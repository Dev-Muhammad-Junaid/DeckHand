//
//  MirrorWindowProbe.swift
//  DeckHandMac
//
//  S14: one look at a mirrored window for `MirrorWindowTracker` (Core):
//  missing (closed), on screen at a frame, or off screen and whether it
//  was minimised. `MirrorStreamService` calls it twice a second while a
//  window is mirrored.
//
//  - Frame and on-screen state: `CGWindowListCopyWindowInfo` for that one
//    window (public). Frames are global points, top-left origin, the same
//    space as `CGDisplayBounds` and `SCWindow.frame`.
//  - Minimised: only asked when the window is off screen. A hidden app
//    (`NSRunningApplication.isHidden`) isn't minimised. Otherwise the
//    window's Accessibility element is found among its app's windows by
//    `CGWindowID` with the private `_AXUIElementGetWindow`, loaded with
//    `dlsym`, and `kAXMinimizedAttribute` is read. Without the symbol or
//    Accessibility access the answer is "can't tell" and the tracker's
//    grace period decides.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
enum MirrorWindowProbe {
    /// The window's frame and owner, when it is listed at all.
    struct Listing {
        let frame: CGRect
        let isOnScreen: Bool
        let ownerPID: pid_t
    }

    static func listing(windowID: CGWindowID) -> Listing? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }
        let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        return Listing(frame: frame, isOnScreen: onScreen, ownerPID: pid)
    }

    /// One look, in the tracker's terms.
    static func observe(windowID: CGWindowID) -> MirrorWindowTracker.Observation {
        guard let listing = listing(windowID: windowID) else { return .missing }
        let rect = MirrorRect(
            x: listing.frame.origin.x, y: listing.frame.origin.y,
            width: listing.frame.width, height: listing.frame.height
        )
        if listing.isOnScreen { return .onScreen(frame: rect) }
        return .offScreen(frame: rect, minimized: isMinimized(windowID: windowID, pid: listing.ownerPID))
    }

    /// `true` / `false` when it can tell, `nil` when it can't.
    static func isMinimized(windowID: CGWindowID, pid: pid_t) -> Bool? {
        guard pid > 0 else { return nil }
        if NSRunningApplication(processIdentifier: pid)?.isHidden == true { return false }
        guard AXIsProcessTrusted(), let getWindow = axGetWindow else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows {
            var id: CGWindowID = 0
            guard getWindow(window, &id) == .success, id == windowID else { continue }
            var minimized: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success else {
                return nil
            }
            return (minimized as? Bool) ?? (minimized as? NSNumber)?.boolValue
        }
        // Not among the app's windows: on another Space, AX lists only the
        // current Space's windows for some apps. Can't tell.
        return nil
    }

    // MARK: - Private symbol

    private typealias AXGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// `_AXUIElementGetWindow` (HIServices), or `nil` when this macOS
    /// doesn't have it.
    private static let axGetWindow: AXGetWindowFunction? = {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            DeckHandLog.app.info("Mirror: _AXUIElementGetWindow missing; minimised windows are judged by time off screen")
            return nil
        }
        return unsafeBitCast(pointer, to: AXGetWindowFunction.self)
    }()
}
