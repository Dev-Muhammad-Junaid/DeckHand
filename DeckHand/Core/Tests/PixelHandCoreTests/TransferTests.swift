//
//  TransferTests.swift
//  PixelHandCoreTests
//
//  S1/S2: manifest reading, file names, inline text and links, the
//  receive policy, the outbox, resume offsets, progress, the Inbox, the
//  dot beam and the protocol 13 additions.
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("TransferManifestTests")
struct TransferManifestTests {
    @Test("A manifest round-trips through Loom offer fields")
    func roundTrip() throws {
        let manifest = TransferManifest(kind: .photo, name: "IMG_0001.HEIC", byteCount: 2_400_000, contentType: "public.heic")
        let read = try TransferManifest.read(
            logicalName: manifest.name,
            byteLength: manifest.byteCount,
            contentType: manifest.contentType,
            metadata: manifest.metadata
        ).get()
        #expect(read == manifest)
    }

    @Test("An offer without a Pixel Hand kind or with another manifest version is unsupported")
    func unsupported() {
        #expect(TransferManifest.read(logicalName: "a", byteLength: 1, contentType: nil, metadata: [:]) == .failure(.unsupported))
        #expect(TransferManifest.read(logicalName: "a", byteLength: 1, contentType: nil, metadata: ["ph.kind": "file", "ph.m": "2"]) == .failure(.unsupported))
        #expect(TransferManifest.read(logicalName: "a", byteLength: 1, contentType: nil, metadata: ["ph.kind": "folder", "ph.m": "1"]) == .failure(.unsupported))
    }

    @Test("An empty link or text is unsupported")
    func emptyInline() {
        #expect(TransferManifest.read(logicalName: "a", byteLength: 0, contentType: nil, metadata: ["ph.kind": "link", "ph.m": "1"]) == .failure(.unsupported))
    }

    @Test("Sizes over the cap for the kind are too large")
    func tooLarge() {
        let text = TransferManifest.read(logicalName: "t", byteLength: TransferPolicy.maxInlineBytes + 1, contentType: nil, metadata: ["ph.kind": "text", "ph.m": "1"])
        #expect(text == .failure(.tooLarge))
        let file = TransferManifest.read(logicalName: "f", byteLength: TransferPolicy.maxFileBytes + 1, contentType: nil, metadata: ["ph.kind": "file", "ph.m": "1"])
        #expect(file == .failure(.tooLarge))
        let ok = TransferManifest.read(logicalName: "f", byteLength: TransferPolicy.maxFileBytes, contentType: nil, metadata: ["ph.kind": "file", "ph.m": "1"])
        #expect((try? ok.get()) != nil)
    }

    @Test("Hostile names and content types are cleaned")
    func hostileFields() throws {
        let read = try TransferManifest.read(
            logicalName: "../../Library/LaunchAgents/evil.plist",
            byteLength: 10,
            contentType: "public.data\u{0}; rm -rf",
            metadata: ["ph.kind": "file", "ph.m": "1"]
        ).get()
        #expect(read.name == "evil.plist")
        #expect(read.contentType == nil)
        let long = String(repeating: "a", count: 200)
        #expect(TransferManifest(kind: .file, name: "x", byteCount: 1, contentType: long).contentType == nil)
    }
}

@Suite("TransferFileNameTests")
struct TransferFileNameTests {
    @Test("Only the last path component survives")
    func lastComponent() {
        #expect(TransferFileName.sanitized("/etc/passwd", kind: .file) == "passwd")
        #expect(TransferFileName.sanitized("..\\..\\boot.ini", kind: .file) == "boot.ini")
        #expect(TransferFileName.sanitized("a:b", kind: .file) == "b")
    }

    @Test("Leading dots, control and direction-override characters are removed")
    func unsafeCharacters() {
        #expect(TransferFileName.sanitized(".hidden", kind: .file) == "hidden")
        #expect(TransferFileName.sanitized("...", kind: .photo) == "Photo")
        #expect(TransferFileName.sanitized("in\u{7}voice\n.pdf", kind: .file) == "invoice.pdf")
        #expect(TransferFileName.sanitized("photo\u{202E}gpj.exe", kind: .file) == "photogpj.exe")
    }

