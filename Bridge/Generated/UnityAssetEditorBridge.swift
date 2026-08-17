import Foundation

#if canImport(UnityAssetEditorBridge)
import UnityAssetEditorBridge
#endif

struct BridgeFileInfo: Decodable {
    let formatVersion: UInt32
    let fileSize: UInt64
    let metadataSize: UInt64
    let dataOffset: UInt64
    let unityVersion: String?
    let targetPlatform: UInt32?
    let objectCount: Int
    let typeCount: Int?
    let externalCount: Int?
    let isBigEndian: Bool?
}

struct BridgeAssetInfo: Decodable {
    let fileName: String
    let pathId: Int64
    let classId: Int
    let byteSize: Int64
    let assetType: String
    let name: String?
}

struct BridgeResponse: Decodable {
    let info: BridgeFileInfo?
    let assets: [BridgeAssetInfo]
    let error: String?
}

enum AssetsToolsNativeBridgeError: LocalizedError {
    case unavailable
    case invalidRequest
    case outputTooSmall
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The AssetsTools.NET native bridge is not linked in this build."
        case .invalidRequest: return "The native bridge rejected the request."
        case .outputTooSmall: return "The native bridge response exceeded its output buffer."
        case .failed(let message): return message
        }
    }
}

struct AssetsToolsNativeBridge {
    private let outputCapacity: Int32

    init(outputCapacity: Int32 = 16 * 1024 * 1024) {
        self.outputCapacity = outputCapacity
    }

    func inspect(path: URL) throws -> BridgeResponse {
        try execute(operation: "inspect", path: path)
    }

    func readObject(path: URL, pathId: Int64) throws -> BridgeResponse {
        try execute(operation: "readObject", path: path, pathId: pathId)
    }

    func updateField(path: URL, pathId: Int64, fieldPath: String, value: String, outputPath: URL) throws -> BridgeResponse {
        try execute(operation: "updateField", path: path, outputPath: outputPath, pathId: pathId, fieldPath: fieldPath, value: value)
    }

    func writeBundle(path: URL, outputPath: URL) throws -> BridgeResponse {
        try execute(operation: "writeBundle", path: path, outputPath: outputPath)
    }

    private func execute(operation: String, path: URL, outputPath: URL? = nil, pathId: Int64? = nil, fieldPath: String? = nil, value: String? = nil) throws -> BridgeResponse {
        let request: [String: Any?] = [
            "operation": operation,
            "path": path.path,
            "outputPath": outputPath?.path,
            "pathId": pathId,
            "fieldPath": fieldPath,
            "value": value
        ]
        let body = try JSONSerialization.data(withJSONObject: request.compactMapValues { $0 })
        var responseData = Data(count: Int(outputCapacity))
        let resultLength: Int32 = body.withUnsafeBytes { requestBuffer in
            responseData.withUnsafeMutableBytes { responseBuffer in
                guard let requestBase = requestBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let responseBase = responseBuffer.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                #if canImport(UnityAssetEditorBridge)
                return uae_bridge_execute(requestBase, responseBase, outputCapacity)
                #else
                return -4
                #endif
            }
        }
        if resultLength == -4 { throw AssetsToolsNativeBridgeError.unavailable }
        guard resultLength >= 0, Int(resultLength) <= responseData.count else {
            if resultLength == -3 { throw AssetsToolsNativeBridgeError.outputTooSmall }
            throw AssetsToolsNativeBridgeError.invalidRequest
        }
        responseData.removeSubrange(Int(resultLength)..<responseData.count)
        let response = try JSONDecoder().decode(BridgeResponse.self, from: responseData)
        if let error = response.error { throw AssetsToolsNativeBridgeError.failed(error) }
        return response
    }
}
