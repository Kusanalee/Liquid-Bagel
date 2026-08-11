import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// The single definition of the backend's `<@ULID>` / `<#ULID>` / `<%ULID>` reference syntax.
///
/// Both the extraction-only `MarkdownReferenceScanner` and the rendering tokenizer
/// `MarkdownInlineToken.tokenize` scan for the same shape. They used to carry byte-identical
/// copies of the alphabet, the length, and the scan loop, so every syntax change had to be made
/// twice. Keep the one copy here.
enum MentionTokenSyntax {
    /// Crockford base32, matching the backend's ULID alphabet (no I, L, O, or U).
    static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let length = 26

    struct Match {
        var kind: MessageInlineReferenceKind
        var rawID: String
        /// The index just past the closing `>`.
        var tokenEnd: String.Index
    }

    /// Matches a complete reference token starting at `index`, which must point at `<`.
    /// Returns nil when the shape does not match exactly; the caller then advances one character.
    static func match(in source: String, at index: String.Index) -> Match? {
        let end = source.endIndex
        guard index < end, source[index] == "<" else { return nil }
        let sigilIndex = source.index(after: index)
        guard sigilIndex < end, "@#%".contains(source[sigilIndex]) else { return nil }

        let idStart = source.index(after: sigilIndex)
        var idEnd = idStart
        while idEnd < end, alphabet.contains(source[idEnd]) {
            idEnd = source.index(after: idEnd)
        }
        guard source.distance(from: idStart, to: idEnd) == length,
              idEnd < end,
              source[idEnd] == ">"
        else { return nil }

        let sigil = source[sigilIndex]
        return Match(
            kind: sigil == "@" ? .user : (sigil == "#" ? .channel : .role),
            rawID: String(source[idStart..<idEnd]),
            tokenEnd: source.index(after: idEnd)
        )
    }
}

/// Extraction-only counterpart to the inline tokenizer, used by StoatFeatures to find
/// which users/channels/roles a message content string references before identity resolution
/// (which needs snapshot/server data StoatUI does not have access to).
public enum MarkdownReferenceScanner {
    public struct Match: Hashable, Sendable {
        public var token: String
        public var kind: MessageInlineReferenceKind
        public var rawID: String

        public init(token: String, kind: MessageInlineReferenceKind, rawID: String) {
            self.token = token
            self.kind = kind
            self.rawID = rawID
        }
    }

    public static func scan(_ source: String) -> [Match] {
        var result: [Match] = []
        var cursor = source.startIndex
        let end = source.endIndex
        while cursor < end {
            if let match = MentionTokenSyntax.match(in: source, at: cursor) {
                result.append(Match(
                    token: String(source[cursor..<match.tokenEnd]),
                    kind: match.kind,
                    rawID: match.rawID
                ))
                cursor = match.tokenEnd
                continue
            }
            cursor = source.index(after: cursor)
        }
        return result
    }
}

enum MarkdownInlineToken: Hashable {
    case text(String)
    case emoji(MessageInlineCustomEmojiItem)
    case reference(MessageInlineReferenceItem)

    static func tokenize(
        source: String,
        emojiItems: [MessageInlineCustomEmojiItem],
        referenceItems: [String: MessageInlineReferenceItem]
    ) -> [MarkdownInlineToken] {
        let byShortcode = Dictionary(uniqueKeysWithValues: emojiItems.map { ($0.shortcode, $0) })
        var result: [MarkdownInlineToken] = []
        var textStart = source.startIndex
        var cursor = source.startIndex
        let end = source.endIndex

        func flushText(upTo index: String.Index) {
            if textStart < index {
                result.append(.text(String(source[textStart..<index])))
            }
        }

        while cursor < end {
            let character = source[cursor]
            if character == ":" {
                let afterColon = source.index(after: cursor)
                if afterColon < end, let closeIndex = source[afterColon...].firstIndex(of: ":") {
                    let tokenEnd = source.index(after: closeIndex)
                    let shortcode = String(source[cursor..<tokenEnd])
                    flushText(upTo: cursor)
                    if let item = byShortcode[shortcode] {
                        result.append(.emoji(item))
                    } else {
                        result.append(.text(shortcode))
                    }
                    cursor = tokenEnd
                    textStart = cursor
                    continue
                }
            } else if character == "<" {
                if let match = MentionTokenSyntax.match(in: source, at: cursor) {
                    let tokenEnd = match.tokenEnd
                    let tokenText = String(source[cursor..<tokenEnd])
                    flushText(upTo: cursor)
                    if let item = referenceItems[tokenText] {
                        result.append(.reference(item))
                    } else {
                        result.append(.reference(MessageInlineReferenceItem(
                            kind: match.kind,
                            rawID: match.rawID,
                            displayName: MessageInlineReferenceItem.fallbackDisplayName(for: match.kind),
                            isFallback: true
                        )))
                    }
                    cursor = tokenEnd
                    textStart = cursor
                    continue
                }
            }
            cursor = source.index(after: cursor)
        }
        flushText(upTo: end)
        return result.isEmpty ? [.text(source)] : result
    }

