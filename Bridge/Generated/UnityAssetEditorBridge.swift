import Foundation

#if canImport(UnityAssetEditorBridge)
import UnityAssetEditorBridge
#endif

struct NativeBridgeProbe {
    static func inspect(path: String, outputCapacity: Int32 = 1_048_576) -> String? {
        #if canImport(UnityAssetEditorBridge)
        let pathBytes = Array(path.utf8) + [0]
        var output = [UInt8](repeating: 0, count: Int(outputCapacity))
        let length = pathBytes.withUnsafeBufferPointer { pathBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                uae_bridge_inspect(pathBuffer.baseAddress, outputBuffer.baseAddress, outputCapacity)
            }
        }
        guard length >= 0, Int(length) < output.count else { return nil }
        return String(bytes: output.prefix(Int(length)), encoding: .utf8)
        #else
        return nil
        #endif
    }
}
