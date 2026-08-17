import Foundation

struct AssetToolsBridgeInfo: Hashable {
    let path: String
    let kind: String
    let assetCount: Int
    let unityVersion: String?
}

enum AssetToolsBridgeError: LocalizedError {
    case unavailable
    case malformedResponse
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "AssetsTools.NET bridge is not embedded in this build."
        case .malformedResponse:
            return "AssetsTools.NET bridge returned invalid metadata."
        case .unsupported(let message):
            return message
        }
    }
}

protocol AssetToolsBridge {
    func openSerializedFile(at url: URL) throws -> AssetToolsBridgeInfo
    func listObjects(at url: URL) throws -> [SerializedObjectInfo]
    func fields(for object: SerializedObjectInfo, at url: URL) throws -> [SerializedObjectField]
    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL, outputURL: URL) throws
}

struct NativeAssetToolsBridge: AssetToolsBridge {
    private let client: NativeBridgeClient

    init(client: NativeBridgeClient = NativeBridgeClient()) {
        self.client = client
    }

    func openSerializedFile(at url: URL) throws -> AssetToolsBridgeInfo {
        let response = try client.inspect(path: url.path)
        let object = try parseObject(response)
        guard let info = object["info"] as? [String: Any],
              let path = info["path"] as? String,
              let kind = info["kind"] as? String,
              let assetCount = info["assetCount"] as? Int else {
            throw AssetToolsBridgeError.malformedResponse
        }
        return AssetToolsBridgeInfo(path: path, kind: kind, assetCount: assetCount, unityVersion: info["unityVersion"] as? String)
    }

    func listObjects(at url: URL) throws -> [SerializedObjectInfo] {
        let response = try client.listObjects(path: url.path)
        let object = try parseObject(response)
        guard let values = object["objects"] as? [[String: Any]] else { throw AssetToolsBridgeError.malformedResponse }
        return values.compactMap(Self.objectInfo)
    }

    func fields(for object: SerializedObjectInfo, at url: URL) throws -> [SerializedObjectField] {
        let response = try client.getFields(path: url.path, pathId: object.pathID)
        let object = try parseObject(response)
        guard let values = object["fields"] as? [[String: Any]] else { throw AssetToolsBridgeError.malformedResponse }
        return values.compactMap(Self.objectField)
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL, outputURL: URL) throws {
        try client.updateField(path: url.path, pathId: object.pathID, fieldPath: field.name, value: field.value, outputPath: outputURL.path)
    }

    private func parseObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AssetToolsBridgeError.malformedResponse }
        return object
    }

    private static func objectInfo(_ value: [String: Any]) -> SerializedObjectInfo? {
        guard let id = value["id"] as? String, let pathID = value["pathID"] as? Int64, let typeID = value["typeID"] as? Int, let byteOffset = value["byteOffset"] as? UInt64, let byteSize = value["byteSize"] as? UInt64, let typeName = value["typeName"] as? String, let displayName = value["displayName"] as? String else { return nil }
        return SerializedObjectInfo(id: id, pathID: pathID, typeID: typeID, byteOffset: byteOffset, byteSize: byteSize, typeName: typeName, displayName: displayName)
    }

    private static func objectField(_ value: [String: Any]) -> SerializedObjectField? {
        guard let id = value["id"] as? String, let name = value["name"] as? String, let type = value["type"] as? String, let fieldValue = value["value"] as? String, let depth = value["depth"] as? Int, let editable = value["editable"] as? Bool else { return nil }
        return SerializedObjectField(id: id, name: name, type: type, value: fieldValue, depth: depth, editable: editable)
    }
}

struct UnavailableAssetToolsBridge: AssetToolsBridge {
    func openSerializedFile(at url: URL) throws -> AssetToolsBridgeInfo { throw AssetToolsBridgeError.unavailable }
    func listObjects(at url: URL) throws -> [SerializedObjectInfo] { throw AssetToolsBridgeError.unavailable }
    func fields(for object: SerializedObjectInfo, at url: URL) throws -> [SerializedObjectField] { throw AssetToolsBridgeError.unavailable }
    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL, outputURL: URL) throws { throw AssetToolsBridgeError.unavailable }
}
