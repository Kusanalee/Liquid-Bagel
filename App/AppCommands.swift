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
            .keyboardShortcut(.upArrow, modifiers: [.command, .control])
            .disabled(commandHandler?.canPerform(.selectPreviousChannel) == false)

            Button("Next Channel") {
                commandHandler?.perform(.selectNextChannel)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .control])
            .disabled(commandHandler?.canPerform(.selectNextChannel) == false)

            Button("Jump to Newest Message") {
                commandHandler?.perform(.jumpToNewestMessage)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            .disabled(commandHandler?.canPerform(.jumpToNewestMessage) == false)

            Button("Jump to First Unread") {
                commandHandler?.perform(.jumpToFirstUnreadMessage)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.jumpToFirstUnreadMessage) == false)

            Button("Focus Timeline") {
                commandHandler?.perform(.focusTimeline)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.focusTimeline) == false)
        }

        CommandMenu("Message") {
            Button("Copy Message") {
                commandHandler?.perform(.copySelectedMessage)
            }
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.copySelectedMessage) == false)

            Button("Copy Message ID") {
                commandHandler?.perform(.copySelectedMessageID)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.copySelectedMessageID) == false)

            Button("Edit Message") {
                commandHandler?.perform(.editSelectedMessage)
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.editSelectedMessage) == false)

            Button("Reply to Message") {
                commandHandler?.perform(.replyToSelectedMessage)
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.replyToSelectedMessage) == false)

            Button("Cancel Reply") {
                commandHandler?.perform(.cancelReply)
            }
            .keyboardShortcut(.escape, modifiers: [.command])
            .disabled(commandHandler?.canPerform(.cancelReply) == false)

            Button("Delete Message") {
                commandHandler?.perform(.deleteSelectedMessage)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(commandHandler?.canPerform(.deleteSelectedMessage) == false)

            Button("Pin or Unpin Message") {
                commandHandler?.perform(.pinOrUnpinSelectedMessage)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.pinOrUnpinSelectedMessage) == false)

            Button("Retry Failed Message") {
                commandHandler?.perform(.retrySelectedMessage)
            }
            .disabled(commandHandler?.canPerform(.retrySelectedMessage) == false)

            Button("Discard Failed Message") {
                commandHandler?.perform(.discardSelectedFailedMessage)
            }
            .disabled(commandHandler?.canPerform(.discardSelectedFailedMessage) == false)
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
