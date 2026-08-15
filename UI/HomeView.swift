import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let selectedFile = viewModel.selectedFile {
                    editorView(for: selectedFile)
                } else {
                    homeView
                }
            }
            .navigationTitle("UnityAssetEditor")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { viewModel.undo() } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!viewModel.canUndo)
                    Button { viewModel.redo() } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!viewModel.canRedo)
                    if viewModel.selectedFile != nil {
                        Button { viewModel.isShowingHistory = true } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    Button {
                        viewModel.isShowingFileImporter = true
                    } label: {
                        Label("Open", systemImage: "folder.badge.plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $viewModel.isShowingFileImporter,
            allowedContentTypes: viewModel.fileTypeFilter(),
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.importFile(from: url)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert("UnityAssetEditor", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var homeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                openCard
                recentFilesSection
            }
            .padding(20)
        }
    }

    private func editorView(for file: AssetFile) -> some View {
        VStack(spacing: 0) {
            fileSummary(file)
            if viewModel.isLoading {
                ProgressView("Reading Unity file…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let bundle = viewModel.selectedBundleInfo {
                bundleSummary(bundle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            } else if viewModel.selectedObjects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Objects")
                        .font(.headline)
                    Text("The file was opened, but it contains no readable object records.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.selectedObjects) { object in
                    Button {
                        viewModel.selectObject(object)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(object.displayName)
                                    .font(.body.weight(.medium))
                                Text("Path ID \(object.pathID) · \(object.byteSize) bytes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedObject?.id == object.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            objectInspector
        }
        .sheet(isPresented: $viewModel.isShowingHexViewer) {
            if let rawData = viewModel.selectedRawObjectData {
                HexInspectorView(rawData: rawData, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.isShowingDiffViewer) {
            if let summary = viewModel.diffSummary {
                DiffViewerView(summary: summary)
            }
        }
        .sheet(isPresented: $viewModel.isShowingHistory) {
            EditorHistoryView(
                entries: viewModel.historyEntries,
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                onUndo: viewModel.undo,
                onRedo: viewModel.redo,
                onClear: viewModel.clearHistory
            )
        }
    }

    private func fileSummary(_ file: AssetFile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(file.fileName, systemImage: "doc.badge.gearshape")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button("Create Backup") { viewModel.createBackup() }
                    Button("Compare with Original") { viewModel.showDiffViewer() }
                        .disabled(!viewModel.hasBackup(for: file))
                    Button("Restore Original", role: .destructive) { viewModel.restoreOriginal() }
                        .disabled(!viewModel.hasBackup(for: file))
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
            if let bundle = viewModel.selectedBundleInfo {
                HStack(spacing: 16) {
                    metric("Unity", bundle.unityVersion.isEmpty ? "Unknown" : bundle.unityVersion)
                    metric("Format", String(bundle.formatVersion))
                    metric("Blocks", String(bundle.blockCount))
                    metric("Entries", String(bundle.directoryEntryCount))
                }
                .font(.caption)
            } else if let info = viewModel.selectedFileInfo {
                HStack(spacing: 16) {
                    metric("Unity", info.unityVersion.isEmpty ? "Unknown" : info.unityVersion)
                    metric("Format", String(info.formatVersion))
                    metric("Objects", String(info.objectCount))
                    metric("Endian", info.isBigEndian ? "Big" : "Little")
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func bundleSummary(_ bundle: AssetBundleInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AssetBundle detected", systemImage: "shippingbox")
                .font(.headline)
            Text(bundle.unityVersion.isEmpty ? "Unity version unknown" : bundle.unityVersion)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                metric("Format", String(bundle.formatVersion))
                metric("Blocks", String(bundle.blockCount))
                metric("Files", String(bundle.directoryEntryCount))
                metric("Compression", bundle.compressionType.displayName)
            }
            List(viewModel.selectedBundleEntries) { entry in
                Button {
                    viewModel.extractBundleEntry(entry)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: entry.isSerialized ? "doc.text" : "doc")
                            .foregroundStyle(entry.isSerialized ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                                .lineLimit(1)
                            Text("\(entry.decompressedSize) bytes · \(entry.isSerialized ? "SerializedFile" : "Resource")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(entry.isDeleted || entry.isDirectory)
            }
            .frame(minHeight: 180, maxHeight: 420)
            Text("Select an entry to extract it into the local workspace and open it in the SerializedFile editor.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
    }

    private var objectInspector: some View {
        Group {
            if let object = viewModel.selectedObject {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(object.displayName).font(.headline)
                        Spacer()
                        Button { viewModel.showDiffViewer() } label: {
                            Image(systemName: "arrow.left.and.right")
                        }
                        .disabled(viewModel.selectedFile.map { !viewModel.hasBackup(for: $0) } ?? true)
                        Button { viewModel.showHexViewer() } label: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                        }
                        Button("Close") { viewModel.clearSelectedObject() }
                            .font(.subheadline)
                    }
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.selectedObjectFields) { field in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if field.editable {
                                        EditableFieldCell(field: field) { value in
                                            viewModel.updateField(field, value: value)
                                        }
                                    } else {
                                        Text(field.value.isEmpty ? "—" : field.value)
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(3)
                                    }
                                }
                                .padding(.leading, CGFloat(field.depth) * 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
                .padding(14)
                .background(.regularMaterial)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UnityAssetEditor")
                .font(.largeTitle.bold())
            Text("Native SerializedFile workspace")
                .foregroundStyle(.secondary)
        }
    }

    private var openCard: some View {
        Button {
            viewModel.isShowingFileImporter = true
        } label: {
            Label("Open Unity File", systemImage: "folder.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.accentColor.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Files")
                .font(.headline)
            if viewModel.recentFiles.isEmpty {
                Text("Imported files will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.recentFiles) { file in
                    RecentFileRow(file: file) {
                        viewModel.openRecentFile(file)
                    } onDelete: {
                        viewModel.removeRecentFile(file)
                    }
                }
            }
        }
    }
}

private struct EditableFieldCell: View {
    let field: SerializedObjectField
    let onCommit: (String) -> Void
    @State private var draft: String

    init(field: SerializedObjectField, onCommit: @escaping (String) -> Void) {
        self.field = field
        self.onCommit = onCommit
        _draft = State(initialValue: field.value)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(field.type, text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onSubmit { onCommit(draft) }
            Button("Apply") { onCommit(draft) }
                .font(.caption.weight(.semibold))
        }
    }
}

private struct RecentFileRow: View {
    let file: AssetFile
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: "doc")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.fileName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove \(file.fileName) from recent files")
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel())
}
