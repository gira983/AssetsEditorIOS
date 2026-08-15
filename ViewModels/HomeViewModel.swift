import Combine
import Foundation
import UniformTypeIdentifiers


@MainActor
final class HomeViewModel: ObservableObject {
    @Published var isShowingFileImporter = false
    @Published private(set) var selectedFile: AssetFile?
    @Published private(set) var recentFiles: [AssetFile] = []
    @Published private(set) var selectedFileInfo: SerializedFileInfo?
    @Published private(set) var selectedObjects: [SerializedObjectInfo] = []
    @Published private(set) var selectedObject: SerializedObjectInfo?
    @Published private(set) var selectedObjectFields: [SerializedObjectField] = []
    @Published private(set) var selectedBundleInfo: AssetBundleInfo?
    @Published private(set) var selectedBundleEntries: [AssetBundleDirectoryEntry] = []
    @Published private(set) var selectedRawObjectData: RawObjectData?
    @Published var isShowingHexViewer = false
    @Published var isShowingDiffViewer = false
    @Published private(set) var diffSummary: AssetDiffSummary?
    @Published var hexSearchQuery = ""
    @Published var hexSearchMode: HexSearchMode = .hex
    @Published private(set) var hexFocusOffset: Int?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var isShowingHistory = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var historyEntries: [EditorHistoryEntry] = []

