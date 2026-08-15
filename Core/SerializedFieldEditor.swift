import Foundation

struct SerializedFieldEditor {
    func apply(
        edits: [String: String],
        to object: SerializedObjectInfo,
        in session: SerializedFileSession
    ) throws -> Data {
        guard !edits.isEmpty else { return session.data }
        guard let record = session.objectRecords.first(where: { $0.pathID == object.pathID }) else {
            throw SerializedFileError.malformed("object not found")
        }
        guard let typeRecord = session.typeRecords.first(where: { $0.typeID == record.typeID && ($0.scriptTypeIndex == record.scriptTypeIndex || record.typeID != 114) }), let root = typeRecord.typeTree else {
            throw SerializedFieldEditError.unsupportedType(object.typeName)
        }
        let objectStart = Int(object.byteOffset)
        let objectSize = Int(record.byteSize)
        guard objectSize >= 0, objectStart >= 0, objectStart <= session.data.count - objectSize else {
            throw SerializedFileError.malformed("object range exceeds file")
        }
        let objectEnd = objectStart + objectSize
        var reader = SerializedObjectRewriter(data: session.data, offset: objectStart, end: objectEnd, bigEndian: session.header.bigEndian, edits: edits)
        try reader.rewrite(node: root, path: root.name)
        guard reader.offset <= objectEnd else {
            throw SerializedFieldEditError.objectLayoutMismatch(expected: objectEnd, actual: reader.offset)
        }
        let editedPaths = Set(edits.keys)
        let knownPaths = reader.visitedEditablePaths
        guard editedPaths.isSubset(of: knownPaths) else {
            let unknown = editedPaths.subtracting(knownPaths).sorted().first ?? ""
            throw SerializedFieldEditError.unknownField(unknown)
        }
        guard reader.data.count == session.data.count else {
            throw SerializedFieldEditError.objectSizeChanged
        }
        data = reader.data
        return data
    }

    func currentValue(for field: SerializedObjectField, object: SerializedObjectInfo, in session: SerializedFileSession) throws -> String {
        let fields = try TypeTreeDecoder(bigEndian: session.header.bigEndian).decode(
            data: session.data,
            start: Int(object.byteOffset),
            end: Int(object.byteOffset + UInt64(object.byteSize)),
            root: try rootNode(for: object, in: session)
        )
        guard let decoded = fields.first(where: { $0.name == field.name }) else {
            throw SerializedFieldEditError.unknownField(field.name)
        }
        return decoded.value
    }

    private func rootNode(for object: SerializedObjectInfo, in session: SerializedFileSession) throws -> TypeTreeNodeRecord {
        guard let record = session.objectRecords.first(where: { $0.pathID == object.pathID }),
              let typeRecord = session.typeRecords.first(where: { $0.typeID == record.typeID && ($0.scriptTypeIndex == record.scriptTypeIndex || record.typeID != 114) }),
              let root = typeRecord.typeTree else {
            throw SerializedFieldEditError.unsupportedType(object.typeName)
        }
        return root
    }
}

enum SerializedFieldEditError: LocalizedError {
    case unsupportedType(String)
    case invalidValue(type: String, value: String)
    case objectSizeChanged
    case unknownField(String)
    case objectLayoutMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let type): return "Editing \(type) fields is not supported yet."
        case .invalidValue(let type, let value): return "\"\(value)\" is not a valid \(type) value."
        case .objectSizeChanged: return "The edited object changed size; only in-place edits are permitted."
        case .unknownField(let path): return "The field \(path) was not found in the object layout."
        case .objectLayoutMismatch: return "The object layout could not be reproduced safely; no changes were written."
        }
    }
}

private struct SerializedObjectRewriter {
    var data: Data
    var offset: Int
    let end: Int
    let bigEndian: Bool
    let edits: [String: String]
    var visitedEditablePaths = Set<String>()

    mutating func rewrite(node: TypeTreeNodeRecord, path: String) throws {
        if node.isArray {
            guard node.children.count >= 2 else { throw SerializedFieldEditError.unsupportedType(node.type) }
            let count = try readInt32()
            guard count >= 0, count <= 1_000_000 else { throw SerializedFileError.malformed("invalid serialized array length") }
            for index in 0..<Int(count) {
                try rewrite(node: node.children[1], path: "\(path)[\(index)]")
            }
            if node.isAligned { try align4() }
            return
        }
        if node.type == "string" {
            try rewriteString(path: path)
            if node.isAligned { try align4() }
            return
        }
        if node.children.isEmpty {
            try rewritePrimitive(type: node.type, path: path)
            if node.isAligned { try align4() }
            return
        }
        for child in node.children {
            let childPath = path.isEmpty ? child.name : "\(path).\(child.name)"
            try rewrite(node: child, path: childPath)
        }
        if node.isAligned { try align4() }
    }

    mutating func rewriteString(path: String) throws {
        let length = try readInt32()
        guard length >= 0, Int64(length) <= Int64(end - offset) else { throw SerializedFileError.malformed("invalid serialized string length") }
        let bytesStart = offset
        _ = try readBytes(count: Int(length))
        let padding = (4 - (offset % 4)) % 4
        guard let value = edits[path] else {
            if padding > 0 { _ = try readBytes(count: padding) }
            return
        }
        visitedEditablePaths.insert(path)
        let encoded = Array(value.utf8)
        guard encoded.count == Int(length) else { throw SerializedFieldEditError.objectSizeChanged }
        data.replaceSubrange(bytesStart..<(bytesStart + encoded.count), with: encoded)
        if padding > 0 { _ = try readBytes(count: padding) }
    }