    @Test("Empty names fall back by kind")
    func fallbacks() {
        #expect(TransferFileName.sanitized("", kind: .file) == "File")
        #expect(TransferFileName.sanitized("   ", kind: .text) == "Text.txt")
        #expect(TransferFileName.sanitized("/", kind: .link) == "Link.txt")
    }

    @Test("Long names are cut to the byte limit and keep their extension")
    func truncation() {
        let name = String(repeating: "é", count: 300) + ".jpeg"
        let clean = TransferFileName.sanitized(name, kind: .photo)
        #expect(clean.utf8.count <= TransferFileName.maxBytes)
        #expect(clean.hasSuffix(".jpeg"))
    }

    @Test("A taken name gets a number before its extension")
    func unique() {
        #expect(TransferFileName.unique("a.pdf", existing: []) == "a.pdf")
        #expect(TransferFileName.unique("a.pdf", existing: ["a.pdf"]) == "a 2.pdf")
        #expect(TransferFileName.unique("a.pdf", existing: ["a.pdf", "a 2.pdf"]) == "a 3.pdf")
        #expect(TransferFileName.unique("README", existing: ["README"]) == "README 2")
    }
}

@Suite("TransferInlineTextTests")
struct TransferInlineTextTests {
    @Test("Only plain web addresses are links")
    func links() {
        #expect(TransferInlineText.webLink("https://pixelhand.app/mac")?.absoluteString == "https://pixelhand.app/mac")
        #expect(TransferInlineText.webLink("  http://example.com  ") != nil)
        #expect(TransferInlineText.webLink("file:///etc/passwd") == nil)
        #expect(TransferInlineText.webLink("javascript:alert(1)") == nil)
        #expect(TransferInlineText.webLink("x-apple-systempreferences:com.apple.preference") == nil)
        #expect(TransferInlineText.webLink("https://user:pw@example.com") == nil)
        #expect(TransferInlineText.webLink("https://example.com and more") == nil)
        #expect(TransferInlineText.webLink("https://") == nil)
        #expect(TransferInlineText.webLink("https://" + String(repeating: "a", count: 9000) + ".com") == nil)
    }

    @Test("Received text is cleaned of control characters and normalised")
    func cleanText() {
        #expect(TransferInlineText.text(from: Data("a\r\nb\u{7}\tc".utf8)) == "a\nb\tc")
        #expect(TransferInlineText.text(from: Data([0xFF, 0xFE])) == nil)
        #expect(TransferInlineText.text(from: Data(" \n ".utf8)) == nil)
    }

    @Test("Titles show a link's host or the first line")
    func titles() {
        #expect(TransferInlineText.title(for: "https://www.apple.com/mac") == "apple.com")
        #expect(TransferInlineText.title(for: "Shopping\nmilk") == "Shopping")
        #expect(TransferInlineText.title(for: String(repeating: "x", count: 100), limit: 10).count == 10)
        #expect(TransferInlineText.fileName(for: "Hello/there", kind: .text) == "there.txt")
    }
}

@Suite("TransferPolicyTests")
struct TransferPolicyTests {
    let small = TransferManifest(kind: .file, name: "a.pdf", byteCount: 5_000_000, contentType: nil)
    let medium = TransferManifest(kind: .file, name: "b.mov", byteCount: 200_000_000, contentType: nil)
    let huge = TransferManifest(kind: .file, name: "c.zip", byteCount: 3_000_000_000, contentType: nil)
    let link = TransferManifest(kind: .link, name: "Link.txt", byteCount: 30, contentType: nil)

    @Test("Unpaired senders are refused before anything else")
    func notPaired() {
        let context = TransferReceiveContext(senderIsPaired: false, lockState: .screenLocked, hasPro: false)
        #expect(TransferPolicy.decide(small, context: context) == .refuse(.notPaired))
    }

    @Test("A locked or off-console Mac refuses every transfer")
    func locked() {
        for state in [MacLockState.screenLocked, .offConsole] {
            #expect(TransferPolicy.decide(link, context: .init(senderIsPaired: true, lockState: state)) == .refuse(.macLocked))
        }
        #expect(LockPolicy.allowsIncomingTransfer(state: .unlocked))
    }

    @Test("A device without Pro refuses")
    func needsPro() {
        #expect(TransferPolicy.decide(small, context: .init(senderIsPaired: true, hasPro: false)) == .refuse(.needsPro))
    }

