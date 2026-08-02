import Foundation
import StoatFeatures
import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.appCommandHandler) private var commandHandler

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Direct Message") {
                commandHandler?.perform(.openNewDirectMessage)
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.openNewDirectMessage) == false)

            Button("New Group") {
                commandHandler?.perform(.openNewGroup)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.openNewGroup) == false)
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
            .keyboardShortcut(Phase71Keybinds.verifiedMacShortcuts[.selectPreviousServer]!.key,
                              modifiers: Phase71Keybinds.verifiedMacShortcuts[.selectPreviousServer]!.modifiers)
            .disabled(commandHandler?.canPerform(.selectPreviousServer) == false)

            Button("Next Server") {
                commandHandler?.perform(.selectNextServer)
            }
            .keyboardShortcut(Phase71Keybinds.verifiedMacShortcuts[.selectNextServer]!.key,
                              modifiers: Phase71Keybinds.verifiedMacShortcuts[.selectNextServer]!.modifiers)
            .disabled(commandHandler?.canPerform(.selectNextServer) == false)

            Button("Previous Channel") {
                commandHandler?.perform(.selectPreviousChannel)
            }
            .keyboardShortcut(Phase71Keybinds.verifiedMacShortcuts[.selectPreviousChannel]!.key,
                              modifiers: Phase71Keybinds.verifiedMacShortcuts[.selectPreviousChannel]!.modifiers)
            .disabled(commandHandler?.canPerform(.selectPreviousChannel) == false)

            Button("Next Channel") {
                commandHandler?.perform(.selectNextChannel)
            }
            .keyboardShortcut(Phase71Keybinds.verifiedMacShortcuts[.selectNextChannel]!.key,
                              modifiers: Phase71Keybinds.verifiedMacShortcuts[.selectNextChannel]!.modifiers)
            .disabled(commandHandler?.canPerform(.selectNextChannel) == false)

            Button("Jump to Newest Message") {
                commandHandler?.perform(.jumpToNewestMessage)
            }
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

            Button("Search This Channel") {
                commandHandler?.perform(.openChannelSearch)
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.openChannelSearch) == false)

            Button("Find in Loaded Messages") {
                commandHandler?.perform(.openLoadedMessageFind)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.openLoadedMessageFind) == false)

            Button("Live Search Selected Channel") {
                commandHandler?.perform(.openLiveChannelSearch)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.openLiveChannelSearch) == false)

            Divider()

            // Verified against the official macOS keybind table (Docs/Research.md Phase 58 Notes):
            // CHAT_JUMP_END = Escape, CHAT_MARK_SERVER_AS_READ = Shift-Escape.
            Button("Mark Channel Read") {
                commandHandler?.perform(.markSelectedChannelRead)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(commandHandler?.canPerform(.markSelectedChannelRead) == false)

            Button("Mark Server Read") {
                commandHandler?.perform(.markSelectedServerRead)
            }
            .keyboardShortcut(.escape, modifiers: [.shift])
            .disabled(commandHandler?.canPerform(.markSelectedServerRead) == false)
        }

        CommandMenu("Search") {
            Button("Pinned in This Channel") {
                commandHandler?.perform(.openPinnedChannelSearch)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.openPinnedChannelSearch) == false)

            Button("Previous Search Result") {
                commandHandler?.perform(.selectPreviousSearchResult)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.selectPreviousSearchResult) == false)

            Button("Next Search Result") {
                commandHandler?.perform(.selectNextSearchResult)
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(commandHandler?.canPerform(.selectNextSearchResult) == false)

            Button("Previous Search Result by Row") {
                commandHandler?.perform(.selectPreviousSearchResult)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.selectPreviousSearchResult) == false)

            Button("Next Search Result by Row") {
                commandHandler?.perform(.selectNextSearchResult)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.selectNextSearchResult) == false)

            Button("Jump to Search Result") {
                commandHandler?.perform(.jumpToSelectedSearchResult)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(commandHandler?.canPerform(.jumpToSelectedSearchResult) == false)

            Button("Load Around Search Result") {
                commandHandler?.perform(.loadAroundSelectedSearchResult)
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(commandHandler?.canPerform(.loadAroundSelectedSearchResult) == false)

            Button("Clear Search Highlights") {
                commandHandler?.perform(.clearSearchHighlights)
            }
            .keyboardShortcut(.escape, modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.clearSearchHighlights) == false)
        }

        CommandMenu("Message") {
            Button("Paste Attachment") {
                commandHandler?.perform(.pasteAttachment)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(commandHandler?.canPerform(.pasteAttachment) == false)

            Divider()

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

            Button("Notification Settings…") {
                commandHandler?.perform(.openNotificationSettings)
            }
            .disabled(commandHandler?.canPerform(.openNotificationSettings) == false)

            Button("Appearance Settings…") {
                commandHandler?.perform(.openAppearanceSettings)
            }
            .disabled(commandHandler?.canPerform(.openAppearanceSettings) == false)
        }

        CommandMenu("Servers") {
            Button("Members") {
                commandHandler?.perform(.openMembers)
            }
            .disabled(commandHandler?.canPerform(.openMembers) == false)

            Button("Permission Editor") {
                commandHandler?.perform(.openPermissionEditor)
            }
            .disabled(commandHandler?.canPerform(.openPermissionEditor) == false)

            Button("Ban List") {
                commandHandler?.perform(.openBanList)
            }
            .disabled(commandHandler?.canPerform(.openBanList) == false)

            Divider()

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
