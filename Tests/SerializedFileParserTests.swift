import XCTest
@testable import UnityAssetEditor

final class SerializedFileParserTests: XCTestCase {
    func testVersion22HeaderUsesModernOffsets() throws {
        var data = Data()
        data.append(contentsOf: be32(0))
        data.append(contentsOf: be32(0))
        data.append(contentsOf: be32(22))
        data.append(contentsOf: be32(0))
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: be32(4))
        data.append(contentsOf: be64(96))
        data.append(contentsOf: be64(64))
        data.append(contentsOf: repeatElement(UInt8(0), count: 8))
        data.append(contentsOf: [UInt8]("2022.3.0f1\0", utf8: true))
        data.append(contentsOf: be32(0))
        data.append(0)
        data.append(contentsOf: be32(0))
        data.append(contentsOf: be32(0))
        data.append(contentsOf: be32(0))
        data.append(contentsOf: be32(0))
        data.append(contentsOf: [UInt8]("\0", utf8: true))
        data.append(contentsOf: repeatElement(UInt8(0), count: 32))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = try SerializedFileParser().open(url: url)
        XCTAssertEqual(session.header.version, 22)
        XCTAssertEqual(session.header.metadataSize, 4)
        XCTAssertEqual(session.header.dataOffset, 64)
        XCTAssertEqual(session.objects.count, 0)
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)]
    }

    private func be64(_ value: UInt64) -> [UInt8] {
        (0..<8).reversed().map { UInt8(value >> (UInt64($0) * 8)) }
    }
}
