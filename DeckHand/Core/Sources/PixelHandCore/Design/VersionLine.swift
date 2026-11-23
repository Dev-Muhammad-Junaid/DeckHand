//
//  VersionLine.swift
//  PixelHandCore – Design
//
//  Settings' version line in dot-matrix (`07-Polish-Spec.md` §7 "Settings"):
//  "PIXEL HAND 1.1 - 52" drawn, "Pixel Hand version 1.1, build 52" spoken.
//  Only characters the 5 × 7 font has, so nothing draws as a gap.
//

import Foundation

public enum VersionLine {
    public static func text(version: String?, build: String?) -> String {
        var line = "PIXEL HAND"
        if let version = cleaned(version) { line += " \(version)" }
        if let build = cleaned(build) { line += " - \(build)" }
        return line
    }

    public static func spoken(version: String?, build: String?) -> String {
        var line = "Pixel Hand"
        if let version = cleaned(version) { line += " version \(version)" }
        if let build = cleaned(build) { line += ", build \(build)" }
        return line
    }

    /// Drops characters the dot-matrix font can't draw.
    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let kept = String(value.uppercased().filter { DotMatrixFont.pattern(for: $0) != nil && $0 != " " })
        return kept.isEmpty ? nil : kept
    }
}
