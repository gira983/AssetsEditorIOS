import SwiftUI

struct HexViewerView: View {
    let rawData: RawObjectData
    let fields: [SerializedObjectField]
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    private let searchService = HexSearchService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                rangeHeader
                Divider()
                hexRows
            }
            .navigationTitle("Raw Data / Hex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack {
                TextField(viewModel.hexSearchMode == .hex ? "FF FF 00 00" : "ASCII text", text: $viewModel.hexSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Picker("Search mode", selection: $viewModel.hexSearchMode) {
                    ForEach(HexSearchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            HStack {
                Text("Matches: \(matches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let first = matches.first {
                    Button("First") { viewModel.focusHex(offset: rawData.absoluteOffset + first) }
                        .font(.caption)
                }
            }
        }
        .padding(12)
    }

    private var rangeHeader: some View {
        HStack {
            Text("Absolute 0x\(String(rawData.absoluteOffset, radix: 16))–0x\(String(rawData.absoluteEndOffset, radix: 16))")
            Spacer()
            Text("\(rawData.byteCount) bytes")
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var hexRows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stride(from: 0, to: rawData.bytes.count, by: 16)), id: \.self) { rowStart in
                        HexRow(
                            absoluteOffset: rawData.absoluteOffset + rowStart,
                            bytes: bytesForRow(start: rowStart),
                            isFocused: focusedRowStart == rowStart,
                            isMatched: matches.contains { $0 >= rowStart && $0 < rowStart + 16 }
                        )
                        .id(rowStart)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { scrollToFocus(proxy) }
            .onChange(of: viewModel.hexFocusOffset) { _ in scrollToFocus(proxy) }
        }
    }

    private func bytesForRow(start: Int) -> [UInt8] {
        guard start >= 0, start < rawData.bytes.count else { return [] }
        let end = min(start + 16, rawData.bytes.count)
        return Array(rawData.bytes[start..<end])
    }

    private var matches: [Int] {
        searchService.matches(in: rawData.bytes, query: viewModel.hexSearchQuery, mode: viewModel.hexSearchMode)
    }

    private var focusedRowStart: Int? {
        guard let focus = viewModel.hexFocusOffset else { return nil }
        let relative = focus - rawData.absoluteOffset
        guard relative >= 0, relative < rawData.bytes.count else { return nil }
        return (relative / 16) * 16
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let row = focusedRowStart else { return }
        withAnimation { proxy.scrollTo(row, anchor: .center) }
    }
}

private struct HexRow: View {
    let absoluteOffset: Int
    let bytes: [UInt8]
    let isFocused: Bool
    let isMatched: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%08X", absoluteOffset))
                .foregroundStyle(.secondary)
            Text(hex)
                .foregroundStyle(isMatched ? .yellow : .primary)
                .frame(width: 16 * 3 + 15, alignment: .leading)
            Text(ascii)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isFocused ? Color.accentColor.opacity(0.2) : (isMatched ? Color.yellow.opacity(0.08) : .clear))
    }

    private var hex: String {
        bytes.enumerated().map { index, byte in
            let value = String(format: "%02X", Int(byte))
            return index == 15 ? value : value + " "
        }.joined() + String(repeating: "   ", count: max(0, 16 - bytes.count))
    }

    private var ascii: String {
        bytes.map { byte in
            byte >= 0x20 && byte < 0x7F ? String(UnicodeScalar(byte)) : "."
        }.joined()
    }
}
