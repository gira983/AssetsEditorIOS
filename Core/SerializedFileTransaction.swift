import Foundation

struct SerializedFileTransaction {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func replaceAtomically(_ data: Data, at url: URL) throws {
        let temporaryURL = url.appendingPathExtension("transaction-temp")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try data.write(to: temporaryURL, options: [.atomic])
        _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL, backupItemName: nil, options: .usingNewMetadataOnly)
    }
}
