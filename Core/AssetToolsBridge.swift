import Foundation

struct AssetToolsBridgeInfo: Hashable {
    let kind: String
    let unityVersion: String?
    let assetCount: Int
}

enum AssetToolsBridgeError: LocalizedError {
    case unavailable
    case invalidResponse
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "AssetsTools.NET is not embedded in this build."
        case .invalidResponse:
            return "The AssetsTools.NET bridge returned invalid data."
        case .unsupported(let message):
            return message
        }
    }
}

protocol AssetToolsBridge {
    func inspect(at url: URL) throws -> AssetToolsBridgeInfo
    func listObjects(at url: URL) throws -> [SerializedObjectInfo]
    func fields(for object: SerializedObjectInfo, at url: URL) throws -> [SerializedObjectField]
    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL, outputURL: URL) throws
    func writeBundle(at url: URL, outputURL: URL) throws
}

struct NativeAssetToolsBridge: AssetToolsBridge {
    private let client: NativeBridgeClient

    init(client: NativeBridgeClient = NativeBridgeClient()) {
        self.client = client
    }

    func inspect(at url: URL) throws -> AssetToolsBridgeInfo {
        let object = try jsonObject(client.inspect(path: url.path))
        guard let info = object["result"] as? [String: Any], let nestedInfo = info["info"] as? [String: Any], let kind = nestedInfo["kind"] as? String, let assetCount = nestedInfo["assetCount"] as? Int else { throw AssetToolsBridgeError.invalidResponse }
        return AssetToolsBridgeInfo(kind: kind, unityVersion: nestedInfo["unityVersion"] as? String, assetCount: assetCount)
    }

    func listObjects(at url: URL) throws -> [SerializedObjectInfo] {
        let object = try jsonObject(client.listObjects(path: url.path))
        guard let result = object["result"] as? [String: Any], let values = result["objects"] as? [[String: Any]] else { throw AssetToolsBridgeError.invalidResponse }
        return values.compactMap { value in
            guard let id = value["id"] as? String, let pathID = value["pathID"] as? Int64 ?? (value["pathID"] as? Int).map(Int64.init), let typeID = value["typeID"] as? Int, let byteOffset = value["byteOffset"] as? UInt64 ?? (value["byteOffset"] as? Int).map(UInt64.init), let byteSize = value["byteSize"] as? UInt64 ?? (value["byteSize"] as? Int).map(UInt64.init), let typeName = value["typeName"] as? String, let displayName = value["displayName"] as? String else { return nil }
            return SerializedObjectInfo(id: id, pathID: pathID, typeID: typeID, byteOffset: byteOffset, byteSize: byteSize, typeName: typeName, displayName: displayName)
        }
    }

    func fields(for object: SerializedObjectInfo, at url: URL) throws -> [SerializedObjectField] {
        let payload = try jsonObject(client.getFields(path: url.path, pathID: object.pathID))
        guard let result = payload["result"] as? [String: Any], let values = result["fields"] as? [[String: Any]] else { throw AssetToolsBridgeError.invalidResponse }
        return values.compactMap { value in
            guard let id = value["id"] as? String, let name = value["name"] as? String, let type = value["type"] as? String, let fieldValue = value["value"] as? String, let depth = value["depth"] as? Int, let editable = value["editable"] as? Bool else { return nil }
            return SerializedObjectField(id: id, name: name, type: type, value: fieldValue, depth: depth, editable: editable)
        }
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL, outputURL: URL) throws {
        try client.updateField(path: url.path, pathID: object.pathID, fieldPath: field.name, value: field.value, outputPath: outputURL.path)
    }

    func writeBundle(at url: URL, outputURL: URL) throws {
        try client.writeBundle(path: url.path, outputPath: outputURL.path)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AssetToolsBridgeError.invalidResponse }
        if let ok = object["ok"] as? Bool, !ok, let error = object["error"] as? String { throw AssetToolsBridgeError.unsupported(error) }
        return object
    }
}

struct UnavailableAssetToolsBridge: AssetToolsBridge {
    func inspect(at url: URL) throws -> AssetToolsBridgeInfo { throw AssetToolsBridgeError.unavailable }
    func listObjects(at url: URL) throws -> [SerializedObjectInfo] { throw AssetToolsBridgeError.unavailable }
    func fields(for object: SerializedObjectInfo, at url: URL) throws -> [SerializedObjectField] { throw AssetToolsBridgeError.unavailable }
    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL, outputURL: URL) throws { throw AssetToolsBridgeError.unavailable }
    func writeBundle(at url: URL, outputURL: URL) throws { throw AssetToolsBridgeError.unavailable }
}