    @Test("Free space with headroom is required")
    func noSpace() {
        let context = TransferReceiveContext(senderIsPaired: true, freeBytes: 5_000_000 + TransferPolicy.freeSpaceHeadroom - 1)
        #expect(TransferPolicy.decide(small, context: context) == .refuse(.noSpace))
        let enough = TransferReceiveContext(senderIsPaired: true, freeBytes: 5_000_000 + TransferPolicy.freeSpaceHeadroom)
        #expect(TransferPolicy.decide(small, context: enough) == .accept)
    }

    @Test("Links, text and small files are taken quietly; larger files ask")
    func prompts() {
        let paired = TransferReceiveContext(senderIsPaired: true)
        #expect(TransferPolicy.decide(link, context: paired) == .accept)
        #expect(TransferPolicy.decide(small, context: paired) == .accept)
        #expect(TransferPolicy.decide(medium, context: paired) == .ask)
    }

    @Test("Always from this device skips the prompt up to 2 GB, never above")
    func always() {
        let always = TransferReceiveContext(senderIsPaired: true, alwaysAcceptFromSender: true)
        #expect(TransferPolicy.decide(medium, context: always) == .accept)
        #expect(TransferPolicy.decide(huge, context: always) == .ask)
    }

    @Test("Sending checks the same caps")
    func canSend() {
        #expect(TransferPolicy.canSend(kind: .file, byteCount: 0))
        #expect(!TransferPolicy.canSend(kind: .text, byteCount: 0))
        #expect(!TransferPolicy.canSend(kind: .link, byteCount: TransferPolicy.maxInlineBytes + 1))
        #expect(!TransferPolicy.canSend(kind: .photo, byteCount: TransferPolicy.maxFileBytes + 1))
    }

    @Test("The prompt times out before Loom's offer does")
    func promptTimeout() {
        #expect(TransferPolicy.promptTimeout < .seconds(120))
    }
}

@Suite("TransferOutboxTests")
struct TransferOutboxTests {
    let mac = UUID()
    let other = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func item(target: UUID?, at date: Date? = nil) -> TransferOutboxItem {
        TransferOutboxItem(kind: .file, fileName: "a.pdf", byteCount: 10, contentType: nil, targetDeviceID: target, targetName: nil, createdAt: date ?? now)
    }

    @Test("Items go to their Mac or to any Mac, oldest first, not while sending")
    func ready() {
        var box = TransferOutbox()
        let mine = item(target: mac)
        let any = item(target: nil)
        let theirs = item(target: other)
        box.add(mine); box.add(any); box.add(theirs)
        #expect(box.ready(for: mac).map(\.id) == [mine.id, any.id])
        box.markSending(mine.id, to: mac, name: "Studio")
        #expect(box.ready(for: mac).map(\.id) == [any.id])
    }

    @Test("An item for any Mac sticks to the first Mac it goes to")
    func pinsTarget() {
        var box = TransferOutbox()
        let any = item(target: nil)
        box.add(any)
        box.markSending(any.id, to: mac, name: "Studio")
        box.connectionEnded()
        #expect(box.items.first?.targetDeviceID == mac)
        #expect(box.items.first?.targetName == "Studio")
        #expect(box.items.first?.state == .paused)
        #expect(box.ready(for: other).isEmpty)
    }

    @Test("Interrupted items retry until the attempt limit")
    func attempts() {
        var box = TransferOutbox()
        let one = item(target: mac)
        box.add(one)
        for _ in 0..<(TransferOutbox.maxAttempts - 1) {
            box.markSending(one.id, to: mac, name: nil)
            let kept = box.markInterrupted(one.id)
            #expect(kept)
        }
        box.markSending(one.id, to: mac, name: nil)
        let keptLast = box.markInterrupted(one.id)
        #expect(!keptLast)
        #expect(box.items.isEmpty)
    }

    @Test("The outbox is capped, rejects duplicate ids and prunes old items")
    func capAndPrune() {
        var box = TransferOutbox()
        let first = item(target: mac, at: now.addingTimeInterval(-8 * 24 * 3600))
        let added = box.add(first)
        let again = box.add(first)
        #expect(added)
        #expect(!again)
        for _ in 1..<TransferPolicy.maxOutboxItems { box.add(item(target: mac)) }
        #expect(box.isFull)
        let overflow = box.add(item(target: mac))
        #expect(!overflow)
        let pruned = box.prune(now: now)
        #expect(pruned == [first.id])
    }

