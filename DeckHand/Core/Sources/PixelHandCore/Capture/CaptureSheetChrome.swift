//
//  CaptureSheetChrome.swift
//  PixelHandCore
//
//  The capture sheet's words and shapes (UX-009): the dot-matrix status
//  strip over the picture, the read-text summary, the error titles
//  (including the locked-Mac refusal), the annotation palette and stroke
//  widths, and the maths that maps a drawing on screen onto the capture's
//  own pixels. Tested on Linux; the views only draw what this returns.
//

import Foundation

/// What was captured.
public enum CaptureKind: Equatable, Sendable {
    case fullScreen
    case region
    case window(appName: String)
}

/// The capture sheet's steps. Annotate and read text are states inside the
/// one sheet, never sheets of their own (one modal level from Control).
public enum CaptureStep: Equatable, Sendable {
    case preview
    case annotate
    case readText
}

/// A dot-matrix strip: the items drawn, and what VoiceOver reads instead.
public struct CaptureStrip: Equatable, Sendable {
    public let items: [String]
    public let spoken: String

    public init(items: [String], spoken: String) {
        self.items = items
        self.spoken = spoken
    }
}

public enum CaptureSheetChrome {
    /// Longest app name the strip shows.
    public static let maxAppNameLength = 12

    /// The strip over the picture: `REGION · 812X540 · MARKED`,
    /// `WINDOW · SAFARI · 1440X900`. Items drop from the end when the strip
    /// runs out of room, so the most useful come first.
    public static func strip(kind: CaptureKind, pixelWidth: Int, pixelHeight: Int, annotated: Bool) -> CaptureStrip {
        var items: [String] = []
        var spoken: [String] = []
        switch kind {
        case .fullScreen:
            items.append("FULL SCREEN")
            spoken.append("Full screen capture")
        case .region:
            items.append("REGION")
            spoken.append("Region capture")
        case .window(let appName):
            items.append("WINDOW")
            let name = MirrorPaneChrome.dotMatrixSafe(appName, maxLength: maxAppNameLength)
            if !name.isEmpty { items.append(name) }
            spoken.append(appName.isEmpty ? "Window capture" : "Window capture, \(appName)")
        }
        if pixelWidth > 0, pixelHeight > 0 {
            items.append("\(pixelWidth)X\(pixelHeight)")
            spoken.append("\(pixelWidth) by \(pixelHeight) pixels")
        }
        if annotated {
            items.append("MARKED")
            spoken.append("annotated")
        }
        return CaptureStrip(items: items, spoken: spoken.joined(separator: ", "))
    }

    /// The annotate step's strip: `ANNOTATE · 3 MARKS`.
    public static func annotateStrip(marks: Int) -> CaptureStrip {
        let count = max(marks, 0)
        let noun = count == 1 ? "MARK" : "MARKS"
        let spokenNoun = count == 1 ? "mark" : "marks"
        return CaptureStrip(
            items: ["ANNOTATE", "\(count) \(noun)"],
            spoken: "Annotate, \(count) \(spokenNoun)"
        )
    }

    /// The read-text step's strip: `READ TEXT · 12 LINES · 340 CHARS`;
    /// `READ TEXT · READING` while Vision works.
    public static func readTextStrip(lines: Int?, characters: Int?) -> CaptureStrip {
        guard let lines else {
            return CaptureStrip(items: ["READ TEXT", "READING"], spoken: "Reading text")
        }
        let chars = max(characters ?? 0, 0)
        let lineWord = lines == 1 ? "LINE" : "LINES"
        let spokenLine = lines == 1 ? "line" : "lines"
        let spokenChar = chars == 1 ? "character" : "characters"
        return CaptureStrip(
            items: ["READ TEXT", "\(lines) \(lineWord)", "\(chars) CHARS"],
            spoken: "Read text, \(lines) \(spokenLine), \(chars) \(spokenChar)"
        )
    }

    // MARK: Errors

    /// Whether a capture error is the Mac's locked-screen refusal.
    public static func isLockedRefusal(_ message: String) -> Bool {
        message == LockPolicy.lockedErrorMessage
    }

    /// The alert title for a failed capture or mirror. Sentence case, like
    /// the lock banner (build 19).
    public static func errorTitle(message: String, isMirror: Bool, macLocked: Bool = false) -> String {
        if macLocked || isLockedRefusal(message) { return "Mac is locked" }
        return isMirror ? "Live screen unavailable" : "Screenshot failed"
    }

