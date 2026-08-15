import Foundation

struct AssetBackupService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createBackupIfNeeded(for fileURL: URL) throws -> URL {
        let backupURL = fileURL.appendingPathExtension("backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return backupURL }
        try fileManager.copyItem(at: fileURL, to: backupURL)
        return backupURL
    }

    func restoreOriginal(for fileURL: URL) throws {
        let backupURL = fileURL.appendingPathExtension("backup")
        guard fileManager.fileExists(atPath: backupURL.path) else { throw AssetBackupError.backupMissing }
        let temporaryURL = fileURL.appendingPathExtension("restore-temp")
        if fileManager.fileExists(atPath: temporaryURL.path) { try fileManager.removeItem(at: temporaryURL) }
        try fileManager.copyItem(at: backupURL, to: temporaryURL)
        if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
        try fileManager.moveItem(at: temporaryURL, to: fileURL)
    }

    func backupURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("backup")
    }

    func hasBackup(for fileURL: URL) -> Bool {
        fileManager.fileExists(atPath: backupURL(for: fileURL).path)
    }
}

enum AssetBackupError: LocalizedError {
    case backupMissing

    var errorDescription: String? {
        switch self {
        case .backupMissing:
            return "The original backup does not exist."
        }
    }
}
