import Foundation

enum AssetFileKind: String, Codable, Hashable {
    case serializedFile
    case assetBundle
    case unknown
}

struct AssetFile: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    let sandboxURL: URL
    let openedAt: Date
    let sourceURL: URL?
    let kind: AssetFileKind

    init(
        id: UUID = UUID(),
        fileName: String,
        fileSize: Int64,
        sandboxURL: URL,
        openedAt: Date = Date(),
        sourceURL: URL? = nil,
        kind: AssetFileKind = .unknown
    ) {
        self.id = id
        self.fileName = fileName
        self.fileSize = fileSize
        self.sandboxURL = sandboxURL
        self.openedAt = openedAt
        self.sourceURL = sourceURL
        self.kind = kind
    }
}
