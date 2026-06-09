import StoatFeatures
import SwiftUI

struct RootScene: Scene {
    @State private var appModel = LiquidBagelAppModel()

    var body: some Scene {
        WindowGroup("Liquid Bagel") {
            LiquidBagelRootView(appModel: appModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)

        Settings {
            AccountConnectionSettingsView(viewModel: appModel.shell)
        }
    }
}
