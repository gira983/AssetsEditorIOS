import Foundation

struct RawObjectDataProvider {
    func rawData(for object: SerializedObjectInfo, in session: SerializedFileSession) throws -> RawObjectData {
        guard let record = session.objectRecords.first(where: { $0.pathID == object.pathID }) else {
            throw SerializedFileError.malformed("object not found")
        }
        let start = Int(object.byteOffset)
        let count = Int(record.byteSize)
        guard start >= 0, count >= 0, start <= session.data.count - count else {
            throw SerializedFileError.malformed("object range exceeds file")
        }
        return RawObjectData(bytes: session.data[start..<(start + count)], absoluteOffset: start)
    }
}
