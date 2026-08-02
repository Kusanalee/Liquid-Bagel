import StoatUI
import SwiftUI

/// Phase 71's verified macOS navigation shortcuts, kept in the package so the mapping can be
/// exercised by `swift test` even though the app command menu itself lives in the app target.
public struct Phase71CommandShortcut: Sendable {
    public var key: KeyEquivalent
    public var modifiers: EventModifiers

    public init(key: KeyEquivalent, modifiers: EventModifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum Phase71Keybinds {
    public static let verifiedMacShortcuts: [AppCommand: Phase71CommandShortcut] = [
        .selectPreviousServer: Phase71CommandShortcut(key: .upArrow, modifiers: [.command, .control]),
        .selectNextServer: Phase71CommandShortcut(key: .downArrow, modifiers: [.command, .control]),
        .selectPreviousChannel: Phase71CommandShortcut(key: .upArrow, modifiers: [.command]),
        .selectNextChannel: Phase71CommandShortcut(key: .downArrow, modifiers: [.command])
    ]
}

public enum Phase71ComposerToken {
    public static func insertionText(for candidate: ComposerAutocompleteCandidate) -> String {
        switch candidate.kind {
        case .user:
            return "<@\(candidate.rawID)> "
        case .channel:
            return "<#\(candidate.rawID)> "
        case .role:
            return "<%\(candidate.rawID)> "
        case .emoji:
            return ":\(candidate.rawID):"
        }
    }
}
