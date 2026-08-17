import Foundation

protocol AssetBackend {
    associatedtype FileInfo
    associatedtype Object

    func openFile(at url: URL) async throws
    func fileInfo() async throws -> FileInfo
    func objects() async throws -> [Object]
    func close() async
}

final class NativeSerializedFileBackend: AssetBackend {
    typealias FileInfo = SerializedFileInfo
    typealias Object = SerializedObjectInfo

    private let parser: SerializedFileParser
    private let fieldEditor: SerializedFieldEditor
    private let rawObjectDataProvider: RawObjectDataProvider
    private let transaction: SerializedFileTransaction
    private let bridge: AssetToolsBridge
    private var session: SerializedFileSession?
    private var openedURL: URL?

    init(
        parser: SerializedFileParser = SerializedFileParser(),
        fieldEditor: SerializedFieldEditor = SerializedFieldEditor(),
        rawObjectDataProvider: RawObjectDataProvider = RawObjectDataProvider(),
        transaction: SerializedFileTransaction = SerializedFileTransaction(),
        bridge: AssetToolsBridge = NativeAssetToolsBridge()
    ) {
        self.parser = parser
        self.fieldEditor = fieldEditor
        self.rawObjectDataProvider = rawObjectDataProvider
        self.transaction = transaction
        self.bridge = bridge
    }

    func openFile(at url: URL) async throws {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            if data.starts(with: Data("UnityFS".utf8)) || data.starts(with: Data("UnityRaw".utf8)) || data.starts(with: Data("UnityWeb".utf8)) {
                openedURL = url
                session = nil
                return
            }
            session = try parser.open(url: url)
            openedURL = url
        } catch {
            _ = try bridge.inspect(at: url)
            openedURL = url
            session = nil
        }
    }

    func fileInfo() async throws -> SerializedFileInfo {
        guard let openedURL else { throw SerializedFileError.notOpen }
        guard let session else {
            let info = try bridge.inspect(at: openedURL)
            return SerializedFileInfo(formatVersion: 0, fileSize: UInt64((try? Data(contentsOf: openedURL).count) ?? 0), metadataSize: 0, dataOffset: 0, unityVersion: info.unityVersion ?? "", targetPlatform: 0, objectCount: info.assetCount, typeCount: 0, externalCount: 0, isBigEndian: false)
        }
        return session.info
    }

    func objects() async throws -> [SerializedObjectInfo] {
        guard let openedURL else { throw SerializedFileError.notOpen }
        if session == nil { return try bridge.listObjects(at: openedURL) }
        return session?.objects ?? []
    }

    func fields(for object: SerializedObjectInfo) throws -> [SerializedObjectField] {
        guard let openedURL else { throw SerializedFileError.notOpen }
        if session == nil { return try bridge.fields(for: object, at: openedURL) }
        guard let session else { throw SerializedFileError.notOpen }
        return try parser.fields(for: object, in: session)
    }

    func rawData(for object: SerializedObjectInfo) throws -> RawObjectData {
        guard let session else { throw SerializedFileError.notOpen }
        return try rawObjectDataProvider.rawData(for: object, in: session)
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, in url: URL) throws {
        if session == nil {
            let outputURL = url.appendingPathExtension("edited")
            try bridge.updateField(field, for: object, at: url, outputURL: outputURL)
            try transaction.replaceAtomically(try Data(contentsOf: outputURL), at: url)
            try? FileManager.default.removeItem(at: outputURL)
            return
        }
        guard let session else { throw SerializedFileError.notOpen }
        let data = try fieldEditor.apply(edits: [field.name: field.value], to: object, in: session)
        try transaction.replaceAtomically(data, at: url)
        self.session = try parser.open(url: url)
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, in url: URL, transaction: SerializedFileTransaction) throws -> String {
        if session == nil {
            let outputURL = url.appendingPathExtension("edited")
            let oldFields = try bridge.fields(for: object, at: url)
            let previousValue = oldFields.first(where: { $0.name == field.name })?.value ?? ""
            try bridge.updateField(field, for: object, at: url, outputURL: outputURL)
            try transaction.replaceAtomically(try Data(contentsOf: outputURL), at: url)
            try? FileManager.default.removeItem(at: outputURL)
            return previousValue
        }
        guard let session else { throw SerializedFileError.notOpen }
        let previousValue = try fieldEditor.currentValue(for: field, object: object, in: session)
        let data = try fieldEditor.apply(edits: [field.name: field.value], to: object, in: session)
        try transaction.replaceAtomically(data, at: url)
        self.session = try parser.open(url: url)
        return previousValue
    }

    func close() async {
        session = nil
        openedURL = nil
    }
}
