//
//  StatusStripTextTests.swift
//  PixelHandCoreTests
//
//  The dot-matrix font's punctuation (VQ-071), the status strip's
//  word-boundary shortening (VQ-070, VQ-074) and the widget strip's
//  detail (VQ-072).
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("Dot-matrix font coverage")
struct DotMatrixFontCoverageTests {
    /// Every character the app's dot-matrix strings use, apart from letters
    /// and digits: the spec's list plus what Mac names carry.
    static let punctuation: [Character] = ["'", "’", "-", "·", "/", ":", "&", "(", ")", "?", "!", ",", ".", "%", "+", "<", ">"]

    @Test("Every glyph renders inside its 5 × 7 box and lights at least one dot")
    func everyGlyphRenders() {
        for character in DotMatrixFont.characters where character != " " {
            let cells = DotMatrixFont.litCells(String(character))
            #expect(!cells.isEmpty, "\(character) renders nothing")
            #expect(cells.allSatisfy { (0..<DotMatrixFont.columns).contains($0.x) && (0..<DotMatrixFont.rows).contains($0.y) }, "\(character) leaves its box")
            #expect(DotMatrixFont.unlitCells(String(character)).count + cells.count == DotMatrixFont.columns * DotMatrixFont.rows)
        }
    }

    @Test("The app's punctuation is in the font and never draws as a space")
    func punctuationIsCovered() {
        for character in Self.punctuation {
            #expect(DotMatrixFont.characters.contains(character), "missing \(character)")
            #expect(DotMatrixFont.normalized(String(character)) == [character])
        }
    }

    @Test("No two glyphs share a pattern, except the two apostrophes")
    func patternsAreDistinct() {
        var seen: [UInt64: Character] = [:]
        for character in DotMatrixFont.characters.sorted() {
            guard let bits = DotMatrixFont.pattern(for: character) else { continue }
            if let other = seen[bits] {
                #expect(Set([other, character]) == Set(["'", "’"]), "\(other) and \(character) look the same")
            }
            seen[bits] = character
        }
    }

    @Test("An apostrophe in a Mac name is drawn, not left as a gap")
    func apostropheInName() {
        for name in ["Muhammad's MacBook Pro", "Muhammad’s MacBook Pro", "Muhammad‘s MacBook Pro"] {
            let normalized = DotMatrixFont.normalized(name)
            #expect(!normalized.contains(" ") || normalized[8] != " ", "\(name)")
            #expect(normalized[8] == "'" || normalized[8] == "’")
            #expect(DotMatrixFont.litCells(name).contains { $0.x / DotMatrixFont.advance == 8 })
        }
    }

    @Test("Accented letters draw without their accents; typographic dashes as hyphens")
    func folding() {
        #expect(DotMatrixFont.normalized("José’s Mac") == Array("JOSE’S MAC"))
        #expect(DotMatrixFont.normalized("Zoë – Studio") == Array("ZOE - STUDIO"))
        #expect(DotMatrixFont.normalized("Ångström") == Array("ANGSTROM"))
        #expect(DotMatrixFont.pattern(for: "é") == DotMatrixFont.pattern(for: "E"))
        #expect(DotMatrixFont.normalized("Mac 🍎") == Array("MAC  "))
    }

    @Test("Every status word and counter the widgets draw is fully covered")
    func widgetStrings() {
        let strings = ["PIXEL HAND", "LOCKED", "OFFLINE", "LIVE · 60 FPS", "01/03", "4.1/9.4 MB", "WI-FI", "PRO", "Q&A (BETA)?", "GO!"]
        for string in strings {
            for character in string.uppercased() {
                #expect(DotMatrixFont.resolve(character) != nil, "\(string): \(character)")
            }
        }
    }
}

@Suite("Status strip text")
struct StatusStripTextTests {
    @Test("A Mac's name shortens at word boundaries, longest first")
    func nameForms() {
        #expect(StatusStripText.nameForms("Muhammad's MacBook Pro") == ["Muhammad's MacBook Pro", "Muhammad's MacBook", "Muhammad's"])
        #expect(StatusStripText.nameForms("  Studio  ") == ["Studio"])
        #expect(StatusStripText.nameForms("   ").isEmpty)
        // A trailing word the font can't draw is dropped from every form.
        #expect(StatusStripText.nameForms("Studio 🍎") == ["Studio"])
        #expect(StatusStripText.nameForms("Studio - Upstairs") == ["Studio - Upstairs", "Studio"])
    }

