import StoatFeatures
import SwiftUI

@main
struct LiquidBagelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        RootScene()
            .commands {
                AppCommands()
            }
    }
}
