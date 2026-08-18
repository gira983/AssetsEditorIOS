# AssetsTools.NET iOS bridge

`AssetToolsBridge.Managed` is the functional AssetsTools.NET adapter. `AssetToolsBridge.Native` publishes that adapter with .NET NativeAOT and exports the C ABI function `uae_bridge_execute`.

CI publishes the native target as a static library for `ios-arm64` and `iossimulator-arm64`, links it directly into the Swift application, and keeps the .NET runtime inside the app executable. This avoids a launch-time dynamic-framework signature dependency on TrollStore. The generated C header remains the ABI documentation; Swift calls the exported symbol directly.

The iOS NativeAOT target is intentionally built separately from the Swift target: Swift never imports managed types or NuGet assemblies. The boundary is UTF-8 JSON over a small C ABI.

For a local device build, run the same bridge publish and static-library packaging steps before opening Xcode. A build without that generated archive cannot link the bridge; it is not a parser implementation.
