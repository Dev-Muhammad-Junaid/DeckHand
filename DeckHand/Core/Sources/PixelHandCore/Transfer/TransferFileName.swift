//
//  TransferFileName.swift
//  PixelHandCore
//
//  S1: file names that come from the other device. A name is a string from
//  the network, so before it becomes a path it loses every directory part,
//  control and direction-override character, leading dot and anything past
//  `maxBytes`, and it never replaces a file already there.
//

import Foundation

public enum TransferFileName {
    /// Longest name kept, in UTF-8 bytes (APFS allows 255).
    public static let maxBytes = 200

    /// The name used when nothing usable is left.
    public static func fallback(for kind: TransferKind) -> String {
        switch kind {
        case .file: "File"
        case .photo: "Photo"
        case .link: "Link.txt"
        case .text: "Text.txt"
        }
    }

    /// A safe single path component for `raw`.
    public static func sanitized(_ raw: String, kind: TransferKind) -> String {
        // Only the last component: no "../", no absolute paths.
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" || $0 == ":" }).last.map(String.init) ?? ""
        var scalars = String.UnicodeScalarView()
        for scalar in last.unicodeScalars where !isUnsafe(scalar) {
            scalars.append(scalar)
        }
        var name = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = truncated(name)
        return name.isEmpty ? fallback(for: kind) : name
    }

    /// `name` if it isn't in `existing`, else "name 2.ext", "name 3.ext"…
    public static func unique(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let (base, ext) = split(name)
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !existing.contains(candidate) { return candidate }
            n += 1
        }
    }

    /// Base name and extension ("" when none). A leading-dot-only name has
    /// no extension.
    public static func split(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = String(name[name.index(after: dot)...])
        guard !ext.isEmpty, ext.count <= 16, !ext.contains(" ") else { return (name, "") }
        return (String(name[..<dot]), ext)
    }

    private static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F: true // control characters
        case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true // direction marks and overrides ("gpj.exe")
        case 0xFEFF: true
        default: false
        }
    }

    /// Cuts to `maxBytes` UTF-8 bytes, keeping the extension and never
    /// splitting a character.
    private static func truncated(_ name: String) -> String {
        guard name.utf8.count > maxBytes else { return name }
        let (base, ext) = split(name)
        let suffix = ext.isEmpty ? "" : "." + ext
        let budget = max(1, maxBytes - suffix.utf8.count)
        var cut = ""
        for character in base {
            if cut.utf8.count + String(character).utf8.count > budget { break }
            cut.append(character)
        }
        return cut.trimmingCharacters(in: .whitespaces) + suffix
    }
}
