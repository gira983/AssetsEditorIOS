import SwiftUI

@main
struct UnityAssetEditorApp: App {
    @State private var homeViewModel = HomeViewModel()

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: homeViewModel)
                .preferredColorScheme(.dark)
        }
    }
}
