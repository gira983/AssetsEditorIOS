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
}
