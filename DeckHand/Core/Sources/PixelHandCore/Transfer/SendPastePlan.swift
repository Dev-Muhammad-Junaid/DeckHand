//
//  SendPastePlan.swift
//  PixelHandCore
//
//  The Send sheet's Clipboard chip is the system paste control, so iOS
//  never shows "Allow Paste": the control hands over item providers, and
//  this plan says, from each provider's registered type identifiers, which
//  representation to load and in what order, and turns what was loaded
//  into something to stage (text, a link, or an image file).
//
//  Order, per provider: a web link, then text, then an image (the chip's
//  old "a link first, then text", with images added). When a provider has
//  an image and no text, the image comes first: copying a picture in a
//  browser carries the picture and its address, and the picture is what
//  the person copied. A candidate that loads nothing usable (a `file:`
//  link, empty text) falls through to the next.
//

import Foundation

public enum SendPastePlan {
    /// One representation to load from a pasted item provider.
    public enum Candidate: Equatable, Sendable {
        /// Load a URL; staged only when it is a plain web address.
        case webLink
        /// Load a string.
        case text
        /// Load the data registered under `typeIdentifier`. When
        /// `needsConversion`, the type is the generic image type and the
        /// data is re-encoded as PNG before it is staged.
        case image(typeIdentifier: String, fileExtension: String, needsConversion: Bool)
    }

    /// The most pasted items staged at once (the Photos chip's limit).
    public static let maxItems = 20

    public static let urlType = "public.url"
    public static let fileURLType = "public.file-url"
    public static let textTypes = [
        "public.utf8-plain-text",
        "public.plain-text",
        "public.utf16-plain-text",
        "public.text",
    ]
    /// Concrete image types, most preferred first, with the file extension
    /// a staged copy gets.
    public static let imageTypes: [(identifier: String, fileExtension: String)] = [
        ("public.png", "png"),
        ("public.jpeg", "jpg"),
        ("public.heic", "heic"),
        ("public.heif", "heif"),
        ("com.compuserve.gif", "gif"),
        ("public.tiff", "tiff"),
    ]
    public static let genericImageType = "public.image"

    /// What the paste control accepts: the control is enabled only while
    /// the clipboard holds one of these.
    public static var acceptedTypeIdentifiers: [String] {
        [urlType] + textTypes + imageTypes.map(\.identifier) + [genericImageType]
    }

    /// The representations to try for one provider, in order; empty when
    /// it holds nothing the Send sheet can stage.
    public static func candidates(registeredTypes: [String]) -> [Candidate] {
        let types = Set(registeredTypes)
        let hasLink = types.contains(urlType)
        let hasText = textTypes.contains { types.contains($0) }
        let image = imageCandidate(types)

        var ordered: [Candidate] = []
        if let image, !hasText { ordered.append(image) }
        if hasLink { ordered.append(.webLink) }
        if hasText { ordered.append(.text) }
        if let image, hasText { ordered.append(image) }
        return ordered
    }

    /// The candidates for every pasted provider, capped at `maxItems`
    /// providers; providers with nothing to stage are dropped.
    public static func plan(providers: [[String]]) -> [(index: Int, candidates: [Candidate])] {
        var result: [(index: Int, candidates: [Candidate])] = []
        for (index, types) in providers.enumerated() {
            let found = candidates(registeredTypes: types)
            guard !found.isEmpty else { continue }
            result.append((index, found))
            if result.count == maxItems { break }
        }
        return result
    }

    /// The text to stage for a loaded URL: its address when it is a plain
    /// web link (`TransferInlineText.webLink`), else `nil` (try the next
    /// candidate; a `file:` or app link is never staged as a link).
    public static func stagedText(fromLink url: URL) -> String? {
        TransferInlineText.webLink(url.absoluteString)?.absoluteString
    }

    /// The text to stage for a loaded string: trimmed, `nil` when empty.
    public static func stagedText(fromText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The file name a pasted image is staged under ("Pasted Image.png";
    /// "Pasted Image 2.png" for the second of several).
    public static func imageFileName(fileExtension: String, ordinal: Int = 1) -> String {
        let base = ordinal > 1 ? "Pasted Image \(ordinal)" : "Pasted Image"
        let ext = fileExtension.isEmpty ? "png" : fileExtension
        return "\(base).\(ext)"
    }

    /// The content type a staged image is sent with.
    public static func stagedContentType(for candidate: Candidate) -> String? {
        guard case let .image(identifier, _, needsConversion) = candidate else { return nil }
        return needsConversion ? "public.png" : identifier
    }

    /// The line shown when the paste brought nothing to send.
    public static let nothingToSendNote = "The clipboard has no text, link or image."

    private static func imageCandidate(_ types: Set<String>) -> Candidate? {
        if let concrete = imageTypes.first(where: { types.contains($0.identifier) }) {
            return .image(typeIdentifier: concrete.identifier, fileExtension: concrete.fileExtension, needsConversion: false)
        }
        if types.contains(genericImageType) {
            return .image(typeIdentifier: genericImageType, fileExtension: "png", needsConversion: true)
        }
        return nil
    }
}
