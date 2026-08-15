import Foundation

struct SerializedFileParser {
    func open(url: URL) throws -> SerializedFileSession {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw SerializedFileError.malformed("could not read file")
        }
        guard data.count >= 20 else { throw SerializedFileError.notSerializedFile }
        var reader = SerializedReader(data: data)
        let header: SerializedHeader
        do {
            header = try reader.readHeader()
        } catch let error as SerializedFileError {
            throw error
        } catch {
            throw SerializedFileError.notSerializedFile
        }
        guard header.metadataStart <= UInt64(data.count) else {
            throw SerializedFileError.malformed("invalid metadata start")
        }
        let metadataEnd = header.metadataStart.addingReportingOverflow(header.metadataSize)
        guard !metadataEnd.overflow, metadataEnd.partialValue <= UInt64(data.count) else {
            throw SerializedFileError.malformed("invalid metadata range")
        }
        guard header.dataOffset >= 0, header.dataOffset <= Int64(data.count) else {
            throw SerializedFileError.malformed("invalid data offset")
        }
        reader.offset = Int(header.metadataStart)
        let metadata = try reader.readMetadata(version: header.version)
        guard reader.offset <= Int(metadataEnd.partialValue) else {
            throw SerializedFileError.malformed("metadata exceeds declared size")
        }
        let objects = metadata.objects.map { record in
            let typeName = unityTypeName(record.typeID)
            let absoluteOffset = header.dataOffset.addingReportingOverflow(record.byteOffset)
            let resolvedOffset = absoluteOffset.overflow ? header.dataOffset : absoluteOffset.partialValue
            return SerializedObjectInfo(id: "\(record.pathID)", pathID: record.pathID, typeID: record.typeID, byteOffset: UInt64(max(0, resolvedOffset)), byteSize: record.byteSize, typeName: typeName, displayName: "\(typeName) · \(record.pathID)")
        }
        return SerializedFileSession(data: data, info: SerializedFileInfo(formatVersion: header.version, fileSize: UInt64(max(0, header.fileSize)), metadataSize: UInt64(header.metadataSize), dataOffset: UInt64(max(0, header.dataOffset)), unityVersion: metadata.unityVersion, targetPlatform: metadata.targetPlatform, objectCount: objects.count, typeCount: metadata.typeCount, externalCount: metadata.externalCount, isBigEndian: header.bigEndian), objects: objects, objectRecords: metadata.objects, typeRecords: metadata.typeRecords, typeTreeEnabled: metadata.typeTreeEnabled, header: header)
    }

    func fields(for object: SerializedObjectInfo, in session: SerializedFileSession) throws -> [SerializedObjectField] {
        guard let record = session.objectRecords.first(where: { $0.pathID == object.pathID }) else { throw SerializedFileError.malformed("object not found") }
        let start = Int(object.byteOffset)
        let objectSize = Int(record.byteSize)
        guard objectSize >= 0, start >= 0, start <= session.data.count - objectSize else { throw SerializedFileError.malformed("object range exceeds file") }
        let end = start + objectSize
        if session.typeTreeEnabled, let typeRecord = session.typeRecords.first(where: { $0.typeID == record.typeID && ($0.scriptTypeIndex == record.scriptTypeIndex || record.typeID != 114) }), let root = typeRecord.typeTree {
            return try TypeTreeDecoder(bigEndian: session.header.bigEndian).decode(data: session.data, start: start, end: end, root: root)
        }
        return fallbackFields(for: record, start: start, end: end, data: session.data)
    }

    private func fallbackFields(for record: ObjectRecord, start: Int, end: Int, data: Data) -> [SerializedObjectField] {
        let bytes = data[start..<end]
        let hexPreview = bytes.prefix(32).map { String(format: "%02X", Int($0)) }.joined(separator: " ")
        return [
            SerializedObjectField(id: "range", name: "Byte range", type: "offset", value: "0x\(String(start, radix: 16))–0x\(String(end, radix: 16))", depth: 0, editable: false),
            SerializedObjectField(id: "size", name: "Serialized size", type: "bytes", value: "\(record.byteSize) bytes", depth: 0, editable: false),
            SerializedObjectField(id: "preview", name: "Hex preview", type: "bytes", value: hexPreview.isEmpty ? "—" : hexPreview, depth: 0, editable: false)
        ]
    }
}

