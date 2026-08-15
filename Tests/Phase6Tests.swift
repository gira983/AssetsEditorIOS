import XCTest
@testable import UnityAssetEditor

final class Phase6Tests: XCTestCase {
    func testLZ4DecoderExpandsRepeatedMatch() throws {
        let compressed = Data([0x32, 0x61, 0x62, 0x63, 0x03, 0x00])
        let output = try LZ4DecoderTestAccess.decode(compressed, expectedSize: 9)
        XCTAssertEqual(output, Data("abcabcabc", encoding: .utf8))
    }

    func testLZ4DecoderRejectsWrongOutputSize() {
        let compressed = Data([0x30, 0x61, 0x62, 0x63])
        XCTAssertThrowsError(try LZ4DecoderTestAccess.decode(compressed, expectedSize: 4))
    }
}

private enum LZ4DecoderTestAccess {
    static func decode(_ data: Data, expectedSize: Int) throws -> Data {
        try AssetBundleTestLZ4.decode(data, expectedSize: expectedSize)
    }
}
