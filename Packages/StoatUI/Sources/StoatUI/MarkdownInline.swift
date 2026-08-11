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
/// Scales a decoded custom-emoji bitmap so an interpolated `Text` glyph lands at body height.
///
/// `Text` renders interpolated images at their natural point size, which for a 44px bitmap is
/// 44pt — twice the intended 22pt. `Image(decorative:scale:)` divides by the scale, so the
/// scale we want is `pixelHeight / targetPointHeight`.
enum InlineEmojiGlyphMetrics {
    static let targetPointHeight: CGFloat = 22

    static func scale(pixelHeight: Int, targetPointHeight: CGFloat = targetPointHeight) -> CGFloat {
        guard pixelHeight > 0, targetPointHeight > 0 else { return 1 }
        return min(8, max(1, CGFloat(pixelHeight) / targetPointHeight))
    }
}

/// Encodes a mention as a URL so it can ride on an `AttributedString` `.link` run.
///
/// Inline mentions have to participate in real line breaking, which means they must be runs
/// inside the message's single `Text` rather than sibling views. `.link` is the only run
/// attribute SwiftUI hit-tests, and it coexists with `.textSelection(.enabled)`.
public enum MentionLinkRoute {
    public static let scheme = "liquidbagel-mention"
    private static let userHost = "user"

    public static func url(for item: MessageInlineReferenceItem) -> URL? {
        guard item.kind == .user, isValidID(item.rawID) else { return nil }
        return URL(string: "\(scheme)://\(userHost)/\(item.rawID)")
    }

    public static func parse(_ url: URL) -> UserID? {
        guard url.scheme == scheme, url.host == userHost else { return nil }
        let id = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard isValidID(id) else { return nil }
        return UserID(rawValue: id)
    }

    private static func isValidID(_ id: String) -> Bool {
        id.count == MentionTokenSyntax.length && id.allSatisfy { MentionTokenSyntax.alphabet.contains($0) }
    }
}

struct MarkdownInlineContent: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let source: String
    let customEmojiItems: [MessageInlineCustomEmojiItem]
    let referenceItems: [String: MessageInlineReferenceItem]
    let font: Font
    let onOpenMention: (UserID) -> Void
    private let tokens: [MarkdownInlineToken]

    #if canImport(AppKit)
    /// Seeded synchronously from the bounded front cache so an already-decoded emoji paints on
    /// first render; misses are filled off the main thread by the task below. Deliberately kept
    /// out of `PreparedMarkdownContent`, which is `Hashable` and backs the timeline row's
    /// `.equatable()` fast path -- putting image data there would destabilize row equality.
    @State private var emojiImages: [DecodedImageKey: CGImage] = [:]
    #endif

    /// Ceiling on per-row inline work. Pathological content falls back to plain text instead of
    /// composing thousands of runs on the main thread.
    private static let maximumTokens = 200

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

        #if canImport(AppKit)
        var seeded: [DecodedImageKey: CGImage] = [:]
        for key in Self.emojiKeys(in: self.tokens) {
            if let image = DecodedImageFrontCache.shared.image(for: key) {
                seeded[key] = image
            }
        }
        _emojiImages = State(initialValue: seeded)
        #endif
    }

    var body: some View {
        composedText
            .font(font)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(accessibleDescription)
            .environment(\.openURL, OpenURLAction { url in
                guard let userID = MentionLinkRoute.parse(url) else { return .systemAction }
                onOpenMention(userID)
                return .handled
            })
            .task(id: source) {
                #if canImport(AppKit)
                await loadMissingEmojiImages()
                #endif
            }
    }

    /// One `Text` for the whole paragraph. Mentions and emoji are runs and glyphs inside it, so
    /// SwiftUI line-breaks them exactly like words -- this is what fixes the old `HStack` path,
    /// which could not wrap at all and truncated any paragraph containing a mention or emoji.
    private var composedText: Text {
        guard tokens.count <= Self.maximumTokens else { return Text(source) }
        return tokens.reduce(Text("")) { partial, token in
            switch token {
            case let .text(value):
                return partial + Text(Self.attributed(value))
            case let .emoji(item):
                return partial + emojiText(item)
            case let .reference(item):
                return partial + Text(mentionAttributedString(item))
            }
        }
    }

    private func emojiText(_ item: MessageInlineCustomEmojiItem) -> Text {
        #if canImport(AppKit)
        if let data = item.imageData {
            let key = DecodedImageKey(data: data, pixelSize: Self.emojiPixelSize)
            if let image = emojiImages[key] {
                let scale = InlineEmojiGlyphMetrics.scale(pixelHeight: image.height)
                return Text(Image(decorative: image, scale: scale))
            }
        }
        #endif
        return Text(item.shortcode)
    }

    private func mentionAttributedString(_ item: MessageInlineReferenceItem) -> AttributedString {
        var string = AttributedString(Self.mentionRunText(for: item))
        string.font = font.weight(.medium)
        string.foregroundColor = referenceForeground(item)
        string.backgroundColor = referenceBackground(item)
        if let url = MentionLinkRoute.url(for: item) {
            string.link = url
        }
        return string
    }

    /// Non-breaking spaces give the tinted run breathing room without introducing break
    /// opportunities, and the display name's own spaces are joined the same way so a mention
    /// moves to the next line whole rather than splitting across two tinted fragments.
    nonisolated static func mentionRunText(for item: MessageInlineReferenceItem) -> String {
        let name = item.displayName.replacingOccurrences(of: " ", with: "\u{00A0}")
        return "\u{00A0}\(sigil(for: item.kind))\(name)\u{00A0}"
    }

    nonisolated static func sigil(for kind: MessageInlineReferenceKind) -> String {
        kind == .channel ? "#" : "@"
    }

    private func sigil(for kind: MessageInlineReferenceKind) -> String {
        Self.sigil(for: kind)
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
        Self.accessibleDescription(for: tokens)
    }

    /// A single `Text` is one accessibility element, so the per-pill VoiceOver labels the old
    /// view-per-token path provided are not expressible. Mentions expand to their spoken form
    /// inline instead, so every mention is still announced with its kind.
    nonisolated static func accessibleDescription(for tokens: [MarkdownInlineToken]) -> String {
        tokens.map { token -> String in
            switch token {
            case let .text(value):
                return value
            case let .emoji(item):
                return item.name
            case let .reference(item):
                switch item.kind {
                case .user:
                    return item.isCurrentUser ? "mentions you" : "mention, \(item.displayName)"
                case .channel:
                    return "channel mention, \(item.displayName)"
                case .role:
                    return "role mention, \(item.displayName)"
                }
            }
        }.joined()
    }

    private static func attributed(_ value: String) -> AttributedString {
        MarkdownInlineCache.shared.attributed(value)
    }
}

extension MarkdownInlineContent {
    static let emojiPixelSize = 44

    static func emojiKeys(in tokens: [MarkdownInlineToken]) -> [DecodedImageKey] {
        tokens.compactMap { token in
            guard case let .emoji(item) = token, let data = item.imageData else { return nil }
            return DecodedImageKey(data: data, pixelSize: emojiPixelSize)
        }
    }

    #if canImport(AppKit)
    private func loadMissingEmojiImages() async {
        for token in tokens {
            guard case let .emoji(item) = token, let data = item.imageData else { continue }
            let key = DecodedImageKey(data: data, pixelSize: Self.emojiPixelSize)
            guard emojiImages[key] == nil else { continue }
            if let image = await DecodedImageStore.shared.image(for: key, data: data) {
                emojiImages[key] = image
            }
        }
    }
    #endif
}
