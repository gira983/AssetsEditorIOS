# Parser diagnosis

Status: 2026-08-20

The current Swift implementation is not a complete Unity SerializedFile parser. It can identify and partially decode UnityFS bundles, but the SerializedFile reader uses a simplified, version-insensitive layout and therefore cannot reliably parse modern Unity assets.

## Observed symptoms

- `cache_res` and `assetindexer` show no objects because a bundle directory entry is being treated as a SerializedFile without validating the extracted payload and without loading a matching TypeTree/class database.
- Other files show objects but fields are binary-looking because raw object bytes are being presented as editable structured fields. That is expected when the TypeTree is absent, disabled, stripped, or decoded with the wrong Unity version/endian/layout.
- The UnityFS reader must handle header flags, `BlocksInfoAtEnd`, block compression, alignment, LZ4/LZ4HC and LZMA. The current code explicitly rejects LZMA and uses a local test LZ4 decoder; it is not enough for UABEA-level compatibility.
- A modern SerializedFile reader must parse the version-dependent header, metadata, endian flag, type records, type trees, externals, object table, and data offsets. Object data should be decoded through a TypeTree; when no TypeTree is embedded, a matching class database is required.

## Correct architecture decision

Do not invent an AssetsTools.NET API in the iOS target. Keep the Swift UI and file-security layer native. Put the real parser behind a documented bridge boundary.

Preferred first production path: build AssetsTools.NET in a separate .NET host/tool process or server-side worker and communicate with the iOS app using a versioned JSON/CBOR protocol. This avoids assuming that the current AssetsTools.NET package is directly linkable into an iOS arm64 target. A native iOS bridge is a separate porting project: it requires verifying every dependency under the exact .NET/iOS/NativeAOT configuration, trimming/reflection behavior, compression support, and licensing.

A native port should only be attempted after a real CI matrix proves the exact target builds and runs on a device. Until then, a Swift/Rust native parser or a companion macOS/Linux conversion service is technically honest; a fake C# export layer is not.

## Reference API facts verified against the upstream documentation

The documented AssetsTools.NET v3 flow uses `AssetsManager`, `LoadAssetsFile`, `LoadBundleFile`, `LoadClassPackage`/`LoadClassDatabaseFromPackage`, `GetBaseField`, `AssetFileInfoEx.SetNewData`, and `AssetsReplacerFromMemory`. These names must be used only in the actual .NET bridge project and only after compiling against the pinned package/source revision.