    @Test("No candidate ever cuts a word")
    func neverMidWord() {
        let name = "Muhammad's MacBook Pro"
        let words = Set(name.split(separator: " ").map(String.init) + ["Google", "Chrome", "·"])
        for line in StatusStripText.candidates(name: name, details: ["Google Chrome"]) {
            for word in line.split(separator: " ") {
                #expect(words.contains(String(word)), "\(line) cuts \(word)")
            }
        }
    }

    @Test("The name shortens before the front app is dropped")
    func detailKeptLonger() {
        let lines = StatusStripText.candidates(name: "Muhammad's MacBook Pro", details: ["Google Chrome"])
        #expect(lines == [
            "Muhammad's MacBook Pro · Google Chrome",
            "Muhammad's MacBook · Google Chrome",
            "Muhammad's · Google Chrome",
            "Muhammad's MacBook Pro",
            "Muhammad's MacBook",
            "Muhammad's",
        ])
    }

    @Test("Fitting picks the longest line that fits, and nothing when even a word doesn't")
    func fit() {
        let name = "Muhammad's MacBook Pro"
        // The small widget's strip: about 13 characters at pitch 1.6.
        #expect(StatusStripText.fit(name: name, details: [], maxCells: 13 * 6 - 1) == "Muhammad's")
        #expect(StatusStripText.fit(name: name, details: ["Xcode"], maxCells: 40 * 6) == "Muhammad's MacBook Pro · Xcode")
        #expect(StatusStripText.fit(name: name, details: ["Xcode"], maxCells: 20 * 6) == "Muhammad's · Xcode")
        #expect(StatusStripText.fit(name: name, details: [], maxCells: 5 * 6) == nil)
        #expect(StatusStripText.fit(name: nil, details: ["Offline"], maxCells: 60) == "Offline")
        // Never the old prefix(6) cut.
        #expect(StatusStripText.candidates(name: name, details: []).allSatisfy { $0 != "Muhamm" })
    }

    @Test("Very long single words stay whole; very long names start from their first fitting form")
    func longNames() {
        #expect(StatusStripText.nameForms(String(repeating: "A", count: 40)) == [String(repeating: "A", count: 40)])
        let long = "The Very Long Named Mac Studio In The Upstairs Office"
        let forms = StatusStripText.nameForms(long)
        #expect(forms.allSatisfy { $0.count <= StatusStripText.maxNameCharacters })
        #expect(forms.last == "The")
    }
}

@Suite("Widget strip detail")
struct WidgetStripDetailTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Live names the front app, locked and offline say so, unknown says nothing")
    func details() {
        let mac = RecentMac(id: "A", name: "Studio", lastConnected: now)
        #expect(mac.stripDetails.isEmpty)
        #expect(!mac.isLive)
        let live = mac.with(frontApp: "Xcode", glance: .live)
        #expect(live.stripDetails == ["Xcode"])
        #expect(live.isLive)
        #expect(mac.with(frontApp: "Xcode", glance: .locked).stripDetails == ["LOCKED"])
        let offline = live.with(frontApp: "Xcode", glance: .offline)
        #expect(offline.stripDetails == ["OFFLINE"])
        #expect(offline.frontApp == nil)
        #expect(!offline.isLive)
        #expect(mac.with(frontApp: "  ", glance: .live).stripDetails.isEmpty)
    }

    @Test("Older snapshots without the glance fields still decode")
    func olderSnapshotDecodes() throws {
        let json = #"{"generatedAt":1000000,"isPro":false,"allKeys":[],"widgetKeys":[],"version":1,"macs":[{"id":"A","name":"Studio","lastConnected":1000000}]}"#
        let snapshot = WidgetDeckSnapshot.decode(Data(json.utf8))
        #expect(snapshot.currentMac?.name == "Studio")
        #expect(snapshot.currentMac?.glance == nil)
        #expect(snapshot.currentMac?.stripDetails == [])
    }

    @Test("The glance round-trips and survives recording the Mac again")
    func roundTrip() throws {
        let mac = RecentMac(id: "A", name: "Studio", lastConnected: now).with(frontApp: "Pages", glance: .live)
        let snapshot = WidgetDeckSnapshot(generatedAt: now, widgetKeys: [], allKeys: [], macs: [mac], isPro: false)
        #expect(WidgetDeckSnapshot.decode(try WidgetDeckSnapshot.encode(snapshot)) == snapshot)
        #expect(RecentMac.recording(mac, in: []).first?.frontApp == "Pages")
    }
}
