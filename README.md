# UnityAssetEditor



## Implemented

- Native Swift parser for SerializedFile headers, metadata, type records, object table, externals, reference-type metadata, and type-tree nodes.
- Object browser with Path ID, Unity type, byte offset, byte size, and a bounded hex preview inspector.
- UnityFS header and block/directory metadata reader. UnityFS block metadata decoding, LZ4/LZ4HC block decompression, and serialized-entry extraction are implemented. LZMA remains unsupported.
- Import into Application Support with a one-time `filename.assets.backup` copy.
- `Restore Original` uses a temporary replacement file and never overwrites the original backup.
- Persistent Recent Files list.
- SwiftUI UI, ViewModel, Core parser/backend, file-system, and backup-service layers.

## Dependencies

- Apple Foundation, SwiftUI, UniformTypeIdentifiers, Combine, XCTest.
- No third-party packages.
- AssetsTools.NET was used as the format reference during implementation; it is not embedded in the iOS target.

## Build

Open `UnityAssetEditor.xcodeproj` in Xcode 15 or newer, select the `UnityAssetEditor` scheme, choose an iPhone or iPad simulator/device, and press Run. The target is iOS 16.0+.

## Phase 3 and 4

- TypeTree-backed object field decoding for primitives, strings, PPtrs, GUID/Hash128 values, arrays, and nested structures.
- In-place editing for supported fixed-width primitive fields and same-length strings. Variable-length changes are rejected.
- Editor UI controls for supported fields; unsupported fields remain read-only.
- `SerializedFieldEditor` performs a full object-layout walk before committing changes, rejects unknown paths and size changes, and preserves the existing backup/Restore Original workflow.
- Hex Viewer with absolute offsets, ASCII/hex search, row highlighting, and field-aware raw-object inspection.
- Byte-level diff against the immutable original backup, with changed ranges and original/current bytes.
- Diff and Hex Viewer are available from the object inspector and file actions menu.
- LZ4/LZ4HC AssetBundle decompression and serialized-entry extraction are available; LZMA decoding remains unsupported.

## Phase 4

- Raw object Hex Viewer with absolute offsets, ASCII rendering, focused rows, and hex/ASCII search.
- Original-versus-current binary diff viewer backed by the immutable `filename.assets.backup` copy.
- Diff ranges show offsets, changed byte counts, file sizes, and original/current byte previews.
- Phase 4 source files are included in the application and test targets.
- UnityFS LZ4/LZ4HC decompression and extraction of embedded SerializedFiles are available; LZMA remains unsupported.

## Phase 5

- Fixed-width edit history with bounded Undo/Redo stacks.
- History entries record object, field, old value, new value, type, and timestamp.
- Undo and Redo reapply the same atomic transaction path used for normal edits.
- The History sheet provides Undo, Redo, Clear, and a chronological edit list.
- Transaction writes use a temporary file and replacement, so a failed write does not partially overwrite the working copy.
- Phase 5 tests cover history movement and atomic transaction cleanup.

## Phase 6 — UnityFS decompression and extraction

- UnityFS block and directory metadata are decoded into explicit models.
- LZ4 and LZ4HC block decompression is implemented in pure Swift with strict output-size and bounds validation.
- Serialized bundle entries can be extracted into `BundleEntryData`; their bytes are ready to pass into the existing SerializedFile parser.
- LZMA is reported as unsupported because the iOS target has no third-party decompression dependency.

## GitHub Actions

The repository includes `.github/workflows/build.yml`. It runs on `macos-14`, selects the latest stable Xcode, builds the `UnityAssetEditor` scheme for a generic iOS Simulator destination without code signing, and runs the XCTest suite.