    private let fileImporter: FileImporter
    private let recentFilesStore: RecentFilesStore
    private let backend: NativeSerializedFileBackend
    private let backupService: AssetBackupService
    private let bundleParser: AssetBundleParser
    private let assetDiffService: AssetDiffService
    private let rawObjectDataProvider: RawObjectDataProvider
    private let historyStore: EditorHistoryStore
    private let transaction: SerializedFileTransaction
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(
        fileImporter: FileImporter = FileImporter(),
        recentFilesStore: RecentFilesStore? = nil,
        backend: NativeSerializedFileBackend = NativeSerializedFileBackend(),
        backupService: AssetBackupService = AssetBackupService(),
        bundleParser: AssetBundleParser = AssetBundleParser(),
        assetDiffService: AssetDiffService = AssetDiffService(),
        rawObjectDataProvider: RawObjectDataProvider = RawObjectDataProvider(),
        transaction: SerializedFileTransaction = SerializedFileTransaction(),
        historyStore: EditorHistoryStore? = nil
    ) {
        self.fileImporter = fileImporter
        self.recentFilesStore = recentFilesStore ?? RecentFilesStore()
        self.backend = backend
        self.backupService = backupService
        self.bundleParser = bundleParser
        self.assetDiffService = assetDiffService
        self.rawObjectDataProvider = rawObjectDataProvider
        self.transaction = transaction
        self.historyStore = historyStore ?? EditorHistoryStore()
        recentFiles = self.recentFilesStore.files
        self.historyStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.syncHistoryState() }
        }.store(in: &cancellables)
    }

    func importFile(from url: URL) {
        do {
            let importedFile = try fileImporter.importFile(from: url)
            select(importedFile.file)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openRecentFile(_ file: AssetFile) {
        select(file)
    }

    func selectObject(_ object: SerializedObjectInfo) {
        selectedObject = object
        do {
            selectedObjectFields = try backend.fields(for: object)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func extractBundleEntry(_ entry: AssetBundleDirectoryEntry) {
        guard let file = selectedFile else { return }
        do {
            let extracted = try bundleParser.extract(entry: entry, from: file.sandboxURL)
            let destination = try extractedFileURL(for: entry.name)
            try extracted.data.write(to: destination, options: [.atomic])
            let kind: AssetFileKind = entry.isSerialized ? .serializedFile : .unknown
            let extractedFile = AssetFile(fileName: destination.lastPathComponent, fileSize: Int64(extracted.data.count), sandboxURL: destination, sourceURL: file.sandboxURL, kind: kind)
            selectExtractedFile(extractedFile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func extractedFileURL(for entryName: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("UnityAssetEditor/Extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = entryName.split(separator: "/").last.map(String.init) ?? "entry"
        return directory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    }

    private func selectExtractedFile(_ file: AssetFile) {
        selectedFile = file
        selectedBundleInfo = nil
        selectedBundleEntries = []
        selectedFileInfo = nil
        selectedObjects = []
        selectedObject = nil
        selectedObjectFields = []
        selectedRawObjectData = nil
        isShowingHexViewer = false
        isShowingDiffViewer = false
        isLoading = true
        Task { await load(file) }
    }

    func clearSelectedObject() {
        selectedObject = nil
        selectedObjectFields = []
        selectedRawObjectData = nil
        isShowingHexViewer = false
    }

    func showHexViewer() {
        guard let object = selectedObject else { return }
        do {
            selectedRawObjectData = try backend.rawData(for: object)
            isShowingHexViewer = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func focusHex(offset: Int) {
        hexFocusOffset = offset
    }

    func clearHexFocus() {
        hexFocusOffset = nil
    }

    func updateField(_ field: SerializedObjectField, value: String) {
        guard let file = selectedFile, let object = selectedObject else { return }
        let updatedField = SerializedObjectField(id: field.id, name: field.name, type: field.type, value: value, depth: field.depth, editable: field.editable)
        do {
            let previousValue = try backend.updateField(updatedField, for: object, in: file.sandboxURL, transaction: transaction)
            historyStore.record(object: object, field: field, oldValue: previousValue, newValue: value)
            syncHistoryState()
            refreshSelectedObject()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func hasBackup(for file: AssetFile) -> Bool {
        backupService.hasBackup(for: file.sandboxURL)
    }

    func createBackup() {
        guard let file = selectedFile else { return }
        do {
            _ = try backupService.createBackupIfNeeded(for: file.sandboxURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreOriginal() {
        guard let file = selectedFile else { return }
        do {
            try backupService.restoreOriginal(for: file.sandboxURL)
            select(file)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeRecentFile(_ file: AssetFile) {
        recentFilesStore.remove(file)
        recentFiles = recentFilesStore.files
    }

    func fileTypeFilter() -> [UTType] {
        [.data]
    }

    private func select(_ file: AssetFile) {
        selectedFile = file
        recentFilesStore.record(file)
        recentFiles = recentFilesStore.files
        selectedFileInfo = nil
        selectedObjects = []
        selectedObjectFields = []
        selectedObject = nil
        selectedRawObjectData = nil
        diffSummary = nil
        isShowingHexViewer = false
        isShowingDiffViewer = false
        hexSearchQuery = ""
        hexFocusOffset = nil
        selectedBundleInfo = nil
        selectedBundleEntries = []
        isLoading = true
        Task { await load(file) }
    }

    private func load(_ file: AssetFile) async {
        defer { isLoading = false }
        do {
            if file.kind == .assetBundle || file.kind == .unknown,
               let bundleInfo = try? bundleParser.readInfo(url: file.sandboxURL) {
                selectedBundleInfo = bundleInfo
                selectedBundleEntries = bundleInfo.directoryEntries
                return
            }
            try await backend.openFile(at: file.sandboxURL)
            selectedFileInfo = try await backend.fileInfo()
            selectedObjects = try await backend.objects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showDiffViewer() {
        guard let file = selectedFile else { return }
        do {
            let backupURL = AssetBackupService().backupURL(for: file.sandboxURL)
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                throw AssetDiffError.backupMissing
            }
            diffSummary = try assetDiffService.compare(originalURL: backupURL, currentURL: file.sandboxURL)
            isShowingDiffViewer = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undo() {
        guard let entry = historyStore.popUndo() else { return }
        applyHistoryEntry(entry, value: entry.oldValue, moving: .undo)
    }

    func redo() {
        guard let entry = historyStore.popRedo() else { return }
        applyHistoryEntry(entry, value: entry.newValue, moving: .redo)
    }

    func clearHistory() {
        historyStore.clear()
        syncHistoryState()
    }

    private func refreshSelectedObject() {
        guard let object = selectedObject else { return }
        do {
            selectedObjectFields = try backend.fields(for: object)
            selectedRawObjectData = try? backend.rawData(for: object)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyHistoryEntry(_ entry: EditorHistoryEntry, value: String, moving: HistoryMove) {
        guard let file = selectedFile,
              let object = selectedObjects.first(where: { $0.id == entry.objectID }) else {
            syncHistoryState()
            return
        }
        let field = selectedObjectFields.first(where: { $0.name == entry.fieldName }) ?? SerializedObjectField(id: entry.fieldName, name: entry.fieldName, type: entry.fieldType, value: value, depth: 0, editable: true)
        do {
            try backend.updateField(SerializedObjectField(id: field.id, name: field.name, type: field.type, value: value, depth: field.depth, editable: field.editable), for: object, in: file.sandboxURL, transaction: transaction)
            if moving == .undo { historyStore.pushRedo(entry) } else { historyStore.pushUndo(entry) }
            syncHistoryState()
            refreshSelectedObject()
        } catch {
            if moving == .undo { historyStore.pushUndo(entry) } else { historyStore.pushRedo(entry) }
            syncHistoryState()
            errorMessage = error.localizedDescription
        }
    }

    private enum HistoryMove { case undo, redo }

    private func syncHistoryState() {
        canUndo = !historyStore.undoStack.isEmpty
        canRedo = !historyStore.redoStack.isEmpty
        historyEntries = historyStore.undoStack.reversed()
    }
}