struct SerializedFileSession {
    let data: Data
    let info: SerializedFileInfo
    let objects: [SerializedObjectInfo]
    let objectRecords: [ObjectRecord]
    let typeRecords: [SerializedTypeRecord]
    let typeTreeEnabled: Bool
    let header: SerializedHeader
}

struct SerializedHeader {
    let metadataSize: UInt64
    let fileSize: Int64
    let version: UInt32
    let dataOffset: Int64
    let metadataStart: UInt64
    let bigEndian: Bool
}

private struct SerializedMetadata {
    let unityVersion: String
    let targetPlatform: UInt32
    let typeIDsByIndex: [Int32]
    let typeCount: Int
    let objects: [ObjectRecord]
    let externalCount: Int
    let typeTreeEnabled: Bool
    let typeRecords: [SerializedTypeRecord]
}

struct ObjectRecord {
    let pathID: Int64
    let byteOffset: Int64
    let byteSize: UInt32
    let typeIndex: Int
    let typeID: Int32
    let scriptTypeIndex: UInt16
}

struct SerializedTypeRecord {
    let typeID: Int32
    let scriptTypeIndex: UInt16
    let typeTree: TypeTreeNodeRecord?
}

private struct SerializedReader {
    let data: Data
    var offset: Int = 0
    var bigEndian = true

    mutating func readHeader() throws -> SerializedHeader {
        let metadataSize = UInt64(try readUInt32())
        let fileSize = Int64(try readUInt32())
        let version = try readUInt32()
        let dataOffset = Int64(try readUInt32())
        let endianFlag = try readUInt8()
        try skip(3)
        bigEndian = true
        if version >= 22 {
            let largeMetadataSize = UInt64(try readUInt32())
            let largeFileSize = try readInt64()
            let largeDataOffset = try readInt64()
            try skip(8)
            bigEndian = endianFlag != 0
            return SerializedHeader(metadataSize: largeMetadataSize, fileSize: largeFileSize, version: version, dataOffset: largeDataOffset, metadataStart: UInt64(offset), bigEndian: endianFlag != 0)
        }
        bigEndian = endianFlag != 0
        return SerializedHeader(metadataSize: metadataSize, fileSize: fileSize, version: version, dataOffset: dataOffset, metadataStart: UInt64(offset), bigEndian: endianFlag != 0)
    }

