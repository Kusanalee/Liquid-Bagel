import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

public struct PreparedMarkdownContent: Hashable, Sendable {
    public var source: String
    var blocks: [MarkdownBlock]

    init(source: String, blocks: [MarkdownBlock]) {
        self.source = source
        self.blocks = blocks
    }
}
public struct MarkdownCacheDiagnostics: Hashable, Sendable {
    public var cacheCount: Int
    public var parseCount: Int
    public var cacheHitCount: Int
}
public enum MarkdownContentPreparer {
    nonisolated public static func prepare(
        _ source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        referenceItems: [String: MessageInlineReferenceItem] = [:]
    ) -> PreparedMarkdownContent {
        let blocks = MarkdownBlockCache.shared.blocks(for: source)
        for block in blocks {
            let inlineSource: String?
            switch block {
            case let .text(value), let .quote(value), let .heading(_, value), let .listItem(_, value):
                inlineSource = value
            case .code:
                inlineSource = nil
            }
            guard let inlineSource else { continue }
            let tokens = MarkdownInlineCache.shared.tokens(source: inlineSource, emojiItems: customEmojiItems, referenceItems: referenceItems)
            for token in tokens {
                if case let .text(value) = token {
                    _ = MarkdownInlineCache.shared.attributed(value)
                }
            }
        }
        return PreparedMarkdownContent(source: source, blocks: blocks)
    }
}
public struct MarkdownMessageContent: View {
    private let source: String
    private let preparedContent: PreparedMarkdownContent?
    private let customEmojiItems: [MessageInlineCustomEmojiItem]
    private let referenceItems: [String: MessageInlineReferenceItem]
    private let onOpenMention: (UserID) -> Void
    @State private var asynchronouslyPreparedContent: PreparedMarkdownContent?

    public init(
        _ source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        referenceItems: [String: MessageInlineReferenceItem] = [:],
        onOpenMention: @escaping (UserID) -> Void = { _ in }
    ) {
        self.source = source
        self.preparedContent = nil
        self.customEmojiItems = customEmojiItems
        self.referenceItems = referenceItems
        self.onOpenMention = onOpenMention
        _asynchronouslyPreparedContent = State(initialValue: nil)
    }

    public init(
        prepared: PreparedMarkdownContent,
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        referenceItems: [String: MessageInlineReferenceItem] = [:],
        onOpenMention: @escaping (UserID) -> Void = { _ in }
    ) {
        self.source = prepared.source
        self.preparedContent = prepared
        self.customEmojiItems = customEmojiItems
        self.referenceItems = referenceItems
        self.onOpenMention = onOpenMention
        _asynchronouslyPreparedContent = State(initialValue: nil)
    }

    public var body: some View {
        Group {
            if let content = preparedContent ?? asynchronouslyPreparedContent {
                blocks(content.blocks)
            } else {
                Text(source)
                    .font(StoatTypography.messageBody)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: source) {
            guard preparedContent == nil else { return }
            let source = source
            let customEmojiItems = customEmojiItems
            let referenceItems = referenceItems
            asynchronouslyPreparedContent = await Task.detached(priority: .userInitiated) {
                MarkdownContentPreparer.prepare(source, customEmojiItems: customEmojiItems, referenceItems: referenceItems)
            }.value
        }
    }

    @ViewBuilder private func blocks(_ parsedBlocks: [MarkdownBlock]) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            ForEach(parsedBlocks.indices, id: \.self) { index in
                switch parsedBlocks[index] {
                case let .code(code):
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(StoatSpacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                        .textSelection(.enabled)
                case let .quote(quote):
                    MarkdownInlineContent(source: quote, customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: StoatTypography.messageBody, onOpenMention: onOpenMention)
                        .padding(.leading, StoatSpacing.small)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2)
                        }
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                case let .heading(level, text):
                    MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: level <= 1 ? .title3.weight(.semibold) : .headline, onOpenMention: onOpenMention)
                        .textSelection(.enabled)
                case let .listItem(marker, text):
                    HStack(alignment: .firstTextBaseline, spacing: StoatSpacing.small) {
                        Text(marker)
                            .font(StoatTypography.messageBody)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: StoatTypography.messageBody, onOpenMention: onOpenMention)
                            .textSelection(.enabled)
                    }
                case let .text(text):
                    MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: StoatTypography.messageBody, onOpenMention: onOpenMention)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
extension MarkdownMessageContent {
    public static func cacheDiagnostics() -> MarkdownCacheDiagnostics {
        MarkdownBlockCache.shared.diagnostics()
    }

    nonisolated static func _testBlockDescriptions(for source: String) -> [String] {
        MarkdownBlock.parse(source).map(\.testDescription)
    }

    nonisolated static func _testInlineTokenDescriptions(
        for source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem],
        referenceItems: [String: MessageInlineReferenceItem] = [:]
    ) -> [String] {
        MarkdownInlineToken.tokenize(source: source, emojiItems: customEmojiItems, referenceItems: referenceItems).map(\.testDescription)
    }

    nonisolated static func _testInlineRenderingStrategy(
        for source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        referenceItems: [String: MessageInlineReferenceItem] = [:]
    ) -> String {
        let tokens = MarkdownInlineToken.tokenize(source: source, emojiItems: customEmojiItems, referenceItems: referenceItems)
        return tokens.allSatisfy {
            if case .text = $0 { return true }
            return false
        } ? MarkdownInlineRenderingStrategy.wrappingText.rawValue : MarkdownInlineRenderingStrategy.tokenRow.rawValue
    }
}
struct InlineCustomEmojiMessageContent: View {
    let source: String
    let customEmojiItems: [MessageInlineCustomEmojiItem]

    var body: some View {
        MarkdownMessageContent(source, customEmojiItems: customEmojiItems)
    }
}
