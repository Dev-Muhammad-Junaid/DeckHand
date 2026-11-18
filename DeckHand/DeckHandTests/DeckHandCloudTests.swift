//
//  DeckHandCloudTests.swift
//  DeckHandTests
//
//  The CloudKit switch lives in the app (it imports LoomCloudKit), so this
//  check stays in the app test bundle; the status mapping it feeds is
//  tested in PixelHandCore (`CloudRecognitionStatusTests`).
//

import Testing

@Suite struct DeckHandCloudTests {

    @Test("This build has CloudKit on, with the registered container")
    func thisBuildHasCloudKitOn() {
        #expect(DeckHandCloud.isCloudEnabled)
        #expect(DeckHandCloud.containerIdentifier == "iCloud.com.widgetsflow.pixelhand")
    }
}