    mutating func readMetadata(version: UInt32) throws -> SerializedMetadata {
        let metadataStart = offset
        let unityVersion = try readCString()
        let targetPlatform = try readUInt32()
        let typeTreeEnabled = version >= 13 ? try readUInt8() != 0 : false
        let typeCount = try readCount(maximum: 1_000_000, label: "type")
        var typeIDsByIndex: [Int32] = []
        var typeRecords: [SerializedTypeRecord] = []
        typeIDsByIndex.reserveCapacity(typeCount)
        typeRecords.reserveCapacity(typeCount)
        for _ in 0..<typeCount {
            let typeID = try readInt32()
            if version >= 16 { _ = try readUInt8() }
            let scriptTypeIndex: UInt16 = version >= 17 ? try readUInt16() : UInt16.max
            if (version < 17 && typeID < 0) || (version >= 17 && typeID == 114) {
                try skip(16)
            }
            try skip(16)
            let typeTree: TypeTreeNodeRecord?
            if typeTreeEnabled {
                if version >= 23 {
                    try skip(16)
                    let typeTreeSize = try readInt32()
                    guard typeTreeSize >= 0 else { throw SerializedFileError.malformed("invalid type tree size") }
                    typeTree = typeTreeSize == 0 ? nil : try readTypeTree(version: version)
                } else {
                    typeTree = try readTypeTree(version: version)
                }
                if version >= 21 {
                    let dependencyCount = try readCount(maximum: 1_000_000, label: "type dependency")
                    try skip(Int64(dependencyCount) * 4)
                }
            } else {
                typeTree = nil
            }
            typeIDsByIndex.append(typeID)
            typeRecords.append(SerializedTypeRecord(typeID: typeID, scriptTypeIndex: scriptTypeIndex, typeTree: typeTree))
        }
        let objectCount = try readCount(maximum: 10_000_000, label: "object")
        try align(4)
        var objects: [ObjectRecord] = []
        objects.reserveCapacity(objectCount)
        for _ in 0..<objectCount {
            try align(4)
            let pathID = version >= 14 ? try readInt64() : Int64(try readUInt32())
            let byteOffset = version >= 22 ? try readInt64() : Int64(try readUInt32())
            let byteSize = try readUInt32()
            let typeIndexOrID: Int32
            let typeID: Int32
            if version >= 16 {
                typeIndexOrID = try readInt32()
                typeID = typeIndexOrID >= 0 && Int(typeIndexOrID) < typeIDsByIndex.count ? typeIDsByIndex[Int(typeIndexOrID)] : typeIndexOrID
            } else {
                typeID = Int32(try readUInt16())
                typeIndexOrID = typeID
            }
            if version <= 16 { _ = try readUInt16() }
            if version >= 15 && version <= 16 { _ = try readUInt8() }
            let scriptTypeIndex = version >= 17 && typeIndexOrID >= 0 && Int(typeIndexOrID) < typeRecords.count ? typeRecords[Int(typeIndexOrID)].scriptTypeIndex : UInt16.max
            objects.append(ObjectRecord(pathID: pathID, byteOffset: byteOffset, byteSize: byteSize, typeIndex: Int(typeIndexOrID), typeID: typeID, scriptTypeIndex: scriptTypeIndex))
        }
        let scriptCount = try readCount(maximum: 1_000_000, label: "script")
        for _ in 0..<scriptCount {
            _ = try readInt32()
            try align(4)
            _ = try readInt64()
        }
        let externalCount = try readCount(maximum: 1_000_000, label: "external")
        for _ in 0..<externalCount {
            _ = try readCString()
            try skip(16)
            _ = try readInt32()
            _ = try readCString()
        }
        if version >= 20 {
            let refTypeCount = try readCount(maximum: 1_000_000, label: "reference type")
            for _ in 0..<refTypeCount { try skipReferenceTypeRecord(version: version, typeTreeEnabled: typeTreeEnabled) }
        }
        if version >= 5 { _ = try readCString() }
        guard offset - metadataStart <= data.count else { throw SerializedFileError.malformed("metadata exceeds file") }
        return SerializedMetadata(unityVersion: unityVersion, targetPlatform: targetPlatform, typeIDsByIndex: typeIDsByIndex, typeCount: typeCount, objects: objects, externalCount: externalCount, typeTreeEnabled: typeTreeEnabled, typeRecords: typeRecords)
    }

    mutating func readCount(maximum: Int, label: String) throws -> Int {
        let count = try readInt32()
        guard count >= 0, Int(count) <= maximum else { throw SerializedFileError.malformed("invalid \(label) count") }
        return Int(count)
    }

    mutating func skipReferenceTypeRecord(version: UInt32, typeTreeEnabled: Bool) throws {
        let typeID = try readInt32()
        if version >= 16 { _ = try readUInt8() }
        let scriptTypeIndex: UInt16 = version >= 17 ? try readUInt16() : UInt16.max
        if (version < 17 && typeID < 0) || (version >= 17 && typeID == 114) || (version >= 17 && scriptTypeIndex != UInt16.max) {
            try skip(16)
        }
        try skip(16)
        if typeTreeEnabled {
            if version >= 23 {
                try skip(16)
                let typeTreeSize = try readInt32()
                guard typeTreeSize >= 0 else { throw SerializedFileError.malformed("invalid reference type tree size") }
                if typeTreeSize > 0 { _ = try readTypeTree(version: version) }
            } else {
                _ = try readTypeTree(version: version)
            }
            if version >= 21 {
                _ = try readCString()
                _ = try readCString()
                _ = try readCString()
            }
        }
    }

