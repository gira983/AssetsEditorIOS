import Foundation

struct AssetToolsBridgeInfo: Hashable {
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

enum AssetToolsBridgeError: LocalizedError {
    case unavailable
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The AssetsTools.NET bridge is not included in this build yet."
        case .unsupported(let message):
            return message
        }
    }
}

protocol AssetToolsBridge {
    func openSerializedFile(at url: URL) throws -> AssetToolsBridgeInfo
    func objects() throws -> [SerializedObjectInfo]
    func fields(for object: SerializedObjectInfo) throws -> [SerializedObjectField]
    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL) throws
    func close()
}

struct UnavailableAssetToolsBridge: AssetToolsBridge {
    func openSerializedFile(at url: URL) throws -> AssetToolsBridgeInfo {
        throw AssetToolsBridgeError.unavailable
    }

    func objects() throws -> [SerializedObjectInfo] {
        throw AssetToolsBridgeError.unavailable
    }

    func fields(for object: SerializedObjectInfo) throws -> [SerializedObjectField] {
        throw AssetToolsBridgeError.unavailable
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL) throws {
        throw AssetToolsBridgeError.unavailable
    }

    func close() {}
}
