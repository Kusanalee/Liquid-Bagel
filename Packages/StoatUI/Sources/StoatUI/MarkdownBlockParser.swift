import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

enum MarkdownBlock: Hashable, Sendable {
    case text(String)
    case code(String)
    case quote(String)
    case heading(Int, String)
    case listItem(String, String)

    static func parse(_ source: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var isInCode = false

        func flushText() {
            let text = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(.text(text)) }
            textBuffer.removeAll()
        }

        for line in source.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if isInCode {
                    result.append(.code(codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    isInCode = false
                } else {
                    flushText()
                    isInCode = true
                }
                continue
            }
            if isInCode {
                codeBuffer.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushText()
                continue
            }

            if let heading = headingBlock(from: trimmed) {
                flushText()
                result.append(heading)
            } else if trimmed.hasPrefix(">") {
                flushText()
                let quote = trimmed.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
                result.append(.quote(quote))
            } else if let listItem = listItemBlock(from: trimmed) {
                flushText()
                result.append(listItem)
            } else {
                textBuffer.append(line)
            }
        }
        if isInCode {
            result.append(.code(codeBuffer.joined(separator: "\n")))
        }
        flushText()
        return result.isEmpty ? [.text(source)] : result
    }

    private static func headingBlock(from line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let remainder = line.dropFirst(hashes.count)
        guard remainder.first?.isWhitespace == true else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(hashes.count, text)
    }

    private static func listItemBlock(from line: String) -> MarkdownBlock? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return .listItem("-", String(line.dropFirst(2)))
        }
        guard let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else {
            return nil
        }
        let marker = String(line[match]).trimmingCharacters(in: .whitespaces)
        let text = String(line[match.upperBound...])
        return .listItem(marker, text)
    }

    var testDescription: String {
        switch self {
        case let .text(value):
            return "text::\(value)"
        case let .code(value):
            return "code::\(value)"
        case let .quote(value):
            return "quote::\(value)"
        case let .heading(level, value):
            return "heading\(level)::\(value)"
        case let .listItem(marker, value):
            return "list\(marker)::\(value)"
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
