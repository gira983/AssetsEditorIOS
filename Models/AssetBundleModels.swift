import Foundation

struct AssetBundleInfo: Hashable {
    let signature: String
    let formatVersion: UInt32
    let unityVersion: String
    let unityRevision: String
    let compressed: Bool
    let compressionType: AssetBundleCompressionType
    let fileSize: UInt64
    let blockInfoCompressedSize: UInt64
    let blockInfoDecompressedSize: UInt64
    let blockCount: Int
    let directoryEntryCount: Int
    let directoryEntries: [AssetBundleDirectoryEntry]

    init(
        signature: String,
        formatVersion: UInt32,
        unityVersion: String,
        unityRevision: String,
        compressed: Bool,
        compressionType: AssetBundleCompressionType = .none,
        fileSize: UInt64,
        blockInfoCompressedSize: UInt64,
        blockInfoDecompressedSize: UInt64,
        blockCount: Int,
        directoryEntryCount: Int,
        directoryEntries: [AssetBundleDirectoryEntry] = []
    ) {
        self.signature = signature
        self.formatVersion = formatVersion
        self.unityVersion = unityVersion
        self.unityRevision = unityRevision
        self.compressed = compressed
        self.compressionType = compressionType
        self.fileSize = fileSize
        self.blockInfoCompressedSize = blockInfoCompressedSize
        self.blockInfoDecompressedSize = blockInfoDecompressedSize
        self.blockCount = blockCount
        self.directoryEntryCount = directoryEntryCount
        self.directoryEntries = directoryEntries
    }
}

enum AssetBundleCompressionType: String, Hashable {
    case none
    case lzma
    case lz4
    case lz4HighCompression
    case mixed
    case unsupported

    var displayName: String {
        switch self {
        case .none: return "None"
        case .lzma: return "LZMA"
        case .lz4: return "LZ4"
        case .lz4HighCompression: return "LZ4HC"
        case .mixed: return "Mixed"
        case .unsupported: return "Unsupported"
        }
    }
}

struct AssetBundleBlock: Hashable, Identifiable {
    let id: Int
    let decompressedSize: UInt32
    let compressedSize: UInt32
    let flags: UInt16

    var compressionType: AssetBundleCompressionType {
        switch flags & 0x3F {
        case 0: return .none
        case 1: return .lzma
        case 2: return .lz4
        case 3: return .lz4HighCompression
        default: return .unsupported
        }
    }
}

struct AssetBundleDirectoryEntry: Hashable, Identifiable {
    let id: Int
    let offset: Int64
    let decompressedSize: Int64
    let flags: UInt32
    let name: String

    var isSerialized: Bool { flags & 0x04 != 0 }
    var isDeleted: Bool { flags & 0x02 != 0 }
    var isDirectory: Bool { flags & 0x01 != 0 }
}

enum AssetBundleError: LocalizedError {
    case notBundle
    case malformed(String)
    case unsupportedCompression(AssetBundleCompressionType)
    case unsupportedEntry(String)
    case decompressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notBundle:
            return "The file does not look like a Unity AssetBundle."
        case .malformed(let message):
            return "The AssetBundle is malformed: \(message)."
        case .unsupportedCompression(let type):
            return "This AssetBundle uses unsupported compression: \(type.displayName)."
        case .unsupportedEntry(let name):
            return "The AssetBundle entry cannot be extracted: \(name)."
        case .decompressionFailed(let message):
            return "AssetBundle decompression failed: \(message)."
        }
    }
}
