# NativeAOT bridge proof of concept

This project is intentionally a separate proof-of-concept target. It verifies that the selected .NET NativeAOT toolchain can emit an iOS-compatible native library and that Swift can consume a C ABI. It does not yet expose AssetsTools.NET operations.

The managed worker in `Bridge/AssetToolsBridge.Managed/` is the functional AssetsTools.NET adapter for this stage. The native target becomes the production adapter only after the same upstream operations pass device and simulator builds.
