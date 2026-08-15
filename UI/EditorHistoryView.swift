import SwiftUI

struct EditorHistoryView: View {
    let entries: [EditorHistoryEntry]
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: onUndo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo)
                    Button(action: onRedo) {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo)
                    Spacer()
                    Button("Clear", role: .destructive, action: onClear)
                        .disabled(entries.isEmpty && !canRedo)
                }
                .buttonStyle(.bordered)
                .padding(16)

                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Edits Yet")
                            .font(.headline)
                        Text("Changes to supported fields will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.fieldName)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(entry.fieldType)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.oldValue)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right")
                                Text(entry.newValue)
                            }
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Edit History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
