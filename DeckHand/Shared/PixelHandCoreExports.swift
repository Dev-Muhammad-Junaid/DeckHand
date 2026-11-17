//
//  PixelHandCoreExports.swift
//  Pixel Hand – Shared
//
//  Re-exports PixelHandCore to every file of the targets that compile
//  `Shared/` (both apps and DeckHandTests), so the protocol, models and
//  policies that moved into the Core package are visible without an
//  `import PixelHandCore` line in each file.
//

@_exported import PixelHandCore

// Names that also exist in Apple frameworks. A declaration in this module
// shadows imported ones, so these keep unqualified uses unambiguous in
// files that also import SwiftUI (which has its own `ScrollPhase` on
// iOS 18 / macOS 15).
typealias ScrollPhase = PixelHandCore.ScrollPhase
typealias Action = PixelHandCore.Action
