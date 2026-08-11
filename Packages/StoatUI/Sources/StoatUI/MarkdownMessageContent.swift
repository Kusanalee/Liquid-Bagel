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
            case let .text(value), let .heading(_, value):
                inlineSource = value
            case let .listItem(_, _, value):
                inlineSource = value
            case let .quote(lines):
                inlineSource = lines.joined(separator: "\n")
            case .code, .rule:
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
        // Spacing is per-pair rather than uniform, so consecutive list items sit tight while
        // headings still get room to breathe.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parsedBlocks.indices, id: \.self) { index in
                block(parsedBlocks[index])
                    .padding(.top, MarkdownBlockSpacing.spacing(
                        above: parsedBlocks[index],
                        below: index > 0 ? parsedBlocks[index - 1] : nil
                    ))
            }
        }
    }

    @ViewBuilder private func block(_ parsedBlock: MarkdownBlock) -> some View {
        switch parsedBlock {
        case let .code(language, code):
            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                if let language {
                    Text(language)
                        .font(StoatTypography.metadata)
                        .foregroundStyle(.tertiary)
                }
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(StoatSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
        case let .quote(lines):
            MarkdownInlineContent(source: lines.joined(separator: "\n"), customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: StoatTypography.messageBody, onOpenMention: onOpenMention)
                // Inset past the bar so text no longer sits underneath it, and use a capsule so
                // the ends are rounded rather than clipped square.
                .padding(.leading, StoatSpacing.small + MarkdownQuoteMetrics.barWidth)
                .background(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.5)).frame(width: MarkdownQuoteMetrics.barWidth)
                }
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case let .heading(level, text):
            MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: MarkdownHeadingStyle.font(for: level), onOpenMention: onOpenMention)
                .textSelection(.enabled)
        case let .listItem(depth, marker, text):
            HStack(alignment: .firstTextBaseline, spacing: StoatSpacing.small) {
                Text(MarkdownListStyle.glyph(marker: marker, depth: depth))
                    .font(StoatTypography.messageBody)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: StoatTypography.messageBody, onOpenMention: onOpenMention)
                    .textSelection(.enabled)
            }
            .padding(.leading, MarkdownListStyle.indent(depth: depth))
        case .rule:
            Divider().padding(.vertical, StoatSpacing.xSmall)
        case let .text(text):
            MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, referenceItems: referenceItems, font: StoatTypography.messageBody, onOpenMention: onOpenMention)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum MarkdownQuoteMetrics {
    static let barWidth: CGFloat = 3
}

/// Six distinct, monotonically shrinking heading sizes. The renderer previously collapsed all six
/// markdown levels onto two fonts, so `##` through `######` were indistinguishable.
public enum MarkdownHeadingStyle {
    public static func font(for level: Int) -> Font {
        switch max(1, min(6, level)) {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        case 4: return .subheadline.weight(.semibold)
        case 5: return .callout.weight(.semibold)
        default: return .footnote.weight(.semibold)
        }
    }
}

public enum MarkdownListStyle {
    private static let unorderedGlyphs = ["\u{2022}", "\u{25E6}", "\u{25AA}", "\u{2013}"]

    /// Ordered markers keep the author's numbering; unordered markers cycle by depth.
    public static func glyph(marker: String, depth: Int) -> String {
        guard marker == "-" else { return marker }
        return unorderedGlyphs[max(0, depth) % unorderedGlyphs.count]
    }

    public static func indent(depth: Int) -> CGFloat {
        CGFloat(max(0, min(MarkdownBlock.maximumListDepth, depth))) * StoatSpacing.large
    }
}

/// Vertical rhythm between adjacent blocks. A single uniform gap made list items look as loose as
/// separate paragraphs.
public enum MarkdownBlockSpacing {
    static func spacing(above block: MarkdownBlock, below previous: MarkdownBlock?) -> CGFloat {
        guard let previous else { return 0 }
        if case .listItem = block, case .listItem = previous { return StoatSpacing.xxSmall }
        if case .heading = block { return StoatSpacing.small }
        if case .heading = previous { return StoatSpacing.xSmall }
        return StoatSpacing.xSmall
    }

    /// Test seam: reports the gap between two blocks by their `testDescription` shape.
    public static func _testSpacing(above: String, below: String?) -> CGFloat {
        func block(_ description: String) -> MarkdownBlock {
            if description.hasPrefix("heading") { return .heading(1, "h") }
            if description.hasPrefix("list") { return .listItem(depth: 0, marker: "-", text: "i") }
            if description.hasPrefix("code") { return .code(language: nil, "c") }
            if description.hasPrefix("quote") { return .quote(["q"]) }
            if description.hasPrefix("rule") { return .rule }
            return .text("t")
        }
        return spacing(above: block(above), below: below.map(block))
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

    /// Describes the segments that compose into the paragraph's single `Text`.
    ///
    /// Replaces the old `_testInlineRenderingStrategy` seam. There is no longer a strategy to
    /// report: every source composes one `Text`, and mentions and emoji are runs inside it rather
    /// than sibling views in a non-wrapping `HStack`.
    nonisolated static func _testInlineSegmentDescriptions(
        for source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        referenceItems: [String: MessageInlineReferenceItem] = [:]
    ) -> [String] {
        MarkdownInlineToken.tokenize(source: source, emojiItems: customEmojiItems, referenceItems: referenceItems)
            .map(\.testDescription)
    }

    /// The literal text of a mention run, including its non-breaking padding and name joining.
    nonisolated static func _testMentionRunText(for item: MessageInlineReferenceItem) -> String {
        MarkdownInlineContent.mentionRunText(for: item)
    }

    /// The rendered characters of an inline text run, after HTML sanitizing and markdown parsing.
    nonisolated static func _testAttributedPlainText(for source: String) -> String {
        String(MarkdownInlineCache.shared.attributed(source).characters)
    }

    /// Whether a mention of this kind carries a tappable `.link` run attribute.
    nonisolated static func _testMentionHasLink(for item: MessageInlineReferenceItem) -> Bool {
        MentionLinkRoute.url(for: item) != nil
    }

    nonisolated static func _testAccessibleDescription(
        for source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        referenceItems: [String: MessageInlineReferenceItem] = [:]
    ) -> String {
        MarkdownInlineContent.accessibleDescription(
            for: MarkdownInlineToken.tokenize(source: source, emojiItems: customEmojiItems, referenceItems: referenceItems)
        )
    }
}
struct InlineCustomEmojiMessageContent: View {
    let source: String
    let customEmojiItems: [MessageInlineCustomEmojiItem]

    var body: some View {
        MarkdownMessageContent(source, customEmojiItems: customEmojiItems)
    }
}
