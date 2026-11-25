#!/usr/bin/env bash
# Writes Pixel Hand's Control Center symbols (custom SF Symbol templates
# drawn from the dot glyphs, `ControlSymbolTemplate` in Core) into the
# widget extension's asset catalog. Run after changing a glyph:
#
#   DeckHand/Scripts/make-control-symbols.sh
#
# Works on macOS and Linux (needs `swift`).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$root/DeckHandWidgets/Assets.xcassets"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/make-control-symbols"
cat > "$work/Package.swift" <<SWIFT
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "make-control-symbols",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "$root/Core")],
    targets: [.executableTarget(name: "make-control-symbols", dependencies: [.product(name: "PixelHandCore", package: "Core")])]
)
SWIFT
cat > "$work/Sources/make-control-symbols/main.swift" <<'SWIFT'
import Foundation
import PixelHandCore

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
try fm.createDirectory(at: out, withIntermediateDirectories: true)
try Data("{\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n".utf8).write(to: out.appendingPathComponent("Contents.json"))
for symbol in ControlSymbolTemplate.symbols {
    let set = out.appendingPathComponent("\(symbol.name).symbolset")
    try fm.createDirectory(at: set, withIntermediateDirectories: true)
    try Data(ControlSymbolTemplate.svg(symbol).utf8).write(to: set.appendingPathComponent("\(symbol.name).svg"))
    try Data(ControlSymbolTemplate.contentsJSON(symbol).utf8).write(to: set.appendingPathComponent("Contents.json"))
    print("wrote \(symbol.name)")
}
SWIFT
swift run --package-path "$work" -c debug make-control-symbols "$out"
