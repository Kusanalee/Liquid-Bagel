import Foundation
import StoatFeatures
import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.appCommandHandler) private var commandHandler

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Direct Message") {
                commandHandler?.perform(.openQuickSwitcher)
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(true)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Button("Quick Switcher") {
                commandHandler?.perform(.openQuickSwitcher)
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.openQuickSwitcher) == false)

            Button("Focus Composer") {
                commandHandler?.perform(.focusComposer)
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.focusComposer) == false)

            Button("Refresh") {
                commandHandler?.perform(.refresh)
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.refresh) == false)

            Button("Reconnect") {
                commandHandler?.perform(.reconnect)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.reconnect) == false)

            Button("Toggle Member Panel") {
                commandHandler?.perform(.toggleMemberPanel)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.toggleMemberPanel) == false)

            Button("Previous Server") {
                commandHandler?.perform(.selectPreviousServer)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.selectPreviousServer) == false)

            Button("Next Server") {
                commandHandler?.perform(.selectNextServer)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.selectNextServer) == false)

            Button("Previous Channel") {
                commandHandler?.perform(.selectPreviousChannel)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            .disabled(commandHandler?.canPerform(.selectPreviousChannel) == false)

            Button("Next Channel") {
                commandHandler?.perform(.selectNextChannel)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            .disabled(commandHandler?.canPerform(.selectNextChannel) == false)
        }

        CommandGroup(after: .appSettings) {
            Button("Account & Connection Settings…") {
                commandHandler?.perform(.openAccountSettings)
            }
            .keyboardShortcut(",", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.openAccountSettings) == false)
        }

        CommandMenu("Servers") {
            ForEach(1...9, id: \.self) { index in
                Button("Select Server \(index)") {
                    commandHandler?.perform(.selectServer(index: index))
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: [.command])
                .disabled(commandHandler?.canPerform(.selectServer(index: index)) == false)
            }
        }
    }
}
