import SwiftUI

struct HexInspectorView: View {
    let rawData: RawObjectData
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HexViewerView(rawData: rawData, fields: [], viewModel: viewModel)
            .onDisappear { viewModel.clearHexFocus() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
    }
}
