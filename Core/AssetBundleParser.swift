import Foundation

struct AssetBundleParser {
    func readInfo(url: URL) throws -> AssetBundleInfo {
        let data = try readFile(url)
        return try parseInfo(data: data)
    }

    func extract(entry: AssetBundleDirectoryEntry, from url: URL) throws -> BundleEntryData {
        let data = try readFile(url)
        let parsed = try parse(data: data)
        guard let selected = parsed.entries.first(where: { $0.id == entry.id }) else {
            throw AssetBundleError.unsupportedEntry(entry.name)
        }
        guard selected.offset >= 0, selected.decompressedSize >= 0 else {
            throw AssetBundleError.unsupportedEntry(selected.name)
        }
        guard let end = checkedAdd(selected.offset, selected.decompressedSize) else {
            throw AssetBundleError.malformed("entry range overflow")
        }
        guard end <= Int64(parsed.uncompressedData.count) else {
            throw AssetBundleError.malformed("entry range exceeds decompressed data")
        }
        let start = Int(selected.offset)
        let finish = Int(end)
        return BundleEntryData(entry: selected, data: Data(parsed.uncompressedData[start..<finish]))
    }

    func extractSerializedEntries(from url: URL) throws -> [BundleEntryData] {
        let data = try readFile(url)
        let parsed = try parse(data: data)
        return try parsed.entries.filter { $0.isSerialized && !$0.isDeleted && !$0.isDirectory }.map { entry in
            guard entry.offset >= 0, entry.decompressedSize >= 0,
                  let end = checkedAdd(entry.offset, entry.decompressedSize),
                  end <= Int64(parsed.uncompressedData.count) else {
                throw AssetBundleError.malformed("entry range exceeds decompressed data")
            }
            let start = Int(entry.offset)
            let finish = Int(end)
            return BundleEntryData(entry: entry, data: Data(parsed.uncompressedData[start..<finish]))
        }
    }

