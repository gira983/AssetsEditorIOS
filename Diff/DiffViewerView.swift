import SwiftUI

struct DiffViewerView: View {
    let summary: AssetDiffSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overview
                    if summary.isIdentical {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.largeTitle)
                                .foregroundStyle(.green)
                            Text("No Changes")
                                .font(.headline)
                            Text("The current file matches the original backup.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                    } else {
                        ForEach(summary.ranges) { range in
                            DiffRangeRow(range: range)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Original vs Current")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.isIdentical ? "Files are identical" : "Changes detected")
                .font(.headline)
            HStack(spacing: 18) {
                metric("Changed bytes", ByteCountFormatter.string(fromByteCount: Int64(summary.changedByteCount), countStyle: .file))
                metric("Ranges", String(summary.ranges.count))
                metric("Current size", ByteCountFormatter.string(fromByteCount: Int64(summary.currentSize), countStyle: .file))
            }
            .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
    }
}

private struct DiffRangeRow: View {
    let range: AssetDiffRange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("0x\(String(range.startOffset, radix: 16, uppercase: true))–0x\(String(range.endOffset, radix: 16, uppercase: true))")
                .font(.caption.weight(.semibold).monospaced())
            HStack(alignment: .top, spacing: 12) {
                byteColumn(title: "Original", bytes: range.originalBytes)
                byteColumn(title: "Current", bytes: range.currentBytes)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func byteColumn(title: String, bytes: [UInt8]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes.map { String(format: "%02X", Int($0)) }.joined(separator: " ").isEmpty ? "—" : bytes.map { String(format: "%02X", Int($0)) }.joined(separator: " "))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
