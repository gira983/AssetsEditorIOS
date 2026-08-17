# AssetsTools.NET iOS bridge

`AssetToolsBridge.Managed` is the functional AssetsTools.NET adapter. `AssetToolsBridge.Native` publishes that adapter with .NET NativeAOT and exports the C ABI function `uae_bridge_execute`.

CI publishes the native target for `ios-arm64`, packages the resulting dylib as `Bridge/Build/UnityAssetEditorBridge.framework`, and links and embeds that framework into the Swift application. The framework contains the generated C header and module map consumed by `NativeBridgeClient`.

The iOS NativeAOT target is intentionally built separately from the Swift target: Swift never imports managed types or NuGet assemblies. The boundary is UTF-8 JSON over a small C ABI.

For a local device build, run the same bridge publish and framework-packaging steps before opening Xcode. A build without that generated framework must remain an explicit unavailable development configuration; it is not a parser implementation.
