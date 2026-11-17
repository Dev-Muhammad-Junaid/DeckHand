//
//  DuplicateBundleIDTests.swift
//  PixelHandCoreTests
//
//  The iOS app crashed when the Mac reported the same bundle ID twice (two
//  copies of an app installed, or a running-apps list with a repeat):
//  `Dictionary(uniqueKeysWithValues:)` traps on duplicate keys. The Quick
//  Actions bar and the window picker now build their lookups through these
//  helpers instead.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct DuplicateBundleIDTests {

    @Test func appLookupKeepsTheFirstCopy() {
        let apps = [
            InstalledAppInfo(bundleID: "com.apple.Safari", displayName: "Safari", iconData: nil),
            InstalledAppInfo(bundleID: "com.example.editor", displayName: "Editor", iconData: nil),
            InstalledAppInfo(bundleID: "com.apple.Safari", displayName: "Safari (copy)", iconData: Data([1])),
        ]
        let lookup = InstalledAppInfo.byBundleID(apps)
        #expect(lookup.count == 2)
        #expect(lookup["com.apple.Safari"]?.displayName == "Safari")
        #expect(lookup["com.example.editor"]?.displayName == "Editor")
    }

    @Test func recencyRankKeepsTheEarliestPosition() {
        let rank = InstalledAppInfo.recencyRank(of: ["a", "b", "a", "c", "b"])
        #expect(rank == ["a": 0, "b": 1, "c": 3])
    }

    @Test func emptyInputs() {
        #expect(InstalledAppInfo.byBundleID([]).isEmpty)
        #expect(InstalledAppInfo.recencyRank(of: []).isEmpty)
    }
}
