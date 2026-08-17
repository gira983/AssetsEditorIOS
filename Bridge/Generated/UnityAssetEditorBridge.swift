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

struct NativeBridgeClient {
    private let outputCapacity: Int32

    init(outputCapacity: Int32 = 16 * 1024 * 1024) {
        self.outputCapacity = outputCapacity
    }

    func execute(operation: String, path: URL, outputPath: URL? = nil, pathId: Int64? = nil, fieldPath: String? = nil, value: String? = nil) throws -> NativeBridgeResponse {
        let request: [String: Any?] = [
            "operation": operation,
            "path": path.path,
            "outputPath": outputPath?.path,
            "pathId": pathId,
            "fieldPath": fieldPath,
            "value": value
        ]
        let body = try JSONSerialization.data(withJSONObject: request.compactMapValues { $0 })
        let responseData = try call(body)
        let response = try JSONDecoder().decode(NativeBridgeResponse.self, from: responseData)
        if let error = response.error {
            throw NativeBridgeError.operationFailed(error)
        }
        return response
    }

    private func call(_ request: Data) throws -> Data {
        #if canImport(UnityAssetEditorBridge)
        var requestBytes = Array(request) + [0]
        var output = [UInt8](repeating: 0, count: Int(outputCapacity))
        let length = requestBytes.withUnsafeMutableBufferPointer { requestBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                uae_bridge_execute(requestBuffer.baseAddress, outputBuffer.baseAddress, outputCapacity)
            }
        }
        guard length >= 0, Int(length) < output.count else {
            throw NativeBridgeError.callFailed(code: Int(length))
        }
        return Data(output.prefix(Int(length)))
        #else
        throw NativeBridgeError.unavailable
        #endif
    }
}

enum NativeBridgeError: LocalizedError {
    case unavailable
    case callFailed(code: Int)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The AssetsTools.NET native bridge is not linked in this build."
        case .callFailed(let code): return "The AssetsTools.NET bridge returned error code \(code)."
        case .operationFailed(let message): return message
        }
    }
}
