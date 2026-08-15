import Foundation

struct RawObjectData {
    let bytes: Data
    let absoluteOffset: Int

    var byteCount: Int { bytes.count }
    var absoluteEndOffset: Int { absoluteOffset + bytes.count }
}
