import Foundation

struct AssetDiffSummary: Hashable {
    let originalSize: Int
    let currentSize: Int
    let changedByteCount: Int
    let ranges: [AssetDiffRange]

    var isIdentical: Bool { changedByteCount == 0 && originalSize == currentSize }
}

struct AssetDiffRange: Hashable, Identifiable {
    let startOffset: Int
    let endOffset: Int
    let originalBytes: [UInt8]
    let currentBytes: [UInt8]

    var id: String { "\(startOffset)-\(endOffset)" }
    var length: Int { endOffset - startOffset }
}

enum AssetDiffError: LocalizedError {
    case backupMissing
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case .backupMissing:
            return "Create the original backup before comparing changes."
        case .unreadableFile(let path):
            return "Could not read file: \(path)."
        }
    }
}
