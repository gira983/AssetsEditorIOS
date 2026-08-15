import XCTest
@testable import UnityAssetEditor

final class Phase3ParserTests: XCTestCase {
    func testTypeTreeDecoderReadsAlignedPrimitiveFields() throws {
        let data = Data([0x2A, 0x00, 0x00, 0x00, 0x01])
        let root = TypeTreeNodeRecord(
            type: "Root",
            name: "root",
            children: [
                TypeTreeNodeRecord(type: "int", name: "number"),
                TypeTreeNodeRecord(type: "bool", name: "enabled")
            ]
        )
        let fields = try TypeTreeDecoder(bigEndian: false).decode(data: data, start: 0, end: data.count, root: root)
        XCTAssertTrue(fields.contains { $0.name == "root.number" && $0.value == "42" })
        XCTAssertTrue(fields.contains { $0.name == "root.enabled" && $0.value == "true" })
    }

    func testTypeTreeDecoderReadsString() throws {
        let data = Data([0x03, 0x00, 0x00, 0x00, 0x61, 0x62, 0x63])
        let root = TypeTreeNodeRecord(type: "string", name: "value")
        let fields = try TypeTreeDecoder(bigEndian: false).decode(data: data, start: 0, end: data.count, root: root)
        XCTAssertEqual(fields.first?.value, "abc")
    }

    func testModernHeaderUsesTheExtendedFieldsAndAllowsPadding() throws {
        var data = Data()
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 22])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 80])
        data.append(contentsOf: [0, 0, 0, 64])
        data.append(contentsOf: Array(repeating: UInt8(0), count: 8))
        data.append(contentsOf: Array("2021.3.0f1".utf8) + [0])
        data.append(contentsOf: [0, 0, 0, 19, 0])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try SerializedFileParser().open(url: url))
    }
}
