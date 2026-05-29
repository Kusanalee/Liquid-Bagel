import Foundation
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Direct Message") {
                post(.liquidBagelNewDirectMessage)
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(true)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Button("Quick Switcher") {
                post(.liquidBagelShowQuickSwitcher)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Focus Composer") {
                post(.liquidBagelFocusComposer)
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button("Refresh / Reconnect") {
                post(.liquidBagelRefresh)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

extension Notification.Name {
    static let liquidBagelNewDirectMessage = Notification.Name("LiquidBagelNewDirectMessage")
    static let liquidBagelShowQuickSwitcher = Notification.Name("LiquidBagelShowQuickSwitcher")
    static let liquidBagelFocusComposer = Notification.Name("LiquidBagelFocusComposer")
    static let liquidBagelRefresh = Notification.Name("LiquidBagelRefresh")
}
