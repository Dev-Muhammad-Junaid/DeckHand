//
//  TransferInlineText.swift
//  PixelHandCore
//
//  S1: links and text. A link is opened in the Mac's browser without a
//  prompt, so only plain web addresses count as links: `http` or `https`,
//  with a host, no user name or password, at most `maxLinkLength`
//  characters. Anything else that claims to be a link is treated as text
//  (saved, never opened), so a peer can't make the Mac open `file:`,
//  `javascript:` or another app's URL scheme.
//

import Foundation

public enum TransferInlineText {
    public static let maxLinkLength = 8 * 1024

    /// Decodes received bytes as UTF-8 text with control characters other
    /// than newline and tab removed. `nil` for invalid UTF-8 or nothing
    /// left.
    public static func text(from data: Data) -> String? {
        guard data.count <= Int(TransferPolicy.maxInlineBytes),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            switch scalar.value {
            case 0x0A, 0x09: scalars.append(scalar)
            case 0x00...0x1F, 0x7F: continue
            default: scalars.append(scalar)
            }
        }
        let clean = String(scalars)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clean
    }

    /// The web address in `text`, when the whole text (trimmed) is one.
    public static func webLink(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLinkLength,
              !trimmed.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    /// A short title for a text or link item: the host for a link, else
    /// the first line, cut to `limit` characters.
    public static func title(for text: String, limit: Int = 60) -> String {
        if let url = webLink(text), let host = url.host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    /// The file name a text item is saved under: its title, made safe.
    public static func fileName(for text: String, kind: TransferKind) -> String {
        let base = title(for: text, limit: 40)
        let name = TransferFileName.sanitized(base, kind: kind)
        return name.lowercased().hasSuffix(".txt") ? name : name + ".txt"
    }
}