    /// The alert body. A locked Mac (the refusal, or the remote's own lock
    /// state) says what to do; anything else is the Mac's sentence, or our
    /// own copy when it is a raw system error (`UserFacingError`).
    public static func errorMessage(message: String, isMirror: Bool, macLocked: Bool = false) -> String {
        if macLocked || isLockedRefusal(message) {
            return isMirror
                ? "Unlock the Mac to see its screen. Pixel Hand never shows the lock screen."
                : "Unlock the Mac to take a screenshot. Pixel Hand never captures the lock screen."
        }
        return UserFacingError.sentence(from: message)
            ?? CaptureFailure.captureFailed.message(isMirror: isMirror)
    }

    /// The window picker's empty state, which is also what a locked Mac
    /// sends back (an empty list).
    public static func emptyWindowsMessage(isMirror: Bool) -> String {
        let verb = isMirror ? "mirror" : "capture"
        return "Open a window on the Mac to \(verb) it. If the Mac is locked, unlock it first."
    }

    // MARK: Annotation tools

    /// Pen widths, in points on screen. Scaled to the capture's pixels on
    /// export so a mark looks the same thickness as it did while drawing.
    public static let penWidths: [Double] = [2, 4, 8, 14]
    public static let defaultPenWidth = 4.0

    /// Pen colours by name; the app maps each to a colour. Phosphor first
    /// (the brand's highlight), then the classic markup colours.
    public enum Ink: String, CaseIterable, Sendable {
        case phosphor, red, orange, yellow, green, blue, white, black

        public var label: String {
            switch self {
            case .phosphor: "Phosphor"
            case .red: "Red"
            case .orange: "Orange"
            case .yellow: "Yellow"
            case .green: "Green"
            case .blue: "Blue"
            case .white: "White"
            case .black: "Black"
            }
        }
    }

    public static let defaultInk = Ink.red
}

/// Where a capture is drawn on screen, and how a point on screen maps onto
/// the capture's own pixels.
public enum CaptureGeometry {
    /// `content` fitted inside `container` (aspect fit, centred).
    public static func fittedRect(contentWidth: Double, contentHeight: Double, in container: MirrorRect) -> MirrorRect {
        guard contentWidth > 0, contentHeight > 0, container.width > 0, container.height > 0 else {
            return MirrorRect(x: container.x, y: container.y, width: 0, height: 0)
        }
        let scale = min(container.width / contentWidth, container.height / contentHeight)
        let w = contentWidth * scale
        let h = contentHeight * scale
        return MirrorRect(
            x: container.x + (container.width - w) / 2,
            y: container.y + (container.height - h) / 2,
            width: w,
            height: h
        )
    }

    /// Image pixels per screen point for a capture drawn in `fitted`.
    public static func pixelsPerPoint(fitted: MirrorRect, imageWidth: Double) -> Double {
        guard fitted.width > 0 else { return 1 }
        return imageWidth / fitted.width
    }

    /// A point on screen in the capture's pixels (top-left origin). Points
    /// outside the picture map outside the image; drawing clips them.
    public static func imagePoint(x: Double, y: Double, fitted: MirrorRect, imageWidth: Double, imageHeight: Double) -> (x: Double, y: Double) {
        guard fitted.width > 0, fitted.height > 0 else { return (0, 0) }
        return (
            (x - fitted.x) * imageWidth / fitted.width,
            (y - fitted.y) * imageHeight / fitted.height
        )
    }

    /// A selection on screen as the 0…1 rect the Mac crops to, clamped to
    /// the picture. `nil` when either side is under `minimumSide` points.
    public static func normalizedSelection(_ selection: MirrorRect, fitted: MirrorRect, minimumSide: Double) -> MirrorRect? {
        guard fitted.width > 0, fitted.height > 0,
              selection.width >= minimumSide, selection.height >= minimumSide else { return nil }
        let x0 = max(selection.x, fitted.x)
        let y0 = max(selection.y, fitted.y)
        let x1 = min(selection.x + selection.width, fitted.x + fitted.width)
        let y1 = min(selection.y + selection.height, fitted.y + fitted.height)
        guard x1 > x0, y1 > y0 else { return nil }
        return MirrorRect(
            x: (x0 - fitted.x) / fitted.width,
            y: (y0 - fitted.y) / fitted.height,
            width: (x1 - x0) / fitted.width,
            height: (y1 - y0) / fitted.height
        )
    }

    /// The region strip's size readout: the selection in the capture's
    /// pixels, `812X540`.
    public static func selectionPixels(_ selection: MirrorRect, fitted: MirrorRect, imageWidth: Double, imageHeight: Double) -> String? {
        guard let n = normalizedSelection(selection, fitted: fitted, minimumSide: 1) else { return nil }
        let w = Int((n.width * imageWidth).rounded())
        let h = Int((n.height * imageHeight).rounded())
        return "\(w)X\(h)"
    }
}
