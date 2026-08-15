import Foundation

enum HexSearchMode: String, CaseIterable, Identifiable {
    case hex
    case ascii

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

struct HexSearchService {
    func matches(in data: Data, query: String, mode: HexSearchMode) -> [Int] {
        let pattern: [UInt8]
        switch mode {
        case .hex:
            guard let value = parseHex(query) else { return [] }
            pattern = value
        case .ascii:
            pattern = Array(query.utf8)
        }
        guard !pattern.isEmpty, pattern.count <= data.count else { return [] }
        let bytes = Array(data)
        return (0...(bytes.count - pattern.count)).filter { start in
            bytes[start..<(start + pattern.count)].elementsEqual(pattern)
        }
    }

    private func parseHex(_ query: String) -> [UInt8]? {
        let compact = query.filter { $0.isHexDigit }
        guard compact.count == query.filter({ !$0.isWhitespace && $0 != "," && $0 != "-" }).count,
              compact.count % 2 == 0 else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(compact.count / 2)
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }
}
