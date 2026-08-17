import Foundation

#if canImport(UnityAssetEditorBridge)
import UnityAssetEditorBridge
#endif

struct NativeBridgeResponse: Decodable {
    let info: NativeBridgeInfo?
    let assets: [NativeBridgeAsset]
    let error: String?
}

struct NativeBridgeInfo: Decodable {
    let path: String
    let kind: String
    let assetCount: Int
    let unityVersion: String?
}

struct NativeBridgeAsset: Decodable, Identifiable {
    let fileName: String
    let pathId: Int64
    let classId: Int
    let byteSize: Int64
    let assetType: String
    let name: String?

    var id: String { "\(fileName):\(pathId):\(classId)" }
}

enum NativeBridgeError: LocalizedError {
    case unavailable
    case failed(String)
    case outputTooSmall

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The AssetsTools.NET bridge is not included in this build."
        case .failed(let message): return message
        case .outputTooSmall: return "The AssetsTools.NET bridge response is too large."
        }
    }
}

struct NativeAssetsToolsBridge {
    private let outputCapacity: Int32

    init(outputCapacity: Int32 = 16 * 1024 * 1024) {
        self.outputCapacity = outputCapacity
    }

    func execute(operation: String, path: URL, outputPath: URL? = nil, pathID: Int64? = nil, fieldPath: String? = nil, value: String? = nil) throws -> NativeBridgeResponse {
        #if canImport(UnityAssetEditorBridge)
        let request: [String: Any?] = [
            "operation": operation,
            "path": path.path,
            "outputPath": outputPath?.path,
            "pathId": pathID,
            "fieldPath": fieldPath,
            "value": value
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request.compactMapValues { $0 })
        let requestBytes = Array(requestData) + [0]
        var output = [UInt8](repeating: 0, count: Int(outputCapacity))
        let length = requestBytes.withUnsafeBufferPointer { requestBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                uae_bridge_execute(requestBuffer.baseAddress, outputBuffer.baseAddress, outputCapacity)
            }
        }
        guard length >= 0 else {
            throw NativeBridgeError.failed("AssetsTools.NET bridge failed with code \(length).")
        }
        guard Int(length) < output.count else { throw NativeBridgeError.outputTooSmall }
        let responseData = Data(output.prefix(Int(length)))
        let response = try JSONDecoder().decode(NativeBridgeResponse.self, from: responseData)
        if let error = response.error { throw NativeBridgeError.failed(error) }
        return response
        #else
        throw NativeBridgeError.unavailable
        #endif
    }
}
