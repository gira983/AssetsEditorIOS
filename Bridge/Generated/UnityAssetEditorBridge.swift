import Foundation
#if canImport(UnityAssetEditorBridge)
import UnityAssetEditorBridge
#endif

struct NativeBridgeClient {
    enum Error: LocalizedError {
        case unavailable
        case invalidResponse
        case operationFailed(String)
        case outputTooSmall

        var errorDescription: String? {
            switch self {
            case .unavailable: return "The AssetsTools.NET bridge is not embedded in this build."
            case .invalidResponse: return "The AssetsTools.NET bridge returned invalid JSON."
            case .operationFailed(let message): return message
            case .outputTooSmall: return "The bridge response exceeded its output buffer."
            }
        }
    }

    private let outputCapacity: Int32

    init(outputCapacity: Int32 = 16 * 1024 * 1024) {
        self.outputCapacity = outputCapacity
    }

    func inspect(path: String) throws -> Data {
        try execute(["operation": "inspect", "path": path])
    }

    func listObjects(path: String) throws -> Data {
        try execute(["operation": "listObjects", "path": path])
    }

    func getFields(path: String, pathId: Int64) throws -> Data {
        try execute(["operation": "getFields", "path": path, "pathId": pathId])
    }

    func updateField(path: String, pathId: Int64, fieldPath: String, value: String, outputPath: String) throws {
        _ = try execute([
            "operation": "updateField",
            "path": path,
            "pathId": pathId,
            "fieldPath": fieldPath,
            "value": value,
            "outputPath": outputPath
        ])
    }

    func writeBundle(path: String, outputPath: String) throws {
        _ = try execute(["operation": "writeBundle", "path": path, "outputPath": outputPath])
    }

    private func execute(_ request: [String: Any]) throws -> Data {
        let requestData = try JSONSerialization.data(withJSONObject: request, options: [])
        #if canImport(UnityAssetEditorBridge)
        var output = [UInt8](repeating: 0, count: Int(outputCapacity))
        let requestBytes = Array(requestData) + [0]
        let length = requestBytes.withUnsafeBufferPointer { requestBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                uae_bridge_execute(requestBuffer.baseAddress, outputBuffer.baseAddress, outputCapacity)
            }
        }
        guard length >= 0 else { throw Error.operationFailed("The native bridge failed with code \(length).") }
        guard Int(length) < output.count else { throw Error.outputTooSmall }
        let response = Data(output.prefix(Int(length)))
        guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw Error.invalidResponse
        }
        if let message = object["error"] as? String { throw Error.operationFailed(message) }
        return response
        #else
        throw Error.unavailable
        #endif
    }
}
