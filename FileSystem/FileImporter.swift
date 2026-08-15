import Foundation

struct ImportedAssetFile {
    let file: AssetFile
    let backupURL: URL
}

enum FileImporterError: LocalizedError {
    case inaccessibleFile

    var errorDescription: String? {
        switch self {
        case .inaccessibleFile:
            return "The file could not be accessed."
        }
    }
}

struct FileImporter {
    private let fileManager: FileManager
    private let backupService: AssetBackupService

    init(fileManager: FileManager = .default, backupService: AssetBackupService = AssetBackupService()) {
        self.fileManager = fileManager
        self.backupService = backupService
    }

    func importFile(from sourceURL: URL) throws -> ImportedAssetFile {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard sourceURL.isFileURL else { throw FileImporterError.inaccessibleFile }
        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        let destinationDirectory = try applicationSupportDirectory()
        let destinationURL = uniqueDestinationURL(for: sourceURL, in: destinationDirectory)
        try data.write(to: destinationURL, options: [.atomic])
        let backupURL = try backupService.createBackupIfNeeded(for: destinationURL)
        let file = AssetFile(
            fileName: sourceURL.lastPathComponent,
            fileSize: Int64(data.count),
            sandboxURL: destinationURL,
            kind: detectKind(for: sourceURL)
        )
        return ImportedAssetFile(file: file, backupURL: backupURL)
    }

    private func applicationSupportDirectory() throws -> URL {
        let url = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = url.appendingPathComponent("UnityAssetEditor", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func detectKind(for url: URL) -> AssetFileKind {
        let ext = url.pathExtension.lowercased()
        if ext == "unity3d" || ext == "assetbundle" || ext == "bundle" { return .assetBundle }
        if ext == "assets" || ext == "resS".lowercased() || ext == "resource" { return .serializedFile }
        return .unknown
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let extensionName = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = extensionName.isEmpty ? "\(baseName)-\(index)" : "\(baseName)-\(index).\(extensionName)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}
