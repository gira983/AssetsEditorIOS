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
    private var session: SerializedFileSession?

    init(
        parser: SerializedFileParser = SerializedFileParser(),
        fieldEditor: SerializedFieldEditor = SerializedFieldEditor(),
        rawObjectDataProvider: RawObjectDataProvider = RawObjectDataProvider(),
        transaction: SerializedFileTransaction = SerializedFileTransaction()
    ) {
        self.parser = parser
        self.fieldEditor = fieldEditor
        self.rawObjectDataProvider = rawObjectDataProvider
        self.transaction = transaction
    }

    func openFile(at url: URL) async throws {
        session = try parser.open(url: url)
    }

    func fileInfo() async throws -> SerializedFileInfo {
        guard let session else { throw SerializedFileError.notOpen }
        return session.info
    }

    func objects() async throws -> [SerializedObjectInfo] {
        guard let session else { throw SerializedFileError.notOpen }
        return session.objects
    }

    func fields(for object: SerializedObjectInfo) throws -> [SerializedObjectField] {
        guard let session else { throw SerializedFileError.notOpen }
        return try parser.fields(for: object, in: session)
    }

    func rawData(for object: SerializedObjectInfo) throws -> RawObjectData {
        guard let session else { throw SerializedFileError.notOpen }
        return try rawObjectDataProvider.rawData(for: object, in: session)
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, in url: URL) throws {
        guard let session else { throw SerializedFileError.notOpen }
        let data = try fieldEditor.apply(edits: [field.name: field.value], to: object, in: session)
        try transaction.replaceAtomically(data, at: url)
        self.session = try parser.open(url: url)
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, in url: URL, transaction: SerializedFileTransaction) throws -> String {
        guard let session else { throw SerializedFileError.notOpen }
        let previousValue = try fieldEditor.currentValue(for: field, object: object, in: session)
        let data = try fieldEditor.apply(edits: [field.name: field.value], to: object, in: session)
        try transaction.replaceAtomically(data, at: url)
        self.session = try parser.open(url: url)
        return previousValue
    }

    func close() async {
        session = nil
    }
}
