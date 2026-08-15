import Foundation
import Combine

struct EditorHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let objectID: String
    let fieldName: String
    let fieldType: String
    let oldValue: String
    let newValue: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        objectID: String,
        fieldName: String,
        fieldType: String,
        oldValue: String,
        newValue: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.objectID = objectID
        self.fieldName = fieldName
        self.fieldType = fieldType
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = timestamp
    }
}

@MainActor
final class EditorHistoryStore: ObservableObject {
    private(set) var undoStack: [EditorHistoryEntry] = []
    private(set) var redoStack: [EditorHistoryEntry] = []

    func record(object: SerializedObjectInfo, field: SerializedObjectField, oldValue: String, newValue: String) {
        guard oldValue != newValue else { return }
        undoStack.append(EditorHistoryEntry(objectID: object.id, fieldName: field.name, fieldType: field.type, oldValue: oldValue, newValue: newValue))
        redoStack.removeAll()
    }

    func popUndo() -> EditorHistoryEntry? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(entry)
        return entry
    }

    func popRedo() -> EditorHistoryEntry? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(entry)
        return entry
    }

    func pushUndo(_ entry: EditorHistoryEntry) {
        if redoStack.last?.id == entry.id { redoStack.removeLast() }
        undoStack.append(entry)
    }

    func pushRedo(_ entry: EditorHistoryEntry) {
        if undoStack.last?.id == entry.id { undoStack.removeLast() }
        redoStack.append(entry)
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

private extension SerializedObjectField {
    func withValue(_ value: String) -> SerializedObjectField {
        SerializedObjectField(id: id, name: name, type: type, value: value, depth: depth, editable: editable)
    }
}
