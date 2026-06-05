import StoatFeatures
import StoatRealtime
import SwiftUI

struct RootScene: Scene {
    var body: some Scene {
        WindowGroup("Liquid Bagel") {
            LiquidBagelRootView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)

        Settings {
            CurrentSettingsSceneView()
        }
    }
}

private struct CurrentSettingsSceneView: View {
    @State private var sessionCoordinator = AppSessionCoordinator()
    @State private var viewModel = MainShellViewModel(
        snapshot: RealtimeSnapshot(),
        runtimeMode: .liveManual,
        sessionState: .signedOut,
        currentUser: nil
    )

    var body: some View {
        AccountConnectionSettingsView(viewModel: viewModel)
            .task {
                viewModel.attachSessionCoordinator(sessionCoordinator)
                await sessionCoordinator.startLiveFirstSession()
                viewModel.syncFromSessionCoordinator()
            }
    }
}
