import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

enum MarkdownBlock: Hashable, Sendable {
    case text(String)
    /// The fence's info string is kept so the renderer can label the block. It is never used to
    /// select a syntax highlighter: tokenizing and coloring source per row is unbounded
    /// main-thread work on a lazy timeline, which is the Phase 51/64 hazard class.
    case code(language: String?, String)
    /// Consecutive `>` lines accumulate into one quote. They used to each become their own block,
    /// so a three-line quote rendered as three disconnected bars with paragraph gaps between them.
    case quote([String])
    case heading(Int, String)
    case listItem(depth: Int, marker: String, text: String)
    case rule

    /// Bounds the nested-indent cost per row.
    static let maximumListDepth = 4

    static func parse(_ source: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var textBuffer: [String] = []
        var quoteBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var isInCode = false

        func flushQuote() {
            if !quoteBuffer.isEmpty {
                result.append(.quote(quoteBuffer))
                quoteBuffer.removeAll()
            }
        }

        func flushText() {
            let text = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(.text(text)) }
            textBuffer.removeAll()
        }

        /// Every non-quote branch has to close an open quote, and every non-text branch has to
        /// close an open paragraph.
        func flushAll() {
            flushText()
            flushQuote()
        }

        for line in source.components(separatedBy: .newlines) {
            let trimmedForFence = line.trimmingCharacters(in: .whitespaces)
            if trimmedForFence.hasPrefix("```") {
                if isInCode {
                    result.append(.code(language: codeLanguage, codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    codeLanguage = nil
                    isInCode = false
                } else {
                    flushAll()
                    codeLanguage = fenceLanguage(from: trimmedForFence)
                    isInCode = true
                }
                continue
            }
            if isInCode {
                codeBuffer.append(line)
                continue
            }

            // Indentation is what distinguishes a nested list item, so it has to be measured
            // before the line is trimmed.
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if trimmed.hasPrefix(">") {
                // Only paragraphs interrupt a quote; consecutive quote lines accumulate.
                flushText()
                quoteBuffer.append(trimmed.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression))
                continue
            }

            if isRule(trimmed) {
                flushAll()
                result.append(.rule)
            } else if let heading = headingBlock(from: trimmed) {
                flushAll()
                result.append(heading)
            } else if let listItem = listItemBlock(from: trimmed, indent: indent) {
                flushAll()
                result.append(listItem)
            } else {
                flushQuote()
                textBuffer.append(line)
            }
        }
        if isInCode {
            result.append(.code(language: codeLanguage, codeBuffer.joined(separator: "\n")))
        }
        flushAll()
        return result.isEmpty ? [.text(source)] : result
    }

    /// Accepts a conservative identifier so an arbitrary info string cannot become visible UI.
    private static func fenceLanguage(from fenceLine: String) -> String? {
        let raw = String(fenceLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty,
              raw.count <= 20,
              raw.range(of: #"^[A-Za-z0-9+#._-]+$"#, options: .regularExpression) != nil
        else { return nil }
        return raw
    }

    private static func isRule(_ line: String) -> Bool {
        line.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil
    }

    private static func headingBlock(from line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let remainder = line.dropFirst(hashes.count)
        guard remainder.first?.isWhitespace == true else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(hashes.count, text)
    }

    private static func listItemBlock(from line: String, indent: Substring) -> MarkdownBlock? {
        let depth = listDepth(for: indent)
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return .listItem(depth: depth, marker: "-", text: String(line.dropFirst(2)))
        }
        guard let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else {
            return nil
        }
        let marker = String(line[match]).trimmingCharacters(in: .whitespaces)
        let text = String(line[match.upperBound...])
        return .listItem(depth: depth, marker: marker, text: text)
    }

    /// A tab is one level; spaces count in pairs, matching the two-space convention the official
    /// clients emit.
    private static func listDepth(for indent: Substring) -> Int {
        let tabs = indent.count { $0 == "\t" }
        let spaces = indent.count { $0 == " " }
        return min(maximumListDepth, tabs + spaces / 2)
    }

    var testDescription: String {
        switch self {
        case let .text(value):
            return "text::\(value)"
        case let .code(language, value):
            return "code:\(language ?? "-")::\(value)"
        case let .quote(lines):
            return "quote::\(lines.joined(separator: "\\n"))"
        case let .heading(level, value):
            return "heading\(level)::\(value)"
        case let .listItem(depth, marker, value):
            return "list\(depth):\(marker)::\(value)"
        case .rule:
            return "rule"
        }
    }
}
final class MarkdownBlockCache: @unchecked Sendable {
    static let shared = MarkdownBlockCache()
    private let lock = NSLock()
    private var blocksBySource: [String: [MarkdownBlock]] = [:]
    private var order: [String] = []
    private var byteCount = 0
    private(set) var parseCount = 0
    private(set) var cacheHitCount = 0
    private let maxEntries = 400
    private let maxBytes = 4 * 1024 * 1024

    func blocks(for source: String) -> [MarkdownBlock] {
        lock.lock()
        if let cached = blocksBySource[source] {
            cacheHitCount += 1
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = MarkdownBlock.parse(source)

        lock.lock()
        parseCount += 1
        blocksBySource[source] = parsed
        byteCount += source.utf8.count
        order.append(source)
        while (order.count > maxEntries || byteCount > maxBytes), let oldest = order.first {
            order.removeFirst()
            blocksBySource.removeValue(forKey: oldest)
            byteCount -= oldest.utf8.count
        }
        lock.unlock()
        return parsed
    }

    func diagnostics() -> MarkdownCacheDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return MarkdownCacheDiagnostics(cacheCount: blocksBySource.count, parseCount: parseCount, cacheHitCount: cacheHitCount)
    }
}
