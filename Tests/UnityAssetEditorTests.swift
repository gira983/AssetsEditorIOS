import XCTest
@testable import UnityAssetEditor

final class UnityAssetEditorTests: XCTestCase {
    func testAssetFileStoresMetadata() {
        let url = URL(fileURLWithPath: "/tmp/example.assets")
        let file = AssetFile(
            fileName: "example.assets",
            fileSize: 1024,
            sandboxURL: url
        )

        XCTAssertEqual(file.fileName, "example.assets")
        XCTAssertEqual(file.fileSize, 1024)
        XCTAssertEqual(file.sandboxURL, url)
    }

    func testByteCountFormattingProducesReadableSize() {
        let value = ByteCountFormatter.string(fromByteCount: 1024, countStyle: .file)
        XCTAssertFalse(value.isEmpty)
    }
}