    mutating func rewritePrimitive(type: String, path: String) throws {
        guard let value = edits[path] else {
            _ = try readPrimitiveBytes(type: type)
            return
        }
        visitedEditablePaths.insert(path)
        switch type {
        case "SInt8", "char": writeInt8(try parseInt8(value, type: type))
        case "UInt8", "unsigned char": writeUInt8(try parseUInt8(value, type: type))
        case "bool": writeUInt8(try parseBool(value, type: type) ? 1 : 0)
        case "SInt16", "short": writeUInt16(UInt16(bitPattern: try parseInt16(value, type: type)))
        case "UInt16", "unsigned short": writeUInt16(try parseUInt16(value, type: type))
        case "SInt32", "int", "Type*": writeUInt32(UInt32(bitPattern: try parseInt32(value, type: type)))
        case "UInt32", "unsigned int": writeUInt32(try parseUInt32(value, type: type))
        case "SInt64", "long", "long long": writeUInt64(UInt64(bitPattern: try parseInt64(value, type: type)))
        case "UInt64", "unsigned long long", "FileSize": writeUInt64(try parseUInt64(value, type: type))
        case "float": writeUInt32(try parseFloatBits(value, type: type))
        case "double": writeUInt64(try parseDoubleBits(value, type: type))
        default:
            _ = try readPrimitiveBytes(type: type)
            throw SerializedFieldEditError.unsupportedType(type)
        }
    }

    mutating func readPrimitiveBytes(type: String) throws -> Data {
        let count: Int
        switch type {
        case "SInt8", "char", "UInt8", "unsigned char", "bool": count = 1
        case "SInt16", "short", "UInt16", "unsigned short": count = 2
        case "SInt32", "int", "UInt32", "unsigned int", "float", "Type*": count = 4
        case "SInt64", "long", "long long", "UInt64", "unsigned long long", "FileSize", "double": count = 8
        case "GUID", "Hash128": count = 16
        default: throw SerializedFieldEditError.unsupportedType(type)
        }
        return try readBytes(count: count)
    }

    mutating func readInt32() throws -> Int32 { Int32(bitPattern: try readUInt32()) }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        let values = Array(bytes)
        if bigEndian { return values.reduce(0) { ($0 << 8) | UInt32($1) } }
        return values.reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset >= 0, offset <= end, count <= end - offset else { throw SerializedFileError.malformed("object field exceeds object data") }
        let result = Data(data[offset..<(offset + count)])
        offset += count
        return result
    }

    mutating func align4() throws { let padding = (4 - (offset % 4)) % 4; if padding > 0 { _ = try readBytes(count: padding) } }

    mutating func writeInt8(_ value: Int8) { writeUInt8(UInt8(bitPattern: value)) }
    mutating func writeUInt8(_ value: UInt8) { data[offset] = value; offset += 1 }

    mutating func writeUInt16(_ value: UInt16) {
        let bytes = bigEndian ? [UInt8(value >> 8), UInt8(value & 0xff)] : [UInt8(value & 0xff), UInt8(value >> 8)]
        data.replaceSubrange(offset..<(offset + 2), with: bytes); offset += 2
    }

    mutating func writeUInt32(_ value: UInt32) {
        let bytes = bigEndian ? [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)] : [UInt8(value), UInt8(value >> 8), UInt8(value >> 16), UInt8(value >> 24)]
        data.replaceSubrange(offset..<(offset + 4), with: bytes); offset += 4
    }

    mutating func writeUInt64(_ value: UInt64) {
        let bytes = bigEndian ? (0..<8).reversed().map { UInt8(value >> (UInt64($0) * 8)) } : (0..<8).map { UInt8(value >> (UInt64($0) * 8)) }
        data.replaceSubrange(offset..<(offset + 8), with: bytes); offset += 8
    }

    func parseInt8(_ value: String, type: String) throws -> Int8 { guard let parsed = Int8(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseUInt8(_ value: String, type: String) throws -> UInt8 { guard let parsed = UInt8(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseBool(_ value: String, type: String) throws -> Bool { let v = value.lowercased(); guard v == "true" || v == "false" || v == "1" || v == "0" else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return v == "true" || v == "1" }
    func parseInt16(_ value: String, type: String) throws -> Int16 { guard let parsed = Int16(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseUInt16(_ value: String, type: String) throws -> UInt16 { guard let parsed = UInt16(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseInt32(_ value: String, type: String) throws -> Int32 { guard let parsed = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseUInt32(_ value: String, type: String) throws -> UInt32 { guard let parsed = UInt32(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseInt64(_ value: String, type: String) throws -> Int64 { guard let parsed = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseUInt64(_ value: String, type: String) throws -> UInt64 { guard let parsed = UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed }
    func parseFloatBits(_ value: String, type: String) throws -> UInt32 { guard let parsed = Float(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed.bitPattern }
    func parseDoubleBits(_ value: String, type: String) throws -> UInt64 { guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SerializedFieldEditError.invalidValue(type: type, value: value) }; return parsed.bitPattern }
}
