import StoatFeatures
import SwiftUI

@main
struct LiquidBagelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = LiquidBagelAppModel()

    var body: some Scene {
        RootScene(appModel: appModel)
            .commands {
                AppCommands()
            }
    }
}
