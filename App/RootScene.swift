import StoatFeatures
import SwiftUI

struct RootScene: Scene {
    var body: some Scene {
        WindowGroup("Liquid Bagel") {
            LiquidBagelRootView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)

        Settings {
            LiquidBagelSettingsView()
                .frame(width: 560, height: 420)
        }
    }
}
