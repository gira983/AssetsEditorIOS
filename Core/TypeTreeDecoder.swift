import Foundation

struct TypeTreeNodeRecord: Hashable {
    let type: String
    let name: String
    let level: Int
    let flags: UInt8
    let metaFlags: UInt32
    var children: [TypeTreeNodeRecord]

    var isArray: Bool { flags & 1 != 0 }
    var isAligned: Bool { metaFlags & 0x4000 != 0 }

    init(type: String, name: String, level: Int = 0, flags: UInt8 = 0, metaFlags: UInt32 = 0, children: [TypeTreeNodeRecord] = []) {
        self.type = type
        self.name = name
        self.level = level
        self.flags = flags
        self.metaFlags = metaFlags
        self.children = children
    }

    static let commonStringTable = Data("AABB\0AnimationClip\0AnimationCurve\0AnimationState\0Array\0Base\0BitField\0bitset\0bool\0char\0ColorRGBA\0Component\0data\0deque\0double\0dynamic_array\0FastPropertyName\0first\0float\0Font\0GameObject\0Generic Mono\0GradientNEW\0GUID\0GUIStyle\0int\0list\0long long\0map\0Matrix4x4f\0MdFour\0MonoBehaviour\0MonoScript\0m_ByteSize\0m_Curve\0m_EditorClassIdentifier\0m_Enabled\0m_ExtensionPtr\0m_GameObject\0m_Index\0m_IsArray\0m_IsStatic\0m_MetaFlag\0m_Name\0m_ObjectHideFlags\0m_PrefabInternal\0m_PrefabParentObject\0m_Script\0m_StaticEditorFlags\0m_Type\0m_Version\0Object\0pair\0PPtr<Component>\0PPtr<GameObject>\0PPtr<Material>\0PPtr<MonoBehaviour>\0PPtr<MonoScript>\0PPtr<Object>\0PPtr<Prefab>\0PPtr<Sprite>\0PPtr<TextAsset>\0PPtr<Texture>\0PPtr<Texture2D>\0PPtr<Transform>\0Prefab\0Quaternionf\0Rectf\0RectInt\0RectOffset\0second\0set\0short\0size\0SInt16\0SInt32\0SInt64\0SInt8\0staticvector\0string\0TextAsset\0TextMesh\0Texture\0Texture2D\0Transform\0TypelessData\0UInt16\0UInt32\0UInt64\0UInt8\0unsigned int\0unsigned long long\0unsigned short\0vector\0Vector2f\0Vector3f\0Vector4f\0m_ScriptingClassIdentifier\0Gradient\0Type*\0int2_storage\0int3_storage\0BoundsInt\0m_CorrespondingSourceObject\0m_PrefabInstance\0m_PrefabAsset\0FileSize\0Hash128\0RenderingLayerMask\0fixed_array\0EntityId\0LoadableObjectId\0LoadableSceneId\0".utf8)

    static func tree(from flatNodes: [TypeTreeNodeRecord]) -> TypeTreeNodeRecord? {
        guard !flatNodes.isEmpty, flatNodes[0].level == 0 else { return nil }
        var index = 0
        let root = makeNode(from: flatNodes, index: &index)
        return index == flatNodes.count ? root : nil
    }

    private static func makeNode(from flatNodes: [TypeTreeNodeRecord], index: inout Int) -> TypeTreeNodeRecord {
        var node = flatNodes[index]
        index += 1
        while index < flatNodes.count, flatNodes[index].level > node.level {
            node.children.append(makeNode(from: flatNodes, index: &index))
        }
        return node
    }
}

struct TypeTreeDecoder {
    private let bigEndian: Bool
    private let maxArrayItems = 256
    private let maxFields = 2_000

    init(bigEndian: Bool) {
        self.bigEndian = bigEndian
    }

    func decode(data: Data, start: Int, end: Int, root: TypeTreeNodeRecord) throws -> [SerializedObjectField] {
        var reader = ObjectDataReader(data: data, offset: start, end: end, bigEndian: bigEndian)
        var fieldCount = 0
        return try decode(node: root, path: root.name, depth: 0, reader: &reader, fieldCount: &fieldCount)
    }

    private func decode(node: TypeTreeNodeRecord, path: String, depth: Int, reader: inout ObjectDataReader, fieldCount: inout Int) throws -> [SerializedObjectField] {
        if node.isArray {
            guard node.children.count >= 2 else { throw SerializedFileError.malformed("array type tree node has no data child") }
            let count = try reader.readInt32()
            guard count >= 0, count <= 1_000_000 else { throw SerializedFileError.malformed("invalid serialized array length") }
            var fields = makeField(path: path, type: node.type, value: "[\(count) items]", depth: depth, fieldCount: &fieldCount)
            let child = node.children[1]
            if child.type == "UInt8" || child.type == "unsigned char" {
                let bytes = try reader.readBytes(count: Int(count))
                if node.isAligned { try reader.align4() }
                if count <= maxArrayItems {
                    for (index, byte) in bytes.enumerated() {
                        fields.append(contentsOf: makeField(path: "\(path)[\(index)]", type: child.type, value: String(byte), depth: depth + 1, fieldCount: &fieldCount))
                    }
                } else {
                    fields.append(contentsOf: makeField(path: "\(path)[…]", type: child.type, value: "\(Int(count) - maxArrayItems) additional items hidden", depth: depth + 1, fieldCount: &fieldCount))
                }
                return fields
            }
            for index in 0..<Int(count) {
                let itemPath = "\(path)[\(index)]"
                let itemFields = try decode(node: child, path: itemPath, depth: depth + 1, reader: &reader, fieldCount: &fieldCount)
                if index < maxArrayItems { fields.append(contentsOf: itemFields) }
            }
            if node.isAligned { try reader.align4() }
            if count > maxArrayItems {
                fields.append(contentsOf: makeField(path: "\(path)[…]", type: child.type, value: "\(Int(count) - maxArrayItems) additional items hidden", depth: depth + 1, fieldCount: &fieldCount))
            }
            return fields
        }

        if node.type == "string" && node.children.isEmpty {
            let value = try readString(reader: &reader)
            return makeField(path: path, type: node.type, value: value, depth: depth, fieldCount: &fieldCount)
        }

        if node.children.isEmpty {
            let value = try readPrimitive(type: node.type, reader: &reader)
            if node.isAligned { try reader.align4() }
            return makeField(path: path, type: node.type, value: value, depth: depth, fieldCount: &fieldCount)
        }

        var fields = makeField(path: path, type: node.type, value: "", depth: depth, fieldCount: &fieldCount)
        for child in node.children {
            let childPath = path.isEmpty ? child.name : "\(path).\(child.name)"
            fields.append(contentsOf: try decode(node: child, path: childPath, depth: depth + 1, reader: &reader, fieldCount: &fieldCount))
        }
        if node.isAligned { try reader.align4() }
        return fields
    }