    @Test("An item's hash is kept for resumes, and the Mac list for the Share extension decodes")
    func hashAndMacs() {
        var box = TransferOutbox()
        let one = item(target: mac)
        box.add(one)
        box.setHash("abc123", for: one.id)
        #expect(TransferOutbox(storage: box.encoded()).items.first?.sha256 == "abc123")
        let macs = [TransferMacEntry(deviceID: mac, name: "Studio")]
        #expect(TransferMacEntry.decodeList(try? JSONEncoder().encode(macs)) == macs)
        #expect(TransferMacEntry.decodeList(Data("x".utf8)).isEmpty)
    }

    @Test("The outbox survives JSON storage")
    func storage() {
        var box = TransferOutbox()
        box.add(item(target: mac))
        #expect(TransferOutbox(storage: box.encoded()) == box)
        #expect(TransferOutbox(storage: Data("junk".utf8)).items.isEmpty)
    }
}

@Suite("TransferResumeTests")
struct TransferResumeTests {
    @Test("A partial prefix resumes; anything else starts over")
    func offsets() {
        #expect(TransferResume.offset(partialBytes: nil, totalBytes: 100) == 0)
        #expect(TransferResume.offset(partialBytes: 0, totalBytes: 100) == 0)
        #expect(TransferResume.offset(partialBytes: 40, totalBytes: 100) == 40)
        #expect(TransferResume.offset(partialBytes: 100, totalBytes: 100) == 0)
        #expect(TransferResume.offset(partialBytes: 140, totalBytes: 100) == 0)
    }

    @Test("Partial file names come from the id only")
    func partialName() {
        let id = UUID(uuidString: "6F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9")!
        #expect(TransferResume.partialFileName(for: id) == "6f1e2d3c-4b5a-4978-8695-a4b3c2d1e0f9.part")
    }
}

@Suite("TransferProgressMeterTests")
struct TransferProgressMeterTests {
    @Test("Rate and time left follow the samples")
    func rate() {
        var meter = TransferProgressMeter(totalBytes: 200_000_000)
        meter.update(bytes: 0, at: 0)
        meter.update(bytes: 10_000_000, at: 1)
        #expect(meter.bytesPerSecond == 10_000_000)
        #expect(meter.secondsLeft == 19)
        #expect(meter.caption == "10 MB of 200 MB · 19 s left")
        #expect(meter.fraction == 0.05)
    }

    @Test("A resume that moves backwards restarts the rate")
    func backwards() {
        var meter = TransferProgressMeter(totalBytes: 100, startingAt: 50)
        meter.update(bytes: 50, at: 0)
        meter.update(bytes: 60, at: 1)
        meter.update(bytes: 20, at: 2)
        #expect(meter.bytesPerSecond == nil)
    }

    @Test("Sizes and durations read like Finder")
    func formatting() {
        #expect(TransferProgressMeter.size(1) == "1 byte")
        #expect(TransferProgressMeter.size(999) == "999 bytes")
        #expect(TransferProgressMeter.size(1_500) == "1.5 KB")
        #expect(TransferProgressMeter.size(200_000_000) == "200 MB")
        #expect(TransferProgressMeter.size(2_000_000_000) == "2 GB")
        #expect(TransferProgressMeter.duration(8) == "8 s")
        #expect(TransferProgressMeter.duration(170) == "3 min")
        #expect(TransferProgressMeter.duration(3900) == "1 h 5 min")
    }
}

@Suite("TransferInboxTests")
struct TransferInboxTests {
    func item(_ name: String, at seconds: TimeInterval, kind: TransferKind = .file, text: String? = nil) -> TransferInboxItem {
        TransferInboxItem(id: UUID(), kind: kind, fileName: name, byteCount: 1, contentType: nil, senderName: "Studio", receivedAt: Date(timeIntervalSince1970: seconds), text: text)
    }

