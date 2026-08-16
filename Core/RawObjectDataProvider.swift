import Foundation

struct RawObjectDataProvider {
    func rawData(for object: SerializedObjectInfo, in session: SerializedFileSession) throws -> RawObjectData {
        guard let record = session.objectRecords.first(where: { $0.pathID == object.pathID }) else {
            throw SerializedFileError.malformed("object not found")
        }
        let start64 = object.byteOffset
        let count64 = UInt64(record.byteSize)
        guard start64 <= UInt64(session.data.count),
              count64 <= UInt64(session.data.count) - start64,
              start64 <= UInt64(Int.max),
              count64 <= UInt64(Int.max) else {
            throw SerializedFileError.malformed("object range exceeds file")
        }
        let start = Int(start64)
        let count = Int(count64)
        return RawObjectData(bytes: Data(session.data[start..<(start + count)]), absoluteOffset: start)
    }
}