    mutating func readTypeTree(version: UInt32, end: Int? = nil) throws -> TypeTreeNodeRecord? {
        if version >= 23 {
            let magic = try readUInt32()
            guard magic == 0x7474686d else { throw SerializedFileError.malformed("invalid extended type tree header") }
            let treeVersion = try readUInt32()
            guard treeVersion == version else { throw SerializedFileError.malformed("type tree version mismatch") }
        }
        let nodeCount = try readCount(maximum: 1_000_000, label: "type tree node")
        let stringBufferLength = try readCount(maximum: 64 * 1024 * 1024, label: "type tree string table")
        var flatNodes: [TypeTreeNodeRecord] = []
        var typeOffsets: [UInt32] = []
        var nameOffsets: [UInt32] = []
        flatNodes.reserveCapacity(nodeCount); typeOffsets.reserveCapacity(nodeCount); nameOffsets.reserveCapacity(nodeCount)
        for _ in 0..<nodeCount {
            _ = try readUInt16(); let level = Int(try readUInt8()); let flags = try readUInt8()
            let typeOffset = try readUInt32(); let nameOffset = try readUInt32()
            _ = try readInt32(); _ = try readUInt32(); let metaFlags = try readUInt32()
            if version >= 18 { _ = try readUInt64() }
            flatNodes.append(TypeTreeNodeRecord(type: "", name: "", level: level, flags: flags, metaFlags: metaFlags, children: []))
            typeOffsets.append(typeOffset); nameOffsets.append(nameOffset)
        }
        let stringTable = try readBytes(count: stringBufferLength)
        let resolved = flatNodes.enumerated().map { index, node in
            TypeTreeNodeRecord(type: resolveTypeTreeString(offset: typeOffsets[index], local: stringTable), name: resolveTypeTreeString(offset: nameOffsets[index], local: stringTable), level: node.level, flags: node.flags, metaFlags: node.metaFlags, children: [])
        }
        if let end, offset > end { throw SerializedFileError.malformed("type tree exceeds declared size") }
        return TypeTreeNodeRecord.tree(from: resolved)
    }

    private func resolveTypeTreeString(offset: UInt32, local: Data) -> String {
        let table = (offset & 0x80000000) != 0 ? TypeTreeNodeRecord.commonStringTable : local
        let index = Int(offset & 0x7fffffff)
        guard index < table.count else { return "?" }
        let end = table[index...].firstIndex(of: 0) ?? table.endIndex
        return String(decoding: table[index..<end], as: UTF8.self)
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count, count <= data.count - offset else { throw SerializedFileError.malformed("invalid byte range") }
        let result = Data(data[offset..<(offset + count)]); offset += count; return result
    }

    mutating func readUInt8() throws -> UInt8 { guard offset < data.count else { throw SerializedFileError.malformed("unexpected end of file") }; defer { offset += 1 }; return data[offset] }
    mutating func readUInt16() throws -> UInt16 { let bytes = try [readUInt8(), readUInt8()]; return bigEndian ? UInt16(bytes[0]) << 8 | UInt16(bytes[1]) : UInt16(bytes[1]) << 8 | UInt16(bytes[0]) }
    mutating func readUInt32() throws -> UInt32 { let bytes = try [readUInt8(), readUInt8(), readUInt8(), readUInt8()]; return bigEndian ? bytes.reduce(0) { ($0 << 8) | UInt32($1) } : bytes.reversed().reduce(0) { ($0 << 8) | UInt32($1) } }
    mutating func readInt32() throws -> Int32 { Int32(bitPattern: try readUInt32()) }
    mutating func readUInt64() throws -> UInt64 { let bytes = try (0..<8).map { _ in try readUInt8() }; return bigEndian ? bytes.reduce(0) { ($0 << 8) | UInt64($1) } : bytes.enumerated().reduce(0) { $0 | (UInt64($1.element) << (UInt64($1.offset) * 8)) } }
    mutating func readInt64() throws -> Int64 { Int64(bitPattern: try readUInt64()) }
    mutating func readCString() throws -> String { let start = offset; while offset < data.count && data[offset] != 0 { offset += 1 }; guard offset < data.count else { throw SerializedFileError.malformed("unterminated string") }; let value = String(decoding: data[start..<offset], as: UTF8.self); offset += 1; return value }
    mutating func skip(_ count: Int64) throws { guard offset >= 0, offset <= data.count, count >= 0, count <= Int64(data.count - offset) else { throw SerializedFileError.malformed("invalid skip") }; offset += Int(count) }
    mutating func align(_ boundary: Int) throws { let remainder = offset % boundary; if remainder != 0 { try skip(Int64(boundary - remainder)) } }
}

private func unityTypeName(_ typeID: Int32) -> String {
    switch typeID { case 1: return "GameObject"; case 28: return "Texture2D"; case 43: return "Mesh"; case 48: return "Shader"; case 49: return "TextAsset"; case 83: return "AudioClip"; case 114: return "MonoBehaviour"; case 115: return "MonoScript"; case 128: return "Font"; case 213: return "Sprite"; case 142: return "AssetBundle"; default: return "Type \(typeID)" }
}
