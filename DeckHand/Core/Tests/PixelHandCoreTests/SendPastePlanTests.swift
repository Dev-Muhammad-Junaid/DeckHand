//
//  SendPastePlanTests.swift
//  PixelHandCoreTests
//
//  The Send sheet's Clipboard chip as the system paste control: which
//  representation of each pasted item provider is loaded, in what order,
//  and what gets staged.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct SendPastePlanTests {
    @Test("A copied link loads the link first, then its text")
    func linkBeforeText() {
        let found = SendPastePlan.candidates(registeredTypes: ["public.url", "public.utf8-plain-text"])
        #expect(found == [.webLink, .text])
    }

    @Test("Plain text loads as text")
    func plainText() {
        #expect(SendPastePlan.candidates(registeredTypes: ["public.utf8-plain-text"]) == [.text])
        #expect(SendPastePlan.candidates(registeredTypes: ["public.text"]) == [.text])
    }

    @Test("An image with no text loads the image first, then its address")
    func imageBeforeLink() {
        let found = SendPastePlan.candidates(registeredTypes: ["public.jpeg", "public.url"])
        #expect(found == [.image(typeIdentifier: "public.jpeg", fileExtension: "jpg", needsConversion: false), .webLink])
    }

    @Test("With text present, an image is the last resort")
    func textBeforeImage() {
        let found = SendPastePlan.candidates(registeredTypes: ["public.png", "public.plain-text"])
        #expect(found == [.text, .image(typeIdentifier: "public.png", fileExtension: "png", needsConversion: false)])
    }

    @Test("PNG is preferred over other image types")
    func prefersPNG() {
        let found = SendPastePlan.candidates(registeredTypes: ["public.heic", "public.png", "public.jpeg"])
        #expect(found == [.image(typeIdentifier: "public.png", fileExtension: "png", needsConversion: false)])
    }

    @Test("Only the generic image type is converted to PNG")
    func genericImage() {
        let found = SendPastePlan.candidates(registeredTypes: ["public.image"])
        let candidate = SendPastePlan.Candidate.image(typeIdentifier: "public.image", fileExtension: "png", needsConversion: true)
        #expect(found == [candidate])
        #expect(SendPastePlan.stagedContentType(for: candidate) == "public.png")
        #expect(SendPastePlan.stagedContentType(for: .image(typeIdentifier: "public.jpeg", fileExtension: "jpg", needsConversion: false)) == "public.jpeg")
        #expect(SendPastePlan.stagedContentType(for: .text) == nil)
    }

    @Test("A file URL or an unknown type gives nothing to stage")
    func nothingToStage() {
        #expect(SendPastePlan.candidates(registeredTypes: ["public.file-url"]).isEmpty)
        #expect(SendPastePlan.candidates(registeredTypes: ["com.adobe.pdf"]).isEmpty)
        #expect(SendPastePlan.candidates(registeredTypes: []).isEmpty)
    }

    @Test("Several providers keep their order, skip empties, and stop at the cap")
    func severalProviders() {
        let plan = SendPastePlan.plan(providers: [["public.png"], ["com.adobe.pdf"], ["public.utf8-plain-text"]])
        #expect(plan.map(\.index) == [0, 2])
        let many = Array(repeating: ["public.png"], count: SendPastePlan.maxItems + 5)
        #expect(SendPastePlan.plan(providers: many).count == SendPastePlan.maxItems)
    }

    @Test("Only plain web links are staged as links")
    func linkStaging() {
        #expect(SendPastePlan.stagedText(fromLink: URL(string: "https://example.com/a?b=1")!) == "https://example.com/a?b=1")
        #expect(SendPastePlan.stagedText(fromLink: URL(fileURLWithPath: "/tmp/x.txt")) == nil)
        #expect(SendPastePlan.stagedText(fromLink: URL(string: "javascript:alert(1)")!) == nil)
        #expect(SendPastePlan.stagedText(fromLink: URL(string: "https://user:pw@example.com")!) == nil)
    }

    @Test("Text is trimmed and empty text is dropped")
    func textStaging() {
        #expect(SendPastePlan.stagedText(fromText: "  hello\n") == "hello")
        #expect(SendPastePlan.stagedText(fromText: " \n\t ") == nil)
    }

    @Test("Pasted images get a readable, numbered file name")
    func imageNames() {
        #expect(SendPastePlan.imageFileName(fileExtension: "png") == "Pasted Image.png")
        #expect(SendPastePlan.imageFileName(fileExtension: "jpg", ordinal: 2) == "Pasted Image 2.jpg")
        #expect(SendPastePlan.imageFileName(fileExtension: "") == "Pasted Image.png")
    }

    @Test("The control accepts links, text and images, and never file URLs")
    func acceptedTypes() {
        let accepted = SendPastePlan.acceptedTypeIdentifiers
        #expect(accepted.contains("public.url"))
        #expect(accepted.contains("public.plain-text"))
        #expect(accepted.contains("public.png"))
        #expect(accepted.contains("public.image"))
        #expect(!accepted.contains("public.file-url"))
        #expect(Set(accepted).count == accepted.count)
    }
}
