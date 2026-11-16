//
//  DuplicateBundleIDTests.swift
//  DeckHandTests
//
//  The iOS app crashed when the Mac reported the same bundle ID twice (two
//  copies of an app installed, or a running-apps list with a repeat):
//  `Dictionary(uniqueKeysWithValues:)` traps on duplicate keys. The Quick
//  Actions bar and the window picker now build their lookups through these
//  helpers instead.
//

import XCTest

final class DuplicateBundleIDTests: XCTestCase {

    func testAppLookupKeepsTheFirstCopy() {
        let apps = [
            InstalledAppInfo(bundleID: "com.apple.Safari", displayName: "Safari", iconData: nil),
            InstalledAppInfo(bundleID: "com.example.editor", displayName: "Editor", iconData: nil),
            InstalledAppInfo(bundleID: "com.apple.Safari", displayName: "Safari (copy)", iconData: Data([1])),
        ]
        let lookup = InstalledAppInfo.byBundleID(apps)
        XCTAssertEqual(lookup.count, 2)
        XCTAssertEqual(lookup["com.apple.Safari"]?.displayName, "Safari")
        XCTAssertEqual(lookup["com.example.editor"]?.displayName, "Editor")
    }

    func testRecencyRankKeepsTheEarliestPosition() {
        let rank = InstalledAppInfo.recencyRank(of: ["a", "b", "a", "c", "b"])
        XCTAssertEqual(rank, ["a": 0, "b": 1, "c": 3])
    }

    func testEmptyInputs() {
        XCTAssertTrue(InstalledAppInfo.byBundleID([]).isEmpty)
        XCTAssertTrue(InstalledAppInfo.recencyRank(of: []).isEmpty)
    }
}