    private func makeField(path: String, type: String, value: String, depth: Int, fieldCount: inout Int) -> [SerializedObjectField] {
        guard fieldCount < maxFields else { return [] }
        fieldCount += 1
        return [SerializedObjectField(id: "\(depth):\(path)", name: path, type: type, value: value, depth: depth, editable: isEditablePrimitive(type))]
    }

    private func readString(reader: inout ObjectDataReader) throws -> String {
        let length = try reader.readInt32()
        guard length >= 0, length <= reader.remaining else { throw SerializedFileError.malformed("invalid serialized string length") }
        let bytes = try reader.readBytes(count: Int(length))
        try reader.align4()
        return String(decoding: bytes, as: UTF8.self)
    }

    private func isEditablePrimitive(_ type: String) -> Bool {
        ["string", "SInt8", "char", "UInt8", "unsigned char", "bool", "SInt16", "short", "UInt16", "unsigned short", "SInt32", "int", "UInt32", "unsigned int", "SInt64", "long", "UInt64", "unsigned long long", "float", "double"].contains(type)
    }

    private func readPrimitive(type: String, reader: inout ObjectDataReader) throws -> String {
        switch type {
        case "SInt8", "char": return String(try reader.readInt8())
        case "UInt8", "unsigned char": return String(try reader.readUInt8())
        case "bool": return (try reader.readUInt8()) == 0 ? "false" : "true"
        case "SInt16", "short": return String(try reader.readInt16())
        case "UInt16", "unsigned short": return String(try reader.readUInt16())
        case "SInt32", "int", "Type*": return String(try reader.readInt32())
        case "UInt32", "unsigned int": return String(try reader.readUInt32())
        case "SInt64", "long", "long long": return String(try reader.readInt64())
        case "UInt64", "unsigned long long", "FileSize": return String(try reader.readUInt64())
        case "float": return String(try reader.readFloat())
        case "double": return String(try reader.readDouble())
        case "PPtr<Component>", "PPtr<GameObject>", "PPtr<Material>", "PPtr<MonoBehaviour>", "PPtr<MonoScript>", "PPtr<Object>", "PPtr<Prefab>", "PPtr<Sprite>", "PPtr<TextAsset>", "PPtr<Texture>", "PPtr<Texture2D>", "PPtr<Transform>":
            let fileID = try reader.readInt32()
            let pathID = try reader.readInt64()
            return "fileID=\(fileID), pathID=\(pathID)"
        case "GUID", "Hash128":
            return try reader.readBytes(count: 16).map { String(format: "%02X", Int($0)) }.joined()
        default:
            throw SerializedFileError.malformed("unsupported leaf type \(type)")
        }
    }
}

struct ObjectDataReader {
    let data: Data
    var offset: Int
    let end: Int
    let bigEndian: Bool

    var remaining: Int { end - offset }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset <= end, count <= end - offset else { throw SerializedFileError.malformed("object field exceeds object data") }
        let result = data[offset..<(offset + count)]
        offset += count
        return Data(result)
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < end else { throw SerializedFileError.malformed("object field exceeds object data") }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readInt8() throws -> Int8 { Int8(bitPattern: try readUInt8()) }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try [readUInt8(), readUInt8()]
        if bigEndian { return UInt16(bytes[0]) << 8 | UInt16(bytes[1]) }
        return UInt16(bytes[1]) << 8 | UInt16(bytes[0])
    }

    mutating func readInt16() throws -> Int16 { Int16(bitPattern: try readUInt16()) }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try [readUInt8(), readUInt8(), readUInt8(), readUInt8()]
        if bigEndian { return bytes.reduce(0) { ($0 << 8) | UInt32($1) } }
        return bytes.reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func readInt32() throws -> Int32 { Int32(bitPattern: try readUInt32()) }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try (0..<8).map { _ in try readUInt8() }
        if bigEndian { return bytes.reduce(0) { ($0 << 8) | UInt64($1) } }
        return bytes.reversed().reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func readInt64() throws -> Int64 { Int64(bitPattern: try readUInt64()) }

    mutating func readFloat() throws -> String {
        String(Float(bitPattern: try readUInt32()))
    }

    mutating func readDouble() throws -> String {
        String(Double(bitPattern: try readUInt64()))
    }

    mutating func align4() throws {
        let remainder = offset % 4
        if remainder != 0 { _ = try readBytes(count: 4 - remainder) }
    }
}
