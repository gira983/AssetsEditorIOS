import XCTest
@testable import UnityAssetEditor

final class Phase4Tests: XCTestCase {
    func testHexSearchFindsHexAndASCIIMatches() {
        let data = Data([0x00, 0xDE, 0xAD, 0xDE, 0xAD, 0x41, 0x42])
        let service = HexSearchService()
        XCTAssertEqual(service.matches(in: data, query: "DE AD", mode: .hex), [1, 3])
        XCTAssertEqual(service.matches(in: data, query: "AB", mode: .ascii), [5])
    }

    func testDiffServiceReportsChangedRanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("original")
        let currentURL = directory.appendingPathComponent("current")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: originalURL)
        try Data([0x00, 0x09, 0x02, 0x03, 0x04]).write(to: currentURL)

        let summary = try AssetDiffService().compare(originalURL: originalURL, currentURL: currentURL)
        XCTAssertEqual(summary.changedByteCount, 2)
        XCTAssertEqual(summary.ranges.count, 2)
        XCTAssertEqual(summary.ranges[0].startOffset, 1)
        XCTAssertEqual(summary.ranges[1].startOffset, 4)
    }
}
