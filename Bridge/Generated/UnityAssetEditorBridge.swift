import Foundation

#if canImport(UnityAssetEditorBridge)
import UnityAssetEditorBridge
#endif

struct NativeBridgeProbe {
    static func add(_ left: Int32, _ right: Int32) -> Int32? {
        #if canImport(UnityAssetEditorBridge)
        return uae_bridge_add(left, right)
        #else
        return nil
        #endif
    }
}
