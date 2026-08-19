import Foundation

struct BridgeInspection {
    let unityVersion: String
    let assetCount: Int
}

enum AssetToolsBridgeError: LocalizedError {
    case invalidResponse
    case operationFailed(String)
    case missingResult
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The native AssetsTools.NET bridge returned invalid JSON."
        case .operationFailed(let message):
            return message
        case .missingResult:
            return "The native AssetsTools.NET bridge returned no result."
        case .invalidValue(let value):
            return "The native AssetsTools.NET bridge returned an invalid value: \(value)."
        }
    }
}

final class AssetToolsBridge {
    static let shared = AssetToolsBridge()

    private let lock = NSLock()
    private var initialized = false

    private init() {}

    func initialize() throws {
        try lock.withLock {
            if initialized { return }
            guard uae_bridge_initialize() == 0 else {
                throw AssetToolsBridgeError.operationFailed("The native AssetsTools.NET bridge failed to initialize.")
            }
            initialized = true
        }
    }

    func inspect(at url: URL) throws -> BridgeInspection {
        let result = try execute(["operation": "inspect", "path": url.path])["result"] as? [String: Any]
        guard let result, let info = result["info"] as? [String: Any] else {
            throw AssetToolsBridgeError.missingResult
        }
        return BridgeInspection(
            unityVersion: string(info["unityVersion"]) ?? "",
            assetCount: integer(info["assetCount"]) ?? 0
        )
    }

    func listObjects(at url: URL) throws -> [SerializedObjectInfo] {
        let result = try execute(["operation": "listObjects", "path": url.path])["result"] as? [String: Any]
        guard let result, let objects = result["objects"] as? [[String: Any]] else {
            throw AssetToolsBridgeError.missingResult
        }
        return try objects.map { object in
            guard let pathID = integer64(object["pathID"]),
                  let typeID = integer32(object["typeID"]),
                  let byteOffset = integer64(object["byteOffset"]),
                  let byteSize = integer64(object["byteSize"]),
                  let typeName = string(object["typeName"]),
                  let displayName = string(object["displayName"]) else {
                throw AssetToolsBridgeError.invalidResponse
            }
            return SerializedObjectInfo(
                id: string(object["id"]) ?? "\(pathID):\(typeID)",
                pathID: pathID,
                typeID: typeID,
                byteOffset: UInt64(byteOffset),
                byteSize: UInt32(byteSize),
                typeName: typeName,
                displayName: displayName
            )
        }
    }

    func fields(for object: SerializedObjectInfo, at url: URL) throws -> [SerializedObjectField] {
        let result = try execute([
            "operation": "getFields",
            "path": url.path,
            "pathId": object.pathID
        ])["result"] as? [String: Any]
        guard let result, let fields = result["fields"] as? [[String: Any]] else {
            throw AssetToolsBridgeError.missingResult
        }
        return try fields.map { field in
            guard let name = string(field["name"]),
                  let type = string(field["type"]),
                  let value = string(field["value"]),
                  let depth = integer(field["depth"]) else {
                throw AssetToolsBridgeError.invalidResponse
            }
            return SerializedObjectField(
                id: string(field["id"]) ?? name,
                name: name,
                type: type,
                value: value,
                depth: depth,
                editable: (field["editable"] as? Bool) ?? false
            )
        }
    }

    func updateField(_ field: SerializedObjectField, for object: SerializedObjectInfo, at url: URL, outputURL: URL) throws {
        _ = try execute([
            "operation": "updateField",
            "path": url.path,
            "pathId": object.pathID,
            "fieldPath": field.name,
            "value": field.value,
            "outputPath": outputURL.path
        ])
    }

    private func execute(_ request: [String: Any]) throws -> [String: Any] {
        try initialize()
        let data = try JSONSerialization.data(withJSONObject: request, options: [])
        let responseString: String = try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw AssetToolsBridgeError.invalidResponse
            }
            guard let result = uae_bridge_execute(baseAddress.assumingMemoryBound(to: UInt8.self), Int32(data.count)) else {
                throw AssetToolsBridgeError.operationFailed("The native AssetsTools.NET bridge returned no response.")
            }
            defer { uae_bridge_free(result) }
            return String(cString: result)
        }
        guard let response = try JSONSerialization.jsonObject(with: Data(responseString.utf8), options: []) as? [String: Any] else {
            throw AssetToolsBridgeError.invalidResponse
        }
        if response["ok"] as? Bool != true {
            throw AssetToolsBridgeError.operationFailed(string(response["error"]) ?? "The native AssetsTools.NET bridge request failed.")
        }
        return response
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func integer(_ value: Any?) -> Int? {
        (value as? NSNumber).map { $0.intValue }
    }

    private func integer32(_ value: Any?) -> Int32? {
        integer64(value).map(Int32.init)
    }

    private func integer64(_ value: Any?) -> Int64? {
        (value as? NSNumber).map { $0.int64Value }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

@_silgen_name("uae_bridge_initialize")
private func uae_bridge_initialize() -> Int32

@_silgen_name("uae_bridge_execute")
private func uae_bridge_execute(_ request: UnsafePointer<UInt8>, _ requestLength: Int32) -> UnsafeMutablePointer<CChar>?

@_silgen_name("uae_bridge_free")
private func uae_bridge_free(_ value: UnsafeMutablePointer<CChar>)
