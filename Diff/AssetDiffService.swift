import Foundation

struct AssetDiffService {
    func compare(originalURL: URL, currentURL: URL) throws -> AssetDiffSummary {
        let original = try read(originalURL)
        let current = try read(currentURL)
        let commonCount = min(original.count, current.count)
        var changedByteCount = abs(original.count - current.count)
        var ranges: [AssetDiffRange] = []
        var index = 0

        while index < commonCount {
            if original[index] == current[index] {
                index += 1
                continue
            }
            let start = index
            while index < commonCount && original[index] != current[index] { index += 1 }
            let end = index
            changedByteCount += end - start
            ranges.append(AssetDiffRange(
                startOffset: start,
                endOffset: end,
                originalBytes: Array(original[start..<end]),
                currentBytes: Array(current[start..<end])
            ))
        }

        if current.count != original.count {
            let start = commonCount
            let end = max(original.count, current.count)
            ranges.append(AssetDiffRange(
                startOffset: start,
                endOffset: end,
                originalBytes: Array(original.dropFirst(commonCount)),
                currentBytes: Array(current.dropFirst(commonCount))
            ))
        }

        return AssetDiffSummary(
            originalSize: original.count,
            currentSize: current.count,
            changedByteCount: changedByteCount,
            ranges: ranges
        )
    }

    private func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw AssetDiffError.unreadableFile(url.lastPathComponent)
        }
    }
}