    private func readFile(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw AssetBundleError.malformed("could not read bundle")
        }
    }

    private func parseInfo(data: Data) throws -> AssetBundleInfo {
        try parse(data: data).info
    }

    private func parse(data: Data) throws -> ParsedBundle {
        var reader = BundleReader(data: data)
        let signature: String
        do {
            signature = try reader.readCString()
        } catch {
            throw AssetBundleError.notBundle
        }
        guard signature == "UnityFS" else { throw AssetBundleError.notBundle }
        let formatVersion = try reader.readUInt32BE()
        guard formatVersion >= 6 else { throw AssetBundleError.malformed("unsupported bundle version") }
        let generationVersion = try reader.readCString()
        let unityVersion = try reader.readCString()
        if formatVersion >= 7 { try reader.align(16) }
        let fileSize = try reader.readInt64BE()
        guard fileSize >= 0 else { throw AssetBundleError.malformed("negative file size") }
        let blockInfoCompressedSize = UInt64(try reader.readUInt32BE())
        let blockInfoDecompressedSize = UInt64(try reader.readUInt32BE())
        guard blockInfoDecompressedSize <= UInt64(Int.max) else { throw AssetBundleError.malformed("block info size exceeds addressable range") }
        let flags = try reader.readUInt32BE()
        let compression = compressionType(flags & 0x3F)
        let infoOffset: Int
        let dataOffset: Int
        if flags & 0x80 != 0 {
            guard fileSize >= Int64(blockInfoCompressedSize) else { throw AssetBundleError.malformed("invalid block info offset") }
            let candidate = fileSize - Int64(blockInfoCompressedSize)
            guard candidate <= Int64(data.count) else { throw AssetBundleError.malformed("block info offset exceeds file") }
            guard candidate <= Int64(Int.max) else { throw AssetBundleError.malformed("block info offset exceeds addressable range") }
            infoOffset = Int(candidate)
            dataOffset = headerDataOffset(version: formatVersion, generationVersion: generationVersion, unityVersion: unityVersion, signature: signature, flags: flags, compressedSize: 0)
        } else {
            infoOffset = reader.offset
            dataOffset = headerDataOffset(version: formatVersion, generationVersion: generationVersion, unityVersion: unityVersion, signature: signature, flags: flags, compressedSize: Int64(blockInfoCompressedSize))
        }
        guard infoOffset >= 0, infoOffset <= data.count, blockInfoCompressedSize <= UInt64(data.count - infoOffset) else { throw AssetBundleError.malformed("invalid block info range") }
        guard blockInfoCompressedSize <= UInt64(Int.max - infoOffset) else { throw AssetBundleError.malformed("block info size exceeds addressable range") }
        let infoEnd = infoOffset + Int(blockInfoCompressedSize)
        guard infoEnd >= infoOffset else { throw AssetBundleError.malformed("invalid block info range") }
        let infoBytes = Data(data[infoOffset..<infoEnd])
        let directory = try decodeBlockInfo(infoBytes, compression: compression, expectedSize: Int(blockInfoDecompressedSize))
        let blocks = directory.blocks
        let effectiveCompression = blocks.map(\.compressionType).reduce(into: Set<AssetBundleCompressionType>()) { $0.insert($1) }
        let bundleCompression: AssetBundleCompressionType
        if effectiveCompression.count == 1 {
            bundleCompression = effectiveCompression.first ?? compression
        } else if effectiveCompression.isEmpty {
            bundleCompression = .none
        } else {
            bundleCompression = .mixed
        }
        guard dataOffset >= 0, dataOffset <= data.count else { throw AssetBundleError.malformed("invalid data offset") }
        let uncompressedData = try decodeData(data: data, dataOffset: dataOffset, blocks: blocks)
        let info = AssetBundleInfo(signature: signature, formatVersion: formatVersion, unityVersion: unityVersion, unityRevision: generationVersion, compressed: bundleCompression != .none, compressionType: bundleCompression, fileSize: UInt64(fileSize), blockInfoCompressedSize: blockInfoCompressedSize, blockInfoDecompressedSize: blockInfoDecompressedSize, blockCount: blocks.count, directoryEntryCount: directory.entries.count, directoryEntries: directory.entries)
        return ParsedBundle(info: info, entries: directory.entries, uncompressedData: uncompressedData)
    }

    private func headerDataOffset(version: UInt32, generationVersion: String, unityVersion: String, signature: String, flags: UInt32, compressedSize: Int64) -> Int {
        var value = generationVersion.utf8.count + unityVersion.utf8.count + 0x1A
        if flags & 0x200 != 0 { value += 0x0A } else { value += signature.utf8.count + 1 }
        if version >= 7 { value = (value + 15) & ~15 }
        if flags & 0x80 == 0 { value += Int(compressedSize) }
        if flags & 0x100 != 0 { value = (value + 15) & ~15 }
        return value
    }

    private func compressionType(_ value: UInt32) -> AssetBundleCompressionType {
        switch value {
        case 0: return .none
        case 1: return .lzma
        case 2: return .lz4
        case 3: return .lz4HighCompression
        default: return .unsupported
        }
    }

    private func decodeBlockInfo(_ compressed: Data, compression: AssetBundleCompressionType, expectedSize: Int) throws -> (blocks: [AssetBundleBlock], entries: [AssetBundleDirectoryEntry]) {
        let decoded: Data
        switch compression {
        case .none:
            decoded = compressed
        case .lz4, .lz4HighCompression:
            decoded = try AssetBundleTestLZ4.decode(compressed, expectedSize: expectedSize)
        case .lzma:
            throw AssetBundleError.unsupportedCompression(.lzma)
        default:
            throw AssetBundleError.unsupportedCompression(compression)
        }
        var reader = BundleReader(data: decoded)
        _ = try reader.readBytes(count: 16)
        let blockCount = try reader.readCount(label: "block")
        guard blockCount <= 1_000_000 else { throw AssetBundleError.malformed("invalid block count") }
        var blocks: [AssetBundleBlock] = []
        blocks.reserveCapacity(blockCount)
        for index in 0..<blockCount {
            blocks.append(AssetBundleBlock(id: index, decompressedSize: try reader.readUInt32BE(), compressedSize: try reader.readUInt32BE(), flags: try reader.readUInt16BE()))
        }
        let directoryCount = try reader.readCount(label: "directory")
        guard directoryCount <= 1_000_000 else { throw AssetBundleError.malformed("invalid directory count") }
        var entries: [AssetBundleDirectoryEntry] = []
        entries.reserveCapacity(directoryCount)
        for index in 0..<directoryCount {
            entries.append(AssetBundleDirectoryEntry(id: index, offset: try reader.readInt64BE(), decompressedSize: try reader.readInt64BE(), flags: try reader.readUInt32BE(), name: try reader.readCString()))
        }
        return (blocks, entries)
    }

    private func decodeData(data: Data, dataOffset: Int, blocks: [AssetBundleBlock]) throws -> Data {
        guard dataOffset >= 0, dataOffset <= data.count else { throw AssetBundleError.malformed("invalid data offset") }
        var reader = BundleReader(data: data, offset: dataOffset)
        var output = Data()
        for block in blocks {
            guard block.compressedSize <= UInt32(Int.max), block.decompressedSize <= UInt32(Int.max) else { throw AssetBundleError.malformed("block size exceeds addressable range") }
            let bytes = try reader.readBytes(count: Int(block.compressedSize))
            switch block.compressionType {
            case .none:
                guard block.compressedSize == block.decompressedSize else { throw AssetBundleError.malformed("uncompressed block size mismatch") }
                output.append(bytes)
            case .lz4, .lz4HighCompression:
                output.append(try AssetBundleTestLZ4.decode(bytes, expectedSize: Int(block.decompressedSize)))
            case .lzma:
                throw AssetBundleError.unsupportedCompression(.lzma)
            default:
                throw AssetBundleError.unsupportedCompression(block.compressionType)
            }
        }
        return output
    }

    private func checkedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        guard lhs >= 0, rhs >= 0 else { return nil }
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }
}