    @Test("Newest first, capped, unseen counted")
    func order() {
        var inbox = TransferInbox()
        inbox.add(item("a", at: 1))
        inbox.add(item("b", at: 2))
        #expect(inbox.items.map(\.fileName) == ["b", "a"])
        #expect(inbox.unseenCount == 2)
        inbox.markSeen(inbox.items[0].id)
        #expect(inbox.unseenCount == 1)
        for i in 0..<TransferInbox.maxItems { inbox.add(item("x\(i)", at: 100 + Double(i))) }
        #expect(inbox.items.count == TransferInbox.maxItems)
        #expect(!inbox.fileNames.contains("a"))
    }

    @Test("Link rows open their link; photos can go to Photos")
    func rows() {
        let link = item("Link.txt", at: 1, kind: .link, text: "https://www.apple.com")
        #expect(link.title == "apple.com")
        #expect(link.link != nil)
        #expect(item("IMG.HEIC", at: 1).isPhotoLibraryCompatible)
        #expect(!item("notes.pdf", at: 1).isPhotoLibraryCompatible)
        var inbox = TransferInbox()
        inbox.add(link)
        #expect(TransferInbox(storage: inbox.encoded()) == inbox)
    }
}

@Suite("TransferBeamAndCopyTests")
struct TransferBeamAndCopyTests {
    @Test("The beam fills with progress, turns mint when saved and drops on refusal")
    func beam() {
        #expect(TransferBeamPhase.phase(status: nil, fraction: nil) == .idle)
        #expect(TransferBeamPhase.phase(status: .awaitingApproval, fraction: nil) == .asking)
        #expect(TransferBeamPhase.phase(status: nil, fraction: 0.5) == .sending(fraction: 0.5))
        #expect(TransferBeamPhase.phase(status: .saved(landing: .downloads), fraction: 0.2) == .delivered)
        #expect(TransferBeamPhase.phase(status: .refused(reason: .declined), fraction: nil) == .stopped)
        #expect(TransferBeamPhase.sending(fraction: 0.5).litDots(of: 9) == 5)
        #expect(TransferBeamPhase.sending(fraction: 0).litDots(of: 9) == 1)
        #expect(TransferBeamPhase.delivered.litDots(of: 9) == 9)
    }

    @Test("Copy names the other device and has a line for every reason")
    func copy() {
        for reason in TransferRefusal.allCases {
            #expect(!TransferCopy.refused(reason, receiver: "Studio").isEmpty)
        }
        #expect(TransferCopy.refused(.macLocked, receiver: "Studio").hasPrefix("Studio is locked"))
        #expect(TransferCopy.saved(.downloads, receiver: "Studio") == "Saved to Downloads on Studio.")
        #expect(TransferCopy.prompt(kind: .file, name: "a.zip", byteCount: 3_000_000_000, sender: "iPad") == "iPad wants to send you “a.zip” (3 GB).")
    }
}

@Suite("TransferProtocolTests")
struct TransferProtocolTests {
    let id = UUID()

    @Test("transferStatus passes validation unchanged and the lock gate allows it")
    func validationAndGate() {
        let message = ControlMessage.sharing(.transferStatus(transferID: id, status: .saved(landing: .inbox)))
        #expect(RemoteInputValidation.sanitize(message) == message)
        for state in MacLockState.allCases {
            #expect(LockPolicy.decide(message, state: state) == .allow)
        }
    }

    @Test("transferStatus round-trips and a malformed id is refused")
    func coding() throws {
        let message = ControlMessage.sharing(.transferStatus(transferID: id, status: .refused(reason: .needsPro)))
        let data = try ControlMessageCoding.encode(message)
        #expect(try ControlMessageCoding.decode(data) == message)
        let bad = #"{"sharing":{"transferStatus":{"status":{"awaitingApproval":{}},"transferID":"../../x"}},"v":\#(PixelHandProtocol.version)}"#
        #expect(throws: (any Error).self) { try ControlMessageCoding.decode(Data(bad.utf8)) }
        let unknownReason = #"{"sharing":{"transferStatus":{"status":{"refused":{"reason":"virus"}},"transferID":"\#(id.uuidString)"}},"v":\#(PixelHandProtocol.version)}"#
        #expect(throws: (any Error).self) { try ControlMessageCoding.decode(Data(unknownReason.utf8)) }
    }

    @Test("Only the waiting status is not final")
    func finality() {
        #expect(!TransferStatus.awaitingApproval.isFinal)
        #expect(TransferStatus.failed(reason: .interrupted).isFinal)
    }
}
