import XCTest
@testable import UnityAssetEditor

final class Phase5Tests: XCTestCase {
    @MainActor
    func testHistoryStoreMovesEntriesBetweenUndoAndRedo() {
        let object = SerializedObjectInfo(id: "1", pathID: 1, typeID: 1, byteOffset: 0, byteSize: 4, typeName: "GameObject", displayName: "GameObject")
        let field = SerializedObjectField(id: "root.value", name: "root.value", type: "int", value: "1", depth: 0, editable: true)
        let store = EditorHistoryStore()
        store.record(object: object, field: field, oldValue: "1", newValue: "2")
        XCTAssertEqual(store.undoStack.count, 1)
        XCTAssertTrue(store.redoStack.isEmpty)
        _ = store.popUndo()
        XCTAssertTrue(store.undoStack.isEmpty)
        XCTAssertEqual(store.redoStack.count, 1)
        _ = store.popRedo()
        XCTAssertEqual(store.undoStack.count, 1)
        XCTAssertTrue(store.redoStack.isEmpty)
    }

    func testTransactionReplacesFileAndLeavesNoTempFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sample.assets")
        try Data([1, 2, 3]).write(to: url)
        try SerializedFileTransaction().replaceAtomically(Data([9, 8, 7, 6]), at: url)
        XCTAssertEqual(try Data(contentsOf: url), Data([9, 8, 7, 6]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("transaction-temp").path))
    }
}
