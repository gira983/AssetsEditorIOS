import XCTest
@testable import UnityAssetEditor

final class SerializedFileHeaderTests: XCTestCase {
    func testLegacyHeaderUsesMetadataImmediatelyAfter20ByteHeader() throws {
        let data = makeLegacyFixture(version: 21, dataOffset: 36)
        let session = try SerializedFileParser().open(url: writeFixture(data))
        XCTAssertEqual(session.info.formatVersion, 21)
        XCTAssertEqual(session.info.metadataSize, 1)
        XCTAssertEqual(session.info.dataOffset, 36)
        XCTAssertEqual(session.objects.count, 0)
    }

    func testModernHeaderUses64BitFieldsAfter28BytePrefix() throws {
        let data = makeModernFixture(version: 22, dataOffset: 64)
        let session = try SerializedFileParser().open(url: writeFixture(data))
        XCTAssertEqual(session.info.formatVersion, 22)
        XCTAssertEqual(session.info.metadataSize, 1)
        XCTAssertEqual(session.info.dataOffset, 64)
        XCTAssertEqual(session.objects.count, 0)
    }

    private func makeLegacyFixture(version: UInt32, dataOffset: UInt32) -> Data {
        var data = Data()
        data.appendBE(UInt32(1))
        data.appendBE(UInt32(dataOffset))
        data.appendBE(version)
        data.appendBE(dataOffset)
        data.append(contentsOf: [0, 0, 0, 0])
        data.appendCString("2021.3.0f1")
        data.appendBE(UInt32(0))
        data.append(contentsOf: [0])
        data.appendBE(UInt32(0))
        data.appendBE(UInt32(0))
        data.appendBE(UInt32(0))
        data.appendCString("")
        data.append(contentsOf: repeatElement(UInt8(0), count: max(0, Int(dataOffset) - data.count)))
        return data
    }

    private func makeModernFixture(version: UInt32, dataOffset: UInt64) -> Data {
        var data = Data()
        data.appendBE(UInt32(1))
        data.appendBE(UInt32(0))
        data.appendBE(version)
        data.appendBE(UInt32(0))
        data.append(contentsOf: [0, 0, 0, 0])
        data.appendBE(UInt32(1))
        data.appendBE(UInt64(dataOffset))
        data.appendBE(UInt64(dataOffset))
        data.append(contentsOf: repeatElement(UInt8(0), count: 8))
        data.appendCString("2021.3.0f1")
        data.appendBE(UInt32(0))
        data.append(contentsOf: [0])
        data.appendBE(UInt32(0))
        data.appendBE(UInt32(0))
        data.appendBE(UInt32(0))
        data.appendCString("")
        data.append(contentsOf: repeatElement(UInt8(0), count: max(0, Int(dataOffset) - data.count)))
        return data
    }

    private func writeFixture(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
}

private extension Data {
    mutating func appendBE(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)])
    }

    mutating func appendBE(_ value: UInt64) {
        append(contentsOf: (0..<8).reversed().map { UInt8(value >> (UInt64($0) * 8)) })
    }

    mutating func appendCString(_ value: String) {
        append(contentsOf: value.utf8)
        append(0)
    }
}