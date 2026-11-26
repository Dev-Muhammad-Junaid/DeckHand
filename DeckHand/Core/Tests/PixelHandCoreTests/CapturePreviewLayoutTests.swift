//
//  CapturePreviewLayoutTests.swift
//  PixelHandCoreTests
//
//  The capture preview (owner testing, build 26, OT-10): the picture fills
//  the room between header and dock, aspect-fit and centred on whole
//  points; pinch, double-tap and pan stay inside the picture.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct CapturePreviewLayoutTests {
    // iPad Air 11" portrait: 820 × 1180 stage, header 52, dock 80.
    static let portraitArea = CapturePreviewLayout.pictureArea(stageWidth: 820, stageHeight: 1180, headerHeight: 52, dockHeight: 80)

    @Test("The picture area is everything between the header and the dock, less the side insets")
    func area() {
        let area = Self.portraitArea
        #expect(area.x == 16)
        #expect(area.y == 64)
        #expect(area.width == 788)
        #expect(area.height == 1180 - 64 - 12 - 80)
        let none = CapturePreviewLayout.pictureArea(stageWidth: 20, stageHeight: 100, headerHeight: 52, dockHeight: 80)
        #expect(none.width == 0)
        #expect(none.height == 0)
    }

    @Test("A landscape capture fills the width in portrait, centred in the area")
    func landscapeCaptureInPortrait() {
        let area = Self.portraitArea
        let frame = CapturePreviewLayout.pictureFrame(imageWidth: 3024, imageHeight: 1964, in: area)
        #expect(frame.width == 788)
        #expect(frame.height == (788 * 1964 / 3024).rounded(.down))
        // Centred vertically, not pinned to the top.
        let above = frame.y - area.y
        let below = (area.y + area.height) - (frame.y + frame.height)
        #expect(abs(above - below) <= 1)
        #expect(above > 100)
    }

    @Test("A tall capture fills the height and is centred across")
    func tallCapture() {
        let area = MirrorRect(x: 16, y: 64, width: 1148, height: 664) // iPad landscape
        let frame = CapturePreviewLayout.pictureFrame(imageWidth: 1000, imageHeight: 2000, in: area)
        #expect(frame.height == 664)
        #expect(frame.width == 332)
        #expect(frame.x == 16 + (1148 - 332) / 2)
    }

    @Test("The frame is on whole points and never bigger than the area")
    func wholePoints() {
        let area = MirrorRect(x: 16, y: 61, width: 370.5, height: 641.3)
        let frame = CapturePreviewLayout.pictureFrame(imageWidth: 1440, imageHeight: 900, in: area)
        for value in [frame.x, frame.y, frame.width, frame.height] {
            #expect(value == value.rounded())
        }
        #expect(frame.width <= area.width)
        #expect(frame.height <= area.height)
        let empty = CapturePreviewLayout.pictureFrame(imageWidth: 0, imageHeight: 900, in: area)
        #expect(empty.width == 0)
    }

    @Test("Zoom stays between 1× and 6×")
    func zoomClamp() {
        #expect(CapturePreviewLayout.clampedZoom(0.4) == 1)
        #expect(CapturePreviewLayout.clampedZoom(3) == 3)
        #expect(CapturePreviewLayout.clampedZoom(40) == 6)
        #expect(CapturePreviewLayout.clampedZoom(.nan) == 1)
        #expect(!CapturePreviewLayout.isZoomed(1.005))
        #expect(CapturePreviewLayout.isZoomed(1.2))
    }

    @Test("Pan never shows past the picture's edges, and there is none at 1×")
    func panClamp() {
        let none = CapturePreviewLayout.clampedPan(x: 50, y: -50, zoom: 1, width: 400, height: 300)
        #expect(none.x == 0)
        #expect(none.y == 0)
        let zoomed = CapturePreviewLayout.clampedPan(x: 900, y: -900, zoom: 2, width: 400, height: 300)
        #expect(zoomed.x == 200)
        #expect(zoomed.y == -150)
        let inside = CapturePreviewLayout.clampedPan(x: 30, y: 20, zoom: 2, width: 400, height: 300)
        #expect(inside.x == 30)
        #expect(inside.y == 20)
    }

    @Test("Double-tap zooms in on the tapped point and back out to 1×")
    func doubleTap() {
        let width = 400.0, height = 300.0
        let centre = CapturePreviewLayout.doubleTap(at: (200, 150), zoom: 1, width: width, height: height)
        #expect(centre.zoom == CapturePreviewLayout.doubleTapZoom)
        #expect(centre.pan.x == 0)
        #expect(centre.pan.y == 0)

        // A point left of centre: the picture moves right so it stays put.
        let left = CapturePreviewLayout.doubleTap(at: (120, 150), zoom: 1, width: width, height: height)
        #expect(left.pan.x == (200 - 120) * 1.5)
        // The tapped point maps to itself: c + (p − c)·z + pan = p.
        #expect(200 + (120 - 200) * left.zoom + left.pan.x == 120)

        // A corner tap is held at the edge.
        let corner = CapturePreviewLayout.doubleTap(at: (0, 0), zoom: 1, width: width, height: height)
        #expect(corner.pan.x == width * 1.5 / 2)
        #expect(corner.pan.y == height * 1.5 / 2)

        let out = CapturePreviewLayout.doubleTap(at: (10, 10), zoom: 2.5, width: width, height: height)
        #expect(out.zoom == 1)
        #expect(out.pan.x == 0)
        #expect(out.pan.y == 0)
    }

    @Test("A pinch scales the pan with the zoom and snaps back to 1× when let go small")
    func pinch() {
        let grow = CapturePreviewLayout.pinch(startZoom: 2, magnification: 1.5, startPan: (40, -20), width: 400, height: 300)
        #expect(grow.zoom == 3)
        #expect(grow.pan.x == 60)
        #expect(grow.pan.y == -30)

        let shrink = CapturePreviewLayout.pinch(startZoom: 2, magnification: 0.4, startPan: (40, -20), width: 400, height: 300)
        #expect(shrink.zoom == 1)
        #expect(shrink.pan.x == 0)

        let capped = CapturePreviewLayout.pinch(startZoom: 4, magnification: 3, startPan: (0, 0), width: 400, height: 300)
        #expect(capped.zoom == CapturePreviewLayout.maximumZoom)
    }

    @Test("The dock keeps the actions together on wide windows")
    func dockWidth() {
        #expect(CapturePreviewLayout.dockMaximumWidth >= 5 * 88)
        #expect(CapturePreviewLayout.dockMaximumWidth.truncatingRemainder(dividingBy: 4) == 0)
    }
}
