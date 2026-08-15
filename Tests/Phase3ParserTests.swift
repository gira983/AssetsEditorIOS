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

    func testVersion22HeaderUsesExtendedLayout() throws {
        var bytes = Data()
        appendUInt32BE(0, to: &bytes)
        appendUInt32BE(0, to: &bytes)
        appendUInt32BE(22, to: &bytes)
        appendUInt32BE(0, to: &bytes)
        bytes.append(0)
        bytes.append(contentsOf: [0, 0, 0])
        appendUInt32BE(10, to: &bytes)
        appendUInt64BE(100, to: &bytes)
        appendUInt64BE(64, to: &bytes)
        bytes.append(contentsOf: repeatElement(UInt8(0), count: 8))
        bytes.append(contentsOf: Data(repeating: 0, count: 40))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try SerializedFileParser().open(url: url))
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value >> 24)); data.append(UInt8(value >> 16)); data.append(UInt8(value >> 8)); data.append(UInt8(value))
    }

    private func appendUInt64BE(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8(value >> UInt64(shift))) }
    }
}
