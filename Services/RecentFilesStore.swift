import Foundation
import Combine

@MainActor
final class RecentFilesStore {
    private(set) var files: [AssetFile] = []

    private let fileManager: FileManager
    private let storageURL: URL
    private let maximumFileCount = 10

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UnityAssetEditor", isDirectory: true)
            .appendingPathComponent("recent-files.json")
        load()
    }

    func record(_ file: AssetFile) {
        files.removeAll { $0.sandboxURL == file.sandboxURL }
        files.insert(file, at: 0)
        files = Array(files.prefix(maximumFileCount))
        save()
    }

    func remove(_ file: AssetFile) {
        files.removeAll { $0.id == file.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let storedFiles = try? JSONDecoder().decode([AssetFile].self, from: data) else {
            return
        }

        files = storedFiles.filter { fileManager.fileExists(atPath: $0.sandboxURL.path) }
    }

    private func save() {
        do {
            let directoryURL = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(files)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }
}