private struct ParsedBundle {
    let info: AssetBundleInfo
    let entries: [AssetBundleDirectoryEntry]
    let uncompressedData: Data
}

private struct BundleReader {
    let data: Data
    var offset: Int

    init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    mutating func readUInt32BE() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64BE() throws -> UInt64 {
        let bytes = try readBytes(count: 8)
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func readInt64BE() throws -> Int64 { Int64(bitPattern: try readUInt64BE()) }

    mutating func readCString() throws -> String {
        let start = offset
        while offset < data.count && data[offset] != 0 { offset += 1 }
        guard offset < data.count else { throw AssetBundleError.malformed("unterminated string") }
        let value = String(decoding: data[start..<offset], as: UTF8.self)
        offset += 1
        return value
    }

    mutating func readCount(label: String) throws -> Int {
        let count = try readUInt32BE()
        guard count <= UInt32(Int.max) else { throw AssetBundleError.malformed("invalid \(label) count") }
        return Int(count)
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard offset >= 0, offset <= data.count, count >= 0, count <= data.count - offset else { throw AssetBundleError.malformed("unexpected end of bundle") }
        let result = Data(data[offset..<(offset + count)])
        offset += count
        return result
    }

    mutating func align(_ boundary: Int) throws {
        guard boundary > 0 else { throw AssetBundleError.malformed("invalid alignment") }
        let remainder = offset % boundary
        if remainder != 0 { _ = try readBytes(count: boundary - remainder) }
    }
}

enum AssetBundleTestLZ4 {
    static func decode(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw AssetBundleError.decompressionFailed("invalid output size") }
        var input = 0
        var output = Data()
        output.reserveCapacity(expectedSize)
        while input < data.count {
            let token = Int(data[input]); input += 1
            var literalLength = token >> 4
            if literalLength == 15 { literalLength += try readLength(data, index: &input) }
            guard literalLength <= data.count - input else { throw AssetBundleError.decompressionFailed("literal exceeds block") }
            output.append(data[input..<(input + literalLength)])
            input += literalLength
            if input == data.count { break }
            guard input + 2 <= data.count else { throw AssetBundleError.decompressionFailed("missing match offset") }
            let matchOffset = Int(data[input]) | (Int(data[input + 1]) << 8); input += 2
            guard matchOffset > 0, matchOffset <= output.count else { throw AssetBundleError.decompressionFailed("invalid match offset") }
            var matchLength = token & 0x0F
            if matchLength == 15 { matchLength += try readLength(data, index: &input) }
            matchLength += 4
            for _ in 0..<matchLength {
                guard let byte = output.dropFirst(output.count - matchOffset).first else { throw AssetBundleError.decompressionFailed("match out of range") }
                output.append(byte)
            }
        }
        guard output.count == expectedSize else { throw AssetBundleError.decompressionFailed("output size mismatch") }
        return output
    }

    private static func readLength(_ data: Data, index: inout Int) throws -> Int {
        var result = 0
        while true {
            guard index < data.count else { throw AssetBundleError.decompressionFailed("truncated length") }
            let value = Int(data[index]); index += 1
            result += value
            if value != 255 { return result }
        }
    }
}