    var testDescription: String {
        switch self {
        case let .text(value):
            return "text::\(value)"
        case let .emoji(item):
            return "emoji::\(item.shortcode)"
        case let .reference(item):
            return "reference:\(item.kind)::\(item.rawID)"
        }
    }
}
final class MarkdownInlineCache: @unchecked Sendable {
    static let shared = MarkdownInlineCache()

    private struct TokenKey: Hashable {
        var source: String
        var emojiItems: [MessageInlineCustomEmojiItem]
        var referenceItems: [String: MessageInlineReferenceItem]
    }

    private let lock = NSLock()
    private var tokensByKey: [TokenKey: [MarkdownInlineToken]] = [:]
    private var attributedBySource: [String: AttributedString] = [:]
    private var tokenOrder: [TokenKey] = []
    private var attributedOrder: [String] = []
    private var tokenByteCount = 0
    private var attributedByteCount = 0
    private let maxEntries = 800
    private let maxBytes = 4 * 1024 * 1024

    func tokens(source: String, emojiItems: [MessageInlineCustomEmojiItem], referenceItems: [String: MessageInlineReferenceItem]) -> [MarkdownInlineToken] {
        let key = TokenKey(source: source, emojiItems: emojiItems, referenceItems: referenceItems)
        lock.lock()
        if let cached = tokensByKey[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let parsed = MarkdownInlineToken.tokenize(source: source, emojiItems: emojiItems, referenceItems: referenceItems)
        lock.lock()
        tokensByKey[key] = parsed
        tokenByteCount += Self.byteCount(for: key)
        tokenOrder.append(key)
        trimTokens()
        lock.unlock()
        return parsed
    }

    func attributed(_ source: String) -> AttributedString {
        lock.lock()
        if let cached = attributedBySource[source] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let sanitized = source.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let parsed = (try? AttributedString(
            markdown: sanitized,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(sanitized)
        lock.lock()
        attributedBySource[source] = parsed
        attributedByteCount += source.utf8.count
        attributedOrder.append(source)
        while (attributedOrder.count > maxEntries || attributedByteCount > maxBytes), let oldest = attributedOrder.first {
            attributedOrder.removeFirst()
            attributedBySource.removeValue(forKey: oldest)
            attributedByteCount -= oldest.utf8.count
        }
        lock.unlock()
        return parsed
    }

    private static func byteCount(for key: TokenKey) -> Int {
        key.source.utf8.count
            + key.emojiItems.reduce(0) { $0 + $1.shortcode.utf8.count }
            + key.referenceItems.reduce(0) { $0 + $1.key.utf8.count + $1.value.displayName.utf8.count }
    }

    private func trimTokens() {
        while (tokenOrder.count > maxEntries || tokenByteCount > maxBytes), let oldest = tokenOrder.first {
            tokenOrder.removeFirst()
            tokensByKey.removeValue(forKey: oldest)
            tokenByteCount -= Self.byteCount(for: oldest)
        }
    }
}
enum MarkdownInlineRenderingStrategy: String, Equatable {
    case wrappingText
    case tokenRow
}
struct MarkdownInlineContent: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let source: String
    let customEmojiItems: [MessageInlineCustomEmojiItem]
    let referenceItems: [String: MessageInlineReferenceItem]
    let font: Font
    let onOpenMention: (UserID) -> Void
    private let tokens: [MarkdownInlineToken]

    init(
        source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem],
        referenceItems: [String: MessageInlineReferenceItem] = [:],
        font: Font,
        onOpenMention: @escaping (UserID) -> Void = { _ in }
    ) {
        self.source = source
        self.customEmojiItems = customEmojiItems
        self.referenceItems = referenceItems
        self.font = font
        self.onOpenMention = onOpenMention
        self.tokens = MarkdownInlineCache.shared.tokens(source: source, emojiItems: customEmojiItems, referenceItems: referenceItems)
    }

    @ViewBuilder var body: some View {
        switch renderingStrategy {
        case .wrappingText:
            Text(wrappingAttributedText)
                .font(font)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(accessibleDescription)
        case .tokenRow:
            HStack(alignment: .center, spacing: StoatSpacing.xxSmall) {
                ForEach(tokens.indices, id: \.self) { index in
                    switch tokens[index] {
                    case let .text(value):
                        Text(Self.attributed(value))
                            .font(font)
                            .textSelection(.enabled)
                    case let .emoji(item):
                        inlineEmoji(item)
                    case let .reference(item):
                        inlineReference(item)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(accessibleDescription)
        }
    }

    private var renderingStrategy: MarkdownInlineRenderingStrategy {
        tokens.allSatisfy {
            if case .text = $0 { return true }
            return false
        } ? .wrappingText : .tokenRow
    }

    private var wrappingAttributedText: AttributedString {
        tokens.reduce(into: AttributedString()) { result, token in
            if case let .text(value) = token {
                result.append(Self.attributed(value))
            }
        }
    }

    @ViewBuilder private func inlineEmoji(_ item: MessageInlineCustomEmojiItem) -> some View {
        #if canImport(AppKit)
        if let data = item.imageData {
            DecodedDataImage(data: data, pixelSize: 44)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .accessibilityLabel(item.name)
        } else {
            Text(item.shortcode)
                .font(StoatTypography.messageBody)
        }
        #else
        Text(item.shortcode)
            .font(StoatTypography.messageBody)
        #endif
    }

    @ViewBuilder private func inlineReference(_ item: MessageInlineReferenceItem) -> some View {
        switch item.kind {
        case .user:
            Button {
                onOpenMention(UserID(rawValue: item.rawID))
            } label: {
                referencePillLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCurrentUser ? "mentions you" : "mention, \(item.displayName)")
        case .channel:
            referencePillLabel(item)
                .accessibilityLabel("channel mention, \(item.displayName)")
        case .role:
            referencePillLabel(item)
                .accessibilityLabel("role mention, \(item.displayName)")
        }
    }

    private func referencePillLabel(_ item: MessageInlineReferenceItem) -> some View {
        HStack(spacing: 2) {
            Text(sigil(for: item.kind))
            Text(item.displayName)
        }
        .font(font.weight(.medium))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(referenceBackground(item), in: Capsule())
        .foregroundStyle(referenceForeground(item))
    }

    private func sigil(for kind: MessageInlineReferenceKind) -> String {
        kind == .channel ? "#" : "@"
    }

    private func referenceForeground(_ item: MessageInlineReferenceItem) -> Color {
        // Matches the MessageRow author-name convention: Increase Contrast overrides sanitized
        // role colors with the system accent rather than risking a low-contrast custom hue.
        if colorSchemeContrast != .increased, let roleColor = item.roleColor {
            return Color(red: roleColor.red, green: roleColor.green, blue: roleColor.blue)
        }
        return .accentColor
    }

    private func referenceBackground(_ item: MessageInlineReferenceItem) -> Color {
        item.isCurrentUser ? Color.accentColor.opacity(0.28) : Color.accentColor.opacity(0.14)
    }

    private var accessibleDescription: String {
        tokens.map { token -> String in
            switch token {
            case let .text(value):
                return value
            case let .emoji(item):
                return item.name
            case let .reference(item):
                return "\(sigil(for: item.kind))\(item.displayName)"
            }
        }.joined()
    }

    private static func attributed(_ value: String) -> AttributedString {
        MarkdownInlineCache.shared.attributed(value)
    }
}
