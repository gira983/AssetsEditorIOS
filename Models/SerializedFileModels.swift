import Foundation

struct SerializedFileInfo: Hashable {
    let formatVersion: UInt32
    let fileSize: UInt64
    let metadataSize: UInt64
    let dataOffset: UInt64
    let unityVersion: String
    let targetPlatform: UInt32
    let objectCount: Int
    let typeCount: Int
    let externalCount: Int
    let isBigEndian: Bool
}

struct SerializedObjectInfo: Identifiable, Hashable {
    let id: String
    let pathID: Int64
    let typeID: Int32
    let byteOffset: UInt64
    let byteSize: UInt32
    let typeName: String
    let displayName: String
}

struct SerializedObjectField: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let value: String
    let depth: Int
    let editable: Bool
}

enum SerializedFileError: LocalizedError {
    case notOpen
    case notSerializedFile
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .notOpen:
            return "No SerializedFile is open."
        case .notSerializedFile:
            return "The file does not look like a Unity SerializedFile."
        case .malformed(let message):
            return "The SerializedFile is malformed: \(message)."
        }
    }
}
