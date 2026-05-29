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

            Button("Toggle Member Panel") {
                post(.liquidBagelToggleMembers)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appSettings) {
            Button("Liquid Bagel Settings Placeholder") {
                post(.liquidBagelShowSettingsPlaceholder)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandMenu("Servers") {
            ForEach(1...9, id: \.self) { index in
                Button("Select Server \(index)") {
                    post(Notification.Name("LiquidBagelSelectServer\(index)"))
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: [.command])
            }
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
    static let liquidBagelToggleMembers = Notification.Name("LiquidBagelToggleMembers")
    static let liquidBagelShowSettingsPlaceholder = Notification.Name("LiquidBagelShowSettingsPlaceholder")
}
