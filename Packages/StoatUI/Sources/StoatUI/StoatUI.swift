import CryptoKit
import Foundation
import OSLog
import StoatDesignSystem
import StoatModels
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
import ImageIO
import QuartzCore
#endif

#if canImport(AVKit)
import AVFoundation
import AVKit
#endif

private enum StoatUILayoutDiagnostics {
    private static let logger = Logger(subsystem: "LiquidBagel", category: "Layout")

    static func body(_ name: StaticString, detail: String = "") {
        #if DEBUG
        if detail.isEmpty {
            logger.debug("\(name) body")
        } else {
            logger.debug("\(name) body: \(detail)")
        }
        #endif
    }
}

public struct DecodedImageKey: Hashable, Sendable {
    public var id: String
    public var pixelSize: Int
    public var revision: Int

    public init(id: String, pixelSize: Int, revision: Int = 0) {
        self.id = id
        self.pixelSize = max(1, pixelSize)
        self.revision = revision
    }

    public init(data: Data, pixelSize: Int, revision: Int = 0) {
        let prefix = data.prefix(8).reduce(into: UInt64(0)) { value, byte in
            value = (value << 8) | UInt64(byte)
        }
        let suffix = data.suffix(8).reduce(into: UInt64(0)) { value, byte in
            value = (value << 8) | UInt64(byte)
        }
        self.init(id: "\(data.count)-\(prefix)-\(suffix)", pixelSize: pixelSize, revision: revision)
    }
}

public struct DecodedImageDiagnostics: Hashable, Sendable {
    public var cacheCount: Int
    public var decodeCount: Int
    public var cacheHitCount: Int
    public var dedupeCount: Int
    public var byteCount: Int
    public var evictionCount: Int

    public init(cacheCount: Int, decodeCount: Int, cacheHitCount: Int, dedupeCount: Int, byteCount: Int = 0, evictionCount: Int = 0) {
        self.cacheCount = cacheCount
        self.decodeCount = decodeCount
        self.cacheHitCount = cacheHitCount
        self.dedupeCount = dedupeCount
        self.byteCount = byteCount
        self.evictionCount = evictionCount
    }
}

#if canImport(AppKit)
@MainActor
final class DecodedImageFrontCache {
    static let shared = DecodedImageFrontCache()

    private var images: [DecodedImageKey: CGImage] = [:]
    private var costs: [DecodedImageKey: Int] = [:]
    private var order: [DecodedImageKey] = []
    private var byteCount = 0
    private let maxEntries = 96
    private let maxBytes = 128 * 1024 * 1024

    func image(for key: DecodedImageKey) -> CGImage? {
        guard let image = images[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return image
    }

    func store(_ image: CGImage, for key: DecodedImageKey) {
        byteCount -= costs[key] ?? 0
        let cost = image.bytesPerRow * image.height
        images[key] = image
        costs[key] = cost
        byteCount += cost
        order.removeAll { $0 == key }
        order.append(key)
        while (order.count > maxEntries || byteCount > maxBytes), let oldest = order.first {
            order.removeFirst()
            images.removeValue(forKey: oldest)
            byteCount -= costs.removeValue(forKey: oldest) ?? 0
        }
    }

    func contains(_ key: DecodedImageKey) -> Bool {
        images[key] != nil
    }

    func reset() {
        images.removeAll()
        costs.removeAll()
        order.removeAll()
        byteCount = 0
    }
}

actor DecodedImageStore {
    static let shared = DecodedImageStore()

    private var images: [DecodedImageKey: CGImage] = [:]
    private var costs: [DecodedImageKey: Int] = [:]
    private var order: [DecodedImageKey] = []
    private var inFlight: [DecodedImageKey: Task<CGImage?, Never>] = [:]
    private var decodeCount = 0
    private var cacheHitCount = 0
    private var dedupeCount = 0
    private var byteCount = 0
    private var evictionCount = 0
    private let maxEntries = 96
    private let maxBytes = 128 * 1024 * 1024

    func image(for key: DecodedImageKey, data: Data) async -> CGImage? {
        if let image = images[key] {
            cacheHitCount += 1
            await DecodedImageFrontCache.shared.store(image, for: key)
            return image
        }
        if let task = inFlight[key] {
            dedupeCount += 1
            return await task.value
        }
        let task = Task.detached(priority: .userInitiated) {
            Self.downsample(data: data, pixelSize: key.pixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        decodeCount += 1
        if let image {
            let cost = image.bytesPerRow * image.height
            images[key] = image
            costs[key] = cost
            byteCount += cost
            order.removeAll { $0 == key }
            order.append(key)
            while (order.count > maxEntries || byteCount > maxBytes), let oldest = order.first {
                order.removeFirst()
                images.removeValue(forKey: oldest)
                byteCount -= costs.removeValue(forKey: oldest) ?? 0
                evictionCount += 1
            }
            await DecodedImageFrontCache.shared.store(image, for: key)
        }
        return image
    }

    func diagnostics() -> DecodedImageDiagnostics {
        DecodedImageDiagnostics(
            cacheCount: images.count,
            decodeCount: decodeCount,
            cacheHitCount: cacheHitCount,
            dedupeCount: dedupeCount,
            byteCount: byteCount,
            evictionCount: evictionCount
        )
    }

    func reset() {
        images.removeAll()
        costs.removeAll()
        order.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        decodeCount = 0
        cacheHitCount = 0
        dedupeCount = 0
        byteCount = 0
        evictionCount = 0
    }

    nonisolated private static func downsample(data: Data, pixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, pixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
#endif

public enum DecodedImagePipeline {
    @discardableResult
    public static func prepare(data: Data, key: DecodedImageKey) async -> Bool {
        #if canImport(AppKit)
        return await DecodedImageStore.shared.image(for: key, data: data) != nil
        #else
        return false
        #endif
    }

    public static func diagnostics() async -> DecodedImageDiagnostics {
        #if canImport(AppKit)
        await DecodedImageStore.shared.diagnostics()
        #else
        DecodedImageDiagnostics(cacheCount: 0, decodeCount: 0, cacheHitCount: 0, dedupeCount: 0)
        #endif
    }

    @MainActor
    public static func hasSynchronouslyCachedImage(for key: DecodedImageKey) -> Bool {
        #if canImport(AppKit)
        DecodedImageFrontCache.shared.contains(key)
        #else
        false
        #endif
    }

    public static func reset() async {
        #if canImport(AppKit)
        await DecodedImageStore.shared.reset()
        await DecodedImageFrontCache.shared.reset()
        #endif
    }
}

public struct DecodedDataImage: View {
    private let data: Data
    private let key: DecodedImageKey
    #if canImport(AppKit)
    @State private var decodedImage: CGImage?
    #endif

    public init(data: Data, key: DecodedImageKey? = nil, pixelSize: Int = 256) {
        self.data = data
        self.key = key ?? DecodedImageKey(data: data, pixelSize: pixelSize)
        #if canImport(AppKit)
        _decodedImage = State(initialValue: DecodedImageFrontCache.shared.image(for: self.key))
        #endif
    }

    public var body: some View {
        Group {
            #if canImport(AppKit)
            if let decodedImage {
                Image(decorative: decodedImage, scale: 1)
                    .resizable()
            } else {
                Color.clear
            }
            #else
            Color.clear
            #endif
        }
        .task(id: key) {
            #if canImport(AppKit)
            decodedImage = await DecodedImageStore.shared.image(for: key, data: data)
            #endif
        }
    }
}

public struct StoatUISnapshot: Equatable, Sendable {
    public var currentUser: User?
    public var users: [User]
    public var servers: [Server]
    public var channels: [Channel]
    public var messages: [Message]

    public init(currentUser: User? = nil, users: [User] = [], servers: [Server] = [], channels: [Channel] = [], messages: [Message] = []) {
        self.currentUser = currentUser
        self.users = users
        self.servers = servers
        self.channels = channels
        self.messages = messages
    }
}

public enum ComposerTextSizing {
    public static let compactHeight: CGFloat = 34
    public static let maximumHeight: CGFloat = 92
    public static let lineHeight: CGFloat = 18

    public static func height(for text: String, approximateCharactersPerLine: Int = 72) -> CGFloat {
        let normalizedLimit = max(12, approximateCharactersPerLine)
        let lineCount = visualLineEstimate(for: text, approximateCharactersPerLine: normalizedLimit)
        let height = compactHeight + CGFloat(max(0, lineCount - 1)) * lineHeight
        return min(maximumHeight, max(compactHeight, height))
    }

    private static func visualLineEstimate(for text: String, approximateCharactersPerLine: Int) -> Int {
        guard !text.isEmpty else { return 1 }
        return text
            .components(separatedBy: .newlines)
            .reduce(0) { partial, line in
                partial + max(1, Int(ceil(Double(line.count) / Double(approximateCharactersPerLine))))
            }
    }
}

public struct GlassPanel<Content: View>: View {
    private let material: StoatGlassMaterial
    private let padding: CGFloat
    private let content: Content

    public init(material: StoatGlassMaterial = .panel, padding: CGFloat = StoatSpacing.large, @ViewBuilder content: () -> Content) {
        self.material = material
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .stoatGlass(material, radius: StoatRadius.panel)
            .shadow(color: StoatElevation.softShadowColor, radius: StoatElevation.softRadius, x: 0, y: 3)
    }
}

public struct GlassSidebar<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.stoatLiquidGlassTransparency) private var liquidGlassTransparency
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let style = StoatMaterialStyle.resolved(
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased,
            liquidGlassTransparency: liquidGlassTransparency
        )
        content
            .background(sidebarBackgroundStyle(style))
    }

    private func sidebarBackgroundStyle(_ style: StoatMaterialStyle) -> AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }
        if style.usesMaterial {
            return AnyShapeStyle(.thinMaterial)
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.96))
    }
}

public struct GlassToolbar<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.stoatLiquidGlassTransparency) private var liquidGlassTransparency
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let style = StoatMaterialStyle.resolved(
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased,
            liquidGlassTransparency: liquidGlassTransparency
        )
        content
            .frame(height: 52)
            .padding(.horizontal, StoatSpacing.large)
            .background(toolbarBackgroundStyle(style))
    }

    private func toolbarBackgroundStyle(_ style: StoatMaterialStyle) -> AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
        if style.usesMaterial {
            return AnyShapeStyle(.bar)
        }
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(0.96))
    }
}

public struct GlassIconButton: View {
    private let title: String
    private let systemImage: String
    private let isSelected: Bool
    private let isDisabled: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String, isSelected: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(title)
        .accessibilityLabel(title)
    }
}

public enum ComposerAttachmentChipStatus: Hashable, Sendable {
    case queued
    case reading
    case uploading
    case uploaded
    case failed(String)
}

public struct ComposerAttachmentChip: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var filename: String
    public var subtitle: String
    public var systemImage: String
    public var status: ComposerAttachmentChipStatus
    public var previewData: Data?

    public init(id: UUID, filename: String, subtitle: String, systemImage: String, status: ComposerAttachmentChipStatus, previewData: Data? = nil) {
        self.id = id
        self.filename = filename
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.status = status
        self.previewData = previewData
    }
}

public enum AttachmentDisplayKind: Hashable, Sendable {
    case image
    case video
    case pdf
    case text
    case archive
    case generic
    case unsupported

    public var label: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .pdf: "PDF"
        case .text: "Text"
        case .archive: "Archive"
        case .generic: "File"
        case .unsupported: "Unsupported"
        }
    }

    public var systemImage: String {
        switch self {
        case .image: "photo"
        case .video: "play.rectangle"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .archive: "archivebox"
        case .generic: "doc"
        case .unsupported: "questionmark.diamond"
        }
    }

    public var isPreviewable: Bool {
        switch self {
        case .image, .pdf, .text:
            true
        case .video, .archive, .generic, .unsupported:
            false
        }
    }
}

public enum AttachmentDisplaySource: Hashable, Sendable {
    case localDraft
    case uploadedDraft(fileID: FileID)
    case remote(fileID: FileID, tag: String, url: URL?)
    case unavailable

    public var fileID: FileID? {
        switch self {
        case let .uploadedDraft(fileID), let .remote(fileID, _, _):
            fileID
        case .localDraft, .unavailable:
            nil
        }
    }

    public var isRemoteLoadable: Bool {
        if case .remote = self { return true }
        return false
    }
}

public enum AttachmentPreviewState: Hashable, Sendable {
    case notLoaded
    case loading
    case readyLocal
    case readyRemote
    case failed(String)
    case unsupported(String)

    public var isReady: Bool {
        switch self {
        case .readyLocal, .readyRemote:
            true
        case .notLoaded, .loading, .failed, .unsupported:
            false
        }
    }
}

public struct AttachmentDisplayItem: Identifiable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var id: String
    public var fileID: FileID?
    public var displayName: String
    public var contentType: String?
    public var byteCount: Int?
    public var kind: AttachmentDisplayKind
    public var source: AttachmentDisplaySource
    public var previewState: AttachmentPreviewState
    public var previewData: Data?

    public init(
        id: String,
        fileID: FileID? = nil,
        displayName: String,
        contentType: String? = nil,
        byteCount: Int? = nil,
        kind: AttachmentDisplayKind,
        source: AttachmentDisplaySource,
        previewState: AttachmentPreviewState = .notLoaded,
        previewData: Data? = nil
    ) {
        self.id = id
        self.fileID = fileID ?? source.fileID
        self.displayName = AttachmentDisplayFormatting.safeFilename(displayName)
        self.contentType = AttachmentDisplayFormatting.safeContentType(contentType)
        self.byteCount = byteCount
        self.kind = kind
        self.source = source
        self.previewState = previewState
        self.previewData = previewData
    }

    public init(file: File, previewState: AttachmentPreviewState = .notLoaded) {
        let source: AttachmentDisplaySource
        if file.deleted == true || file.reported == true {
            source = .unavailable
        } else {
            source = .remote(fileID: file.id, tag: file.tag.isEmpty ? "attachments" : file.tag, url: nil)
        }
        self.init(
            id: "file-\(file.id.rawValue)",
            fileID: file.id,
            displayName: file.filename,
            contentType: file.contentType,
            byteCount: file.size > 0 ? file.size : nil,
            kind: AttachmentDisplayFormatting.kind(contentType: file.contentType, filename: file.filename, metadata: file.metadata, unavailable: file.deleted == true || file.reported == true),
            source: source,
            previewState: file.deleted == true || file.reported == true ? .unsupported("Attachment unavailable") : previewState
        )
    }

    public var description: String {
        "\(displayName) · \(kind.label)"
    }

    public var debugDescription: String {
        "AttachmentDisplayItem(id: \(id), fileID: \(AttachmentDisplayFormatting.shortID(fileID?.rawValue)), name: \(displayName), kind: \(kind.label), state: \(previewState.safeLabel))"
    }

    public var playbackURL: URL? {
        if case let .remote(_, _, url) = source { return url }
        return nil
    }

    public var isExternalEmbedMedia: Bool {
        if case let .remote(_, tag, _) = source { return tag == "external" }
        return false
    }
}

public enum MessageRowActionRole: Hashable, Sendable {
    case standard
    case destructive
}

public struct MessageRowActionItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var systemImage: String
    public var role: MessageRowActionRole
    public var isEnabled: Bool
    public var isPrimary: Bool

    public init(
        id: String,
        title: String,
        systemImage: String,
        role: MessageRowActionRole = .standard,
        isEnabled: Bool = true,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isEnabled = isEnabled
        self.isPrimary = isPrimary
    }
}

enum MessageRowActionLayout {
    static let buttonWidth: CGFloat = 26
    static let maximumPrimaryActions = 3
    static let hoverFadeDuration: TimeInterval = 0.08

    static func trailingReservation(primaryActionCount: Int, hasMenu: Bool) -> CGFloat {
        let buttonCount = min(max(0, primaryActionCount), maximumPrimaryActions) + (hasMenu ? 1 : 0)
        guard buttonCount > 0 else { return 0 }
        let internalSpacing = CGFloat(max(0, buttonCount - 1)) * StoatSpacing.xxSmall
        let barPadding = StoatSpacing.xxSmall * 2
        return CGFloat(buttonCount) * buttonWidth + internalSpacing + barPadding + StoatSpacing.small
    }

    static func shouldMountActionBar(
        hasActions: Bool,
        isHovering: Bool,
        isFocused: Bool,
        isSelected: Bool
    ) -> Bool {
        hasActions && (isHovering || isFocused || isSelected)
    }

    static func allowsActionBarInteraction(
        hasActions: Bool,
        isHovering: Bool,
        isFocused: Bool,
        isSelected: Bool
    ) -> Bool {
        shouldMountActionBar(
            hasActions: hasActions,
            isHovering: isHovering,
            isFocused: isFocused,
            isSelected: isSelected
        )
    }
}

public struct MessageRowReplyPreviewItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var authorName: String?
    public var summary: String
    public var systemImage: String
    public var canOpen: Bool
    public var accessibilityLabel: String

    public init(
        id: String,
        authorName: String? = nil,
        summary: String,
        systemImage: String = "arrowshape.turn.up.left",
        canOpen: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.authorName = authorName
        self.summary = summary
        self.systemImage = systemImage
        self.canOpen = canOpen
        if let accessibilityLabel {
            self.accessibilityLabel = accessibilityLabel
        } else if let authorName, !authorName.isEmpty {
            self.accessibilityLabel = "Reply to \(authorName): \(summary)"
        } else {
            self.accessibilityLabel = "Reply preview: \(summary)"
        }
    }

    public var plainText: String {
        if let authorName, !authorName.isEmpty {
            return "\(authorName): \(summary)"
        }
        return summary
    }
}

public struct MessageReactionDisplayItem: Identifiable, Hashable, Sendable {
    public var emoji: String
    public var count: Int
    public var hasCurrentUserReacted: Bool
    public var customEmojiName: String?
    public var customEmojiImageData: Data?

    public var id: String { emoji }

    public init(emoji: String, count: Int, hasCurrentUserReacted: Bool, customEmojiName: String? = nil, customEmojiImageData: Data? = nil) {
        self.emoji = emoji
        self.count = count
        self.hasCurrentUserReacted = hasCurrentUserReacted
        self.customEmojiName = customEmojiName
        self.customEmojiImageData = customEmojiImageData
    }
}

public struct MessageInlineCustomEmojiItem: Identifiable, Hashable, Sendable {
    public var id: String { shortcode }
    public var shortcode: String
    public var name: String
    public var imageData: Data?

    public init(shortcode: String, name: String, imageData: Data? = nil) {
        self.shortcode = shortcode
        self.name = name
        self.imageData = imageData
    }
}

/// Sanitized role-color components (Phase 58), mirroring `ResolvedRoleColor.red/green/blue`
/// without depending on StoatFeatures, which StoatUI sits below in the package graph.
public struct MessageInlineMentionColorComponents: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Phase 58: covers the three content-token mention kinds the backend parser recognizes
/// (`<@ULID>`, `<#ULID>`, `<%ULID>`; Docs/Research.md Phase 58 Notes).
public enum MessageInlineReferenceKind: Hashable, Sendable {
    case user
    case channel
    case role
}

public struct MessageInlineReferenceItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(kind)-\(rawID)" }
    public var kind: MessageInlineReferenceKind
    public var rawID: String
    public var displayName: String
    public var roleColor: MessageInlineMentionColorComponents?
    public var isCurrentUser: Bool
    public var isFallback: Bool

    public init(
        kind: MessageInlineReferenceKind,
        rawID: String,
        displayName: String,
        roleColor: MessageInlineMentionColorComponents? = nil,
        isCurrentUser: Bool = false,
        isFallback: Bool = false
    ) {
        self.kind = kind
        self.rawID = rawID
        self.displayName = displayName
        self.roleColor = roleColor
        self.isCurrentUser = isCurrentUser
        self.isFallback = isFallback
    }

    public static func fallbackDisplayName(for kind: MessageInlineReferenceKind) -> String {
        switch kind {
        case .user: return "Unknown User"
        case .channel: return "unknown-channel"
        case .role: return "unknown-role"
        }
    }
}




public struct EmojiPickerItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var insertionText: String
    public var displayName: String
    public var searchTerms: [String]
    public var customMediaKey: String?
    public var imageData: Data?

    public init(
        id: String,
        insertionText: String,
        displayName: String? = nil,
        searchTerms: [String] = [],
        customMediaKey: String? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.insertionText = insertionText
        self.displayName = displayName ?? insertionText
        self.searchTerms = searchTerms
        self.customMediaKey = customMediaKey
        self.imageData = imageData
    }

    public static func unicode(_ value: String) -> EmojiPickerItem {
        EmojiPickerItem(id: "unicode-\(value)", insertionText: value)
    }

    public var isCustom: Bool { customMediaKey != nil }

    public func matchesSearch(_ query: String, aliases: [String] = []) -> Bool {
        insertionText.localizedCaseInsensitiveContains(query)
            || displayName.localizedCaseInsensitiveContains(query)
            || searchTerms.contains { $0.localizedCaseInsensitiveContains(query) }
            || aliases.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

public struct EmojiPickerSection: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var items: [EmojiPickerItem]

    public init(id: String, title: String, items: [EmojiPickerItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public enum AttachmentDisplayFormatting {
    public static func safeFilename(_ filename: String) -> String {
        let last = URL(fileURLWithPath: filename).lastPathComponent
        let scalars = last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    public static func safeContentType(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        let cleaned = contentType
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "/", with: "/")
        return cleaned.isEmpty ? nil : cleaned
    }

    public static func formattedSize(_ byteCount: Int?) -> String {
        guard let byteCount, byteCount > 0 else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    public static func kind(contentType: String?, filename: String, metadata: FileMetadata? = nil, unavailable: Bool = false) -> AttachmentDisplayKind {
        if unavailable { return .unsupported }
        if let metadata {
            switch metadata {
            case .image:
                return .image
            case .text:
                return .text
            case .video:
                return playableVideoKind(contentType: contentType, filename: filename)
            case .audio:
                return .unsupported
            case .file, .unknown:
                break
            }
        }
        let loweredType = (contentType ?? "").lowercased()
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if loweredType.hasPrefix("image/") || ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext) { return .image }
        if loweredType.hasPrefix("video/") || ["mp4", "mov", "m4v", "webm"].contains(ext) {
            return playableVideoKind(contentType: contentType, filename: filename)
        }
        if loweredType == "application/pdf" || ext == "pdf" { return .pdf }
        if loweredType.hasPrefix("text/") || ["md", "markdown", "json", "csv", "rtf", "txt"].contains(ext) { return .text }
        if ["zip", "gz", "tgz", "tar", "7z", "rar"].contains(ext) { return .archive }
        return .generic
    }

    private static func playableVideoKind(contentType: String?, filename: String) -> AttachmentDisplayKind {
        let loweredType = (contentType ?? "").lowercased()
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ["video/mp4", "video/quicktime", "video/x-m4v"].contains(loweredType) || ["mp4", "mov", "m4v"].contains(ext) {
            return .video
        }
        return .unsupported
    }

    public static func shortID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(4))"
    }
}

public extension AttachmentPreviewState {
    var safeLabel: String {
        switch self {
        case .notLoaded:
            "Not loaded"
        case .loading:
            "Loading"
        case .readyLocal:
            "Ready locally"
        case .readyRemote:
            "Ready"
        case let .failed(message), let .unsupported(message):
            AttachmentDisplayFormatting.safeFilename(message)
        }
    }
}

public struct GlassSearchField: View {
    private let title: String
    private let action: () -> Void

    public init(title: String = "Quick Switcher", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StoatSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘K")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, StoatSpacing.medium)
            .frame(height: 34)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Phase 58: the `@token` immediately before the composer caret, with no intervening whitespace.
/// Offsets are UTF-16 (matching `NSString`/`NSTextView` indexing) so the caller can splice the
/// verified mention token into the same `text` binding without needing AppKit types.
public enum ComposerAutocompleteKind: String, Hashable, Sendable {
    case user
    case channel
    case role
    case emoji
}

public struct InlineComposerTrigger: Hashable, Sendable {
    public var utf16Location: Int
    public var utf16Length: Int
    public var query: String
    public var kind: ComposerAutocompleteKind

    public init(
        utf16Location: Int,
        utf16Length: Int,
        query: String,
        kind: ComposerAutocompleteKind = .user
    ) {
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.query = query
        self.kind = kind
    }
}

/// One-shot cursor-placement command (mirrors the `focusRequestID` bump-to-trigger pattern):
/// bump `id` whenever `utf16Offset` should be (re-)applied, e.g. right after splicing a completed
/// mention token into the composer text.
public struct ComposerCursorRequest: Hashable, Sendable {
    public var id: Int
    public var utf16Offset: Int

    public init(id: Int, utf16Offset: Int) {
        self.id = id
        self.utf16Offset = utf16Offset
    }
}

public enum MentionAutocompleteNavigation: Hashable, Sendable {
    case up
    case down
}

public struct ComposerAutocompleteCandidate: Identifiable, Hashable, Sendable {
    public var id: String { "\(kind.rawValue):\(rawID)" }
    public var kind: ComposerAutocompleteKind
    public var rawID: String
    public var name: String
    public var subtitle: String?
    public var avatarData: Data?
    public var roleColor: MessageInlineMentionColorComponents?
    public var literalText: String?
    public var searchAliases: [String]

    public init(
        kind: ComposerAutocompleteKind,
        rawID: String,
        name: String,
        subtitle: String? = nil,
        avatarData: Data? = nil,
        roleColor: MessageInlineMentionColorComponents? = nil,
        literalText: String? = nil,
        searchAliases: [String] = []
    ) {
        self.kind = kind
        self.rawID = rawID
        self.name = name
        self.subtitle = subtitle
        self.avatarData = avatarData
        self.roleColor = roleColor
        self.literalText = literalText
        self.searchAliases = searchAliases
    }

    public static func user(
        userID: UserID,
        name: String,
        subtitle: String? = nil,
        avatarData: Data? = nil,
        searchAliases: [String] = []
    ) -> Self {
        Self(
            kind: .user,
            rawID: userID.rawValue,
            name: name,
            subtitle: subtitle,
            avatarData: avatarData,
            searchAliases: searchAliases
        )
    }

    public var userID: UserID? { kind == .user ? UserID(rawValue: rawID) : nil }
}

/// A redacted, developer-only outcome for a media paste attempt. It deliberately carries only
/// delivery categories and counts: never clipboard contents, filenames, paths, or type IDs.
public struct ComposerPasteDiagnostic: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        case keyEquivalent = "Key equivalent"
        case nativeTextView = "AppKit"
    }

    public enum Outcome: String, Hashable, Sendable {
        case queued
        case rejected
        case unsupported
    }

    public enum MediaCategory: String, Hashable, Sendable {
        case file
        case image
        case mixed
        case unknown
    }

    public var source: Source
    public var outcome: Outcome
    public var mediaCategory: MediaCategory
    public var providerCount: Int
    public var itemCount: Int

    public init(
        source: Source,
        outcome: Outcome,
        mediaCategory: MediaCategory = .unknown,
        providerCount: Int,
        itemCount: Int = 0
    ) {
        self.source = source
        self.outcome = outcome
        self.mediaCategory = mediaCategory
        self.providerCount = max(0, providerCount)
        self.itemCount = max(0, itemCount)
    }

    public var redactedDescription: String {
        "Composer paste \(source.rawValue): \(mediaCategory.rawValue), \(outcome.rawValue), providers \(providerCount), items \(itemCount)"
    }
}

public struct GlassComposer: View {
    @State private var isEmojiPopoverPresented = false
    @State private var caretTracker = ComposerCaretTracker()
    @Binding private var text: String
    private let placeholder: String
    private let isEnabled: Bool
    private let canSend: Bool
    private let disabledReason: String?
    private let isSending: Bool
    private let canAttach: Bool
    private let attachments: [ComposerAttachmentChip]
    private let attachmentSummary: String?
    private let replyAuthor: String?
    private let replyPreview: String?
    @Binding private var shouldMentionReplyAuthor: Bool
    private let focusRequestID: Int
    private let onCancelReply: () -> Void
    private let onAttach: () -> Void
    private let onUploadAttachment: (UUID) -> Void
    private let onRemoveAttachment: (UUID) -> Void
    private let onPreviewAttachment: (UUID) -> Void
    private let onDropFileURLs: ([URL]) -> Void
    private let emojiItems: [String]
    private let emojiSections: [EmojiPickerSection]
    private let onInsertEmoji: (String, Int?) -> Void
    private let customEmojiImageData: (EmojiPickerItem) -> Data?
    private let onRequestCustomEmojiImage: (EmojiPickerItem) -> Void
    private let onPasteImageData: (Data) -> Void
    private let onPasteFileURLs: ([URL]) -> Void
    private let onPasteDiagnostic: (ComposerPasteDiagnostic) -> Void
    private let onSend: () -> Void
    private let onFocus: () -> Void
    private let mentionAutocompleteCandidates: [ComposerAutocompleteCandidate]
    private let highlightedMentionCandidateID: String?
    private let cursorRequest: ComposerCursorRequest?
    private let onInlineTriggerChange: (InlineComposerTrigger?) -> Void
    private let onNativeEdit: () -> Void
    private let onInlineTriggerSuppressed: () -> Void
    private let onNavigateMentionAutocomplete: (MentionAutocompleteNavigation) -> Void
    private let onSelectHighlightedMentionCandidate: () -> Void
    private let onCancelMentionAutocomplete: () -> Void
    private let onSelectMentionCandidate: (ComposerAutocompleteCandidate) -> Void
    private let onRequestAutocompleteEmojiImage: (ComposerAutocompleteCandidate) -> Void

    public init(
        text: Binding<String>,
        shouldMentionReplyAuthor: Binding<Bool> = .constant(true),
        placeholder: String,
        isEnabled: Bool = true,
        canSend: Bool = false,
        disabledReason: String? = nil,
        isSending: Bool = false,
        canAttach: Bool = false,
        attachments: [ComposerAttachmentChip] = [],
        attachmentSummary: String? = nil,
        replyAuthor: String? = nil,
        replyPreview: String? = nil,
        focusRequestID: Int = 0,
        onCancelReply: @escaping () -> Void = {},
        onAttach: @escaping () -> Void = {},
        onUploadAttachment: @escaping (UUID) -> Void = { _ in },
        onRemoveAttachment: @escaping (UUID) -> Void = { _ in },
        onPreviewAttachment: @escaping (UUID) -> Void = { _ in },
        onDropFileURLs: @escaping ([URL]) -> Void = { _ in },
        emojiItems: [String] = [],
        emojiSections: [EmojiPickerSection] = [],
        onInsertEmoji: @escaping (String, Int?) -> Void = { _, _ in },
        customEmojiImageData: @escaping (EmojiPickerItem) -> Data? = { $0.imageData },
        onRequestCustomEmojiImage: @escaping (EmojiPickerItem) -> Void = { _ in },
        onPasteImageData: @escaping (Data) -> Void = { _ in },
        onPasteFileURLs: @escaping ([URL]) -> Void = { _ in },
        onPasteDiagnostic: @escaping (ComposerPasteDiagnostic) -> Void = { _ in },
        onSend: @escaping () -> Void = {},
        onFocus: @escaping () -> Void = {},
        mentionAutocompleteCandidates: [ComposerAutocompleteCandidate] = [],
        highlightedMentionCandidateID: String? = nil,
        cursorRequest: ComposerCursorRequest? = nil,
        onInlineTriggerChange: @escaping (InlineComposerTrigger?) -> Void = { _ in },
        onNativeEdit: @escaping () -> Void = {},
        onInlineTriggerSuppressed: @escaping () -> Void = {},
        onNavigateMentionAutocomplete: @escaping (MentionAutocompleteNavigation) -> Void = { _ in },
        onSelectHighlightedMentionCandidate: @escaping () -> Void = {},
        onCancelMentionAutocomplete: @escaping () -> Void = {},
        onSelectMentionCandidate: @escaping (ComposerAutocompleteCandidate) -> Void = { _ in },
        onRequestAutocompleteEmojiImage: @escaping (ComposerAutocompleteCandidate) -> Void = { _ in }
    ) {
        self._text = text
        self._shouldMentionReplyAuthor = shouldMentionReplyAuthor
        self.placeholder = placeholder
        self.isEnabled = isEnabled
        self.canSend = canSend
        self.disabledReason = disabledReason
        self.isSending = isSending
        self.canAttach = canAttach
        self.attachments = attachments
        self.attachmentSummary = attachmentSummary
        self.replyAuthor = replyAuthor
        self.replyPreview = replyPreview
        self.focusRequestID = focusRequestID
        self.onCancelReply = onCancelReply
        self.onAttach = onAttach
        self.onUploadAttachment = onUploadAttachment
        self.onRemoveAttachment = onRemoveAttachment
        self.onPreviewAttachment = onPreviewAttachment
        self.onDropFileURLs = onDropFileURLs
        self.emojiItems = emojiItems
        self.emojiSections = emojiSections
        self.onInsertEmoji = onInsertEmoji
        self.customEmojiImageData = customEmojiImageData
        self.onRequestCustomEmojiImage = onRequestCustomEmojiImage
        self.onPasteImageData = onPasteImageData
        self.onPasteFileURLs = onPasteFileURLs
        self.onPasteDiagnostic = onPasteDiagnostic
        self.onSend = onSend
        self.onFocus = onFocus
        self.mentionAutocompleteCandidates = mentionAutocompleteCandidates
        self.highlightedMentionCandidateID = highlightedMentionCandidateID
        self.cursorRequest = cursorRequest
        self.onInlineTriggerChange = onInlineTriggerChange
        self.onNativeEdit = onNativeEdit
        self.onInlineTriggerSuppressed = onInlineTriggerSuppressed
        self.onNavigateMentionAutocomplete = onNavigateMentionAutocomplete
        self.onSelectHighlightedMentionCandidate = onSelectHighlightedMentionCandidate
        self.onCancelMentionAutocomplete = onCancelMentionAutocomplete
        self.onSelectMentionCandidate = onSelectMentionCandidate
        self.onRequestAutocompleteEmojiImage = onRequestAutocompleteEmojiImage
    }

    public var body: some View {
        GlassPanel(material: .composer, padding: StoatSpacing.medium) {
            VStack(alignment: .leading, spacing: StoatSpacing.small) {
                if let replyAuthor, let replyPreview {
                    HStack(spacing: StoatSpacing.small) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                            Text("Replying to \(replyAuthor)")
                                .font(.caption.weight(.semibold))
                            Text(replyPreview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("Mention", isOn: $shouldMentionReplyAuthor)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        GlassIconButton("Cancel Reply", systemImage: "xmark", action: onCancelReply)
                    }
                    .padding(.horizontal, StoatSpacing.small)
                    .padding(.vertical, StoatSpacing.xSmall)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(StoatAccessibility.replyContextLabel(author: replyAuthor, preview: replyPreview, mentionsAuthor: shouldMentionReplyAuthor))
                }
                if !attachments.isEmpty {
                    if let attachmentSummary {
                        Text(attachmentSummary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Attachment summary, \(attachmentSummary)")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: StoatSpacing.small) {
                            ForEach(attachments) { attachment in
                                ComposerAttachmentChipView(
                                    attachment: attachment,
                                    onUpload: { onUploadAttachment(attachment.id) },
                                    onRemove: { onRemoveAttachment(attachment.id) },
                                    onPreview: { onPreviewAttachment(attachment.id) }
                                )
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .accessibilityLabel("Queued attachments")
                }
                HStack(alignment: .bottom, spacing: StoatSpacing.medium) {
                    GlassIconButton(canAttach ? "Attach File" : "Attach file unavailable because file upload permission is missing", systemImage: "paperclip", isDisabled: !canAttach) {
                        onAttach()
                    }
                    ZStack(alignment: .topLeading) {
                        ComposerTextInput(
                            text: $text,
                            isEnabled: isEnabled,
                            focusRequestID: focusRequestID,
                            caretTracker: caretTracker,
                            onSubmit: onSend,
                            onFocus: onFocus,
                            onPasteImageData: onPasteImageData,
                            onPasteFileURLs: onPasteFileURLs,
                            onPasteDiagnostic: onPasteDiagnostic,
                            hasMentionCandidates: !mentionAutocompleteCandidates.isEmpty,
                            cursorRequest: cursorRequest,
                            onInlineTriggerChange: onInlineTriggerChange,
                            onNativeEdit: onNativeEdit,
                            onInlineTriggerSuppressed: onInlineTriggerSuppressed,
                            onNavigateMentionAutocomplete: onNavigateMentionAutocomplete,
                            onSelectHighlightedMentionCandidate: onSelectHighlightedMentionCandidate,
                            onCancelMentionAutocomplete: onCancelMentionAutocomplete
                        )
                            .frame(height: ComposerTextSizing.height(for: text))
                            .overlay(alignment: .topLeading) {
                                if !mentionAutocompleteCandidates.isEmpty {
                                    InlineAutocompletePopover(
                                        candidates: mentionAutocompleteCandidates,
                                        highlightedID: highlightedMentionCandidateID,
                                        onSelect: onSelectMentionCandidate,
                                        onRequestEmojiImage: onRequestAutocompleteEmojiImage
                                    )
                                    // Positioned from values already known here rather than from
                                    // the child's measured height: the popover used to be offset
                                    // by its own collapsed height, so it sat wrong by exactly the
                                    // amount that had been clipped away.
                                    .offset(y: ComposerAutocompleteSizing.offsetAboveField(
                                        fieldHeight: ComposerTextSizing.height(for: text),
                                        popoverHeight: ComposerAutocompleteSizing.height(
                                            candidateCount: mentionAutocompleteCandidates.count
                                        )
                                    ))
                                }
                            }
                        if text.isEmpty {
                            Text(placeholder)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    Button {
                        isEmojiPopoverPresented.toggle()
                        if isEmojiPopoverPresented {
                            onCancelMentionAutocomplete()
                        }
                    } label: {
                        Image(systemName: "face.smiling")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $isEmojiPopoverPresented, arrowEdge: .top) {
                        EmojiPickerPopover(
                            sections: emojiSections.isEmpty
                                ? [EmojiPickerSection(id: "emoji", title: "Emoji", items: emojiItems.map(EmojiPickerItem.unicode))]
                                : emojiSections,
                            disabledReason: isEnabled ? nil : disabledReason,
                            customEmojiImageData: customEmojiImageData,
                            onRequestCustomEmojiImage: onRequestCustomEmojiImage,
                            onInsertEmoji: { emoji in
                                let currentLength = (text as NSString).length
                                let offset = caretTracker.documentUTF16Length == currentLength
                                    ? caretTracker.utf16Offset
                                    : nil
                                onInsertEmoji(emoji, offset)
                                isEmojiPopoverPresented = false
                            }
                        )
                    }
                    .help("Insert emoji")
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 30, height: 30)
                    } else {
                        GlassIconButton(disabledReason ?? "Send Message", systemImage: "arrow.up.circle.fill", isDisabled: !canSend) {
                            onSend()
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(StoatAccessibility.composerLabel(isEnabled: isEnabled, disabledReason: disabledReason, replyAuthor: replyAuthor))
        .accessibilityHint(isEnabled ? "Press Return to send, Shift Return for a new line" : (disabledReason ?? "Composer is unavailable"))
        .help(disabledReason ?? placeholder)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            loadDroppedFileURLs(from: providers)
            return true
        }
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    DispatchQueue.main.async {
                        onDropFileURLs([url])
                    }
                }
            }
        }
    }
}

#if canImport(AppKit)
extension GlassComposer {
    @MainActor
    static func _testDetectInlineTrigger(text: String, caretUTF16Offset: Int) -> InlineComposerTrigger? {
        let textView = NSTextView()
        textView.string = text
        textView.setSelectedRange(NSRange(location: caretUTF16Offset, length: 0))
        return ComposerTextView.Coordinator.detectInlineTrigger(in: textView)
    }

    struct TestPasteOutcome {
        let resultingText: String
        let pastedFileURLs: [URL]?
        let pastedImageData: Data?
        let pastedImageDataList: [Data]
        let diagnostics: [ComposerPasteDiagnostic]
    }

    struct TestNativeInputOutcome {
        let resultingText: String
        let pastedImageData: Data?
        let nativeEditCount: Int
        let inlineTriggerPublications: [InlineComposerTrigger?]
        let inlineTriggerSuppressionCount: Int
    }

    /// Reproduces the live Character Viewer path after an attachment paste. `insertText` is the
    /// NSTextInputClient entry used for composed Unicode input, including surrogate-pair emoji.
    @MainActor
    static func _testAttachmentThenNativeTextAndEmoji(
        imageData: Data,
        text: String,
        emoji: String
    ) -> TestNativeInputOutcome {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("StoatUITests.ComposerNativeInput.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: .png)

        var bindingText = ""
        var pastedImageData: Data?
        var nativeEditCount = 0
        var publications: [InlineComposerTrigger?] = []
        var suppressionCount = 0
        let handlers = ComposerTextHandlers(
            onSubmit: {},
            onFocus: {},
            onPasteImageData: { pastedImageData = $0 },
            onPasteFileURLs: { _ in },
            onPasteDiagnostic: { _ in },
            onInlineTriggerChange: { publications.append($0) },
            onNativeEdit: { nativeEditCount += 1 },
            onInlineTriggerSuppressed: { suppressionCount += 1 }
        )
        let binding = Binding<String>(get: { bindingText }, set: { bindingText = $0 })
        let coordinator = ComposerTextView.Coordinator(text: binding, handlers: handlers)
        let textView = ComposerPasteInterceptingTextView()
        textView.delegate = coordinator
        textView.pasteboardOverride = pasteboard
        textView.onPasteImageData = handlers.onPasteImageData
        textView.paste(nil)

        for value in [text, emoji, emoji] {
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            textView.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0))
            coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        }

        return TestNativeInputOutcome(
            resultingText: bindingText,
            pastedImageData: pastedImageData,
            nativeEditCount: nativeEditCount,
            inlineTriggerPublications: publications,
            inlineTriggerSuppressionCount: suppressionCount
        )
    }

    /// Drives the composer's native paste entry points against a scratch pasteboard (never
    /// `NSPasteboard.general`) so tests can exercise attachment-vs-text precedence without
    /// touching the real system clipboard.
    @MainActor
    static func _testPaste(existingText: String, configurePasteboard: (NSPasteboard) -> Void) -> TestPasteOutcome {
        testPaste(existingText: existingText, configurePasteboard: configurePasteboard) { textView, pasteboard in
            textView.paste(nil)
        }
    }

    /// `NSTextView` can reach this lower-level read path for paste services and rich clipboard
    /// representations. Keep it covered separately from the command-selector paste path.
    @MainActor
    static func _testReadSelection(existingText: String, configurePasteboard: (NSPasteboard) -> Void) -> TestPasteOutcome {
        testPaste(existingText: existingText, configurePasteboard: configurePasteboard) { textView, pasteboard in
            _ = textView.readSelection(from: pasteboard, type: .string)
        }
    }

    /// Exercises the Cmd-V entry point that is used in the live composer. This stays separate
    /// from `paste(_:)`: AppKit's key-equivalent traversal happens before menu command routing.
    @MainActor
    static func _testKeyEquivalentPaste(existingText: String, configurePasteboard: (NSPasteboard) -> Void) -> TestPasteOutcome {
        testPaste(existingText: existingText, configurePasteboard: configurePasteboard) { textView, _ in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = textView
            window.makeFirstResponder(textView)
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "v",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: 9
            )!
            _ = textView.performKeyEquivalent(with: event)
        }
    }

    @MainActor
    private static func testPaste(
        existingText: String,
        configurePasteboard: (NSPasteboard) -> Void,
        invoke: (ComposerPasteInterceptingTextView, NSPasteboard) -> Void
    ) -> TestPasteOutcome {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("StoatUITests.ComposerPaste.\(UUID().uuidString)"))
        pasteboard.clearContents()
        configurePasteboard(pasteboard)

        let textView = ComposerPasteInterceptingTextView()
        textView.string = existingText
        textView.pasteboardOverride = pasteboard

        var pastedFileURLs: [URL]?
        var pastedImageData: Data?
        textView.onPasteFileURLs = { pastedFileURLs = $0 }
        textView.onPasteImageData = { pastedImageData = $0 }

        invoke(textView, pasteboard)

        return TestPasteOutcome(
            resultingText: textView.string,
            pastedFileURLs: pastedFileURLs,
            pastedImageData: pastedImageData,
            pastedImageDataList: pastedImageData.map { [$0] } ?? [],
            diagnostics: []
        )
    }

}
#endif


private struct EmojiPickerPopover: View {
    let sections: [EmojiPickerSection]
    let disabledReason: String?
    let customEmojiImageData: (EmojiPickerItem) -> Data?
    let onRequestCustomEmojiImage: (EmojiPickerItem) -> Void
    let onInsertEmoji: (String) -> Void
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            Text("Emoji")
                .font(.headline)
            if let disabledReason {
                EmptyStateView(title: "Emoji unavailable", message: disabledReason, systemImage: "face.smiling")
            } else if sections.flatMap(\.items).isEmpty {
                EmptyStateView(title: "No emoji available", message: "Emoji will appear here when the composer is ready.", systemImage: "face.smiling")
            } else if filteredSections.isEmpty {
                TextField("Search emoji", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                EmptyStateView(title: "No matches", message: "Try another emoji name or shortcode.", systemImage: "magnifyingglass")
            } else {
                TextField("Search emoji", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                        ForEach(filteredSections) { section in
                            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                                Text(section.title.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8), spacing: 4) {
                                    ForEach(section.items) { item in
                                        Button {
                                            onInsertEmoji(item.insertionText)
                                        } label: {
                                            emojiLabel(item)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Insert emoji \(item.displayName)")
                                        .onAppear {
                                            guard item.isCustom, customEmojiImageData(item) == nil else { return }
                                            onRequestCustomEmojiImage(item)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(StoatSpacing.medium)
        .frame(width: 330, alignment: .leading)
    }

    private var filteredSections: [EmojiPickerSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections.filter { !$0.items.isEmpty } }
        return sections.compactMap { section in
            let matches = section.items.filter { item in
                item.matchesSearch(query, aliases: Self.aliases(for: item.insertionText))
            }
            return matches.isEmpty ? nil : EmojiPickerSection(id: section.id, title: section.title, items: matches)
        }
    }

    @ViewBuilder private func emojiLabel(_ item: EmojiPickerItem) -> some View {
        #if canImport(AppKit)
        if let imageData = customEmojiImageData(item) {
            DecodedDataImage(data: imageData, pixelSize: 56)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        } else {
            fallbackEmojiLabel(item)
        }
        #else
        fallbackEmojiLabel(item)
        #endif
    }

    private func fallbackEmojiLabel(_ item: EmojiPickerItem) -> some View {
        Text(item.isCustom ? ":\(item.displayName):" : item.insertionText)
            .font(item.isCustom ? .caption.weight(.semibold) : .title3)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private static func aliases(for emoji: String) -> [String] {
        switch emoji {
        case "👍": return ["thumbs up", "like", "yes"]
        case "❤️": return ["heart", "love"]
        case "😂": return ["laugh", "joy", "tears"]
        case "🥯": return ["bagel"]
        case "✅": return ["check", "done", "success"]
        case "👀": return ["eyes", "look"]
        case "🎉": return ["party", "celebrate", "tada"]
        case "🙏": return ["pray", "thanks", "please"]
        case "🔥": return ["fire", "hot"]
        case "✨": return ["sparkles", "magic"]
        case "💬": return ["message", "chat", "comment"]
        case "📌": return ["pin", "pinned"]
        case "⭐": return ["star", "favorite"]
        case "❌": return ["x", "cancel", "no"]
        case "😄": return ["smile", "happy"]
        case "😅": return ["sweat", "relief"]
        case "😎": return ["cool", "sunglasses"]
        case "😢": return ["sad", "cry"]
        case "😮": return ["surprise", "wow"]
        case "🤔": return ["thinking", "hmm"]
        case "🚀": return ["rocket", "ship"]
        case "💯": return ["hundred", "perfect"]
        case "🫡": return ["salute"]
        case "👋": return ["wave", "hello"]
        case "🙌": return ["raise hands", "hooray"]
        case "😆": return ["laugh", "grin"]
        case "😋": return ["yum", "tasty"]
        case "😴": return ["sleep", "tired"]
        case "😭": return ["sob", "cry"]
        case "😬": return ["grimace", "awkward"]
        case "😤": return ["frustrated", "triumph"]
        case "🥳": return ["party", "celebrate"]
        case "🤝": return ["handshake", "deal"]
        case "🫶": return ["heart hands", "support"]
        default: return []
        }
    }
}

private struct ComposerAttachmentChipView: View {
    let attachment: ComposerAttachmentChip
    let onUpload: () -> Void
    let onRemove: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: StoatSpacing.small) {
            preview
            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                Text(attachment.filename)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
            }
            if showsUploadButton {
                GlassIconButton(uploadTitle, systemImage: "arrow.up.circle", action: onUpload)
            }
            GlassIconButton("Remove Attachment", systemImage: "xmark", action: onRemove)
        }
        .padding(.leading, StoatSpacing.xSmall)
        .padding(.trailing, StoatSpacing.xxSmall)
        .padding(.vertical, StoatSpacing.xSmall)
        .frame(width: 260, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onPreview)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attachment.filename), \(statusText)")
        .accessibilityHint("Press to preview. Use the buttons to upload or remove the attachment.")
    }

    @ViewBuilder private var preview: some View {
        #if canImport(AppKit)
        if let data = attachment.previewData {
            DecodedDataImage(data: data, pixelSize: 68)
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: attachment.systemImage)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                .accessibilityHidden(true)
        }
        #else
        Image(systemName: attachment.systemImage)
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
        #endif
    }

    private var statusText: String {
        switch attachment.status {
        case .queued:
            return "\(attachment.subtitle) · queued"
        case .reading:
            return "Reading"
        case .uploading:
            return "Uploading"
        case .uploaded:
            return "\(attachment.subtitle) · uploaded"
        case let .failed(message):
            return message
        }
    }

    private var statusColor: Color {
        if case .failed = attachment.status {
            return .red
        }
        return .secondary
    }

    private var showsProgress: Bool {
        switch attachment.status {
        case .reading, .uploading:
            return true
        case .queued, .uploaded, .failed:
            return false
        }
    }

    private var showsUploadButton: Bool {
        switch attachment.status {
        case .queued, .failed:
            true
        case .reading, .uploading, .uploaded:
            false
        }
    }

    private var uploadTitle: String {
        if case .failed = attachment.status {
            return "Retry Upload"
        }
        return "Upload Attachment"
    }
}

private struct ComposerTextInput: View {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequestID: Int
    let caretTracker: ComposerCaretTracker
    let onSubmit: () -> Void
    let onFocus: () -> Void
    let onPasteImageData: (Data) -> Void
    let onPasteFileURLs: ([URL]) -> Void
    let onPasteDiagnostic: (ComposerPasteDiagnostic) -> Void
    var hasMentionCandidates: Bool = false
    var cursorRequest: ComposerCursorRequest? = nil
    var onInlineTriggerChange: (InlineComposerTrigger?) -> Void = { _ in }
    var onNativeEdit: () -> Void = {}
    var onInlineTriggerSuppressed: () -> Void = {}
    var onNavigateMentionAutocomplete: (MentionAutocompleteNavigation) -> Void = { _ in }
    var onSelectHighlightedMentionCandidate: () -> Void = {}
    var onCancelMentionAutocomplete: () -> Void = {}

    var body: some View {
        #if canImport(AppKit)
        ComposerTextView(
            text: $text,
            isEnabled: isEnabled,
            focusRequestID: focusRequestID,
            caretTracker: caretTracker,
            hasMentionCandidates: hasMentionCandidates,
            cursorRequest: cursorRequest,
            handlers: ComposerTextHandlers(
                onSubmit: onSubmit,
                onFocus: onFocus,
                onPasteImageData: onPasteImageData,
                onPasteFileURLs: onPasteFileURLs,
                onPasteDiagnostic: onPasteDiagnostic,
                onInlineTriggerChange: onInlineTriggerChange,
                onNativeEdit: onNativeEdit,
                onInlineTriggerSuppressed: onInlineTriggerSuppressed,
                onNavigateMentionAutocomplete: onNavigateMentionAutocomplete,
                onSelectHighlightedMentionCandidate: onSelectHighlightedMentionCandidate,
                onCancelMentionAutocomplete: onCancelMentionAutocomplete
            )
        )
            .font(.body)
        #else
        TextEditor(text: $text)
            .font(.body)
            .disabled(!isEnabled)
            .onTapGesture(perform: onFocus)
        #endif
    }
}

#if canImport(AppKit)
/// Classifies clipboard content for composer paste: an attachment payload (file URLs or image
/// data) always wins over any accompanying text representation on the same pasteboard item,
/// since Finder/screenshot copies commonly carry both.
enum ComposerPastePayload: Equatable {
    case fileURLs([URL])
    case imageData(Data)
    case none
}

enum ComposerPastePayloadClassifier {
    static func classify(pasteboard: NSPasteboard) -> ComposerPastePayload {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty {
            return .fileURLs(urls)
        }
        if let fileURL = pasteboard.string(forType: .fileURL)
            .flatMap(URL.init(string:)), fileURL.isFileURL {
            return .fileURLs([fileURL])
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return .imageData(data)
        }
        // Screenshot and image-provider pasteboards do not always advertise PNG or TIFF
        // directly. AppKit knows how to decode their generic image representations; normalize
        // those to PNG so the composer queue has valid, accurately-labelled image bytes.
        if let image = NSImage(pasteboard: pasteboard),
           let pngData = normalizedPNGData(from: image) {
            return .imageData(pngData)
        }
        return .none
    }

    static func normalizedPNGData(from sourceData: Data) -> Data? {
        guard let image = NSImage(data: sourceData) else { return nil }
        return normalizedPNGData(from: image)
    }

    private static func normalizedPNGData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// Overrides `paste(_:)` directly rather than relying solely on the delegate's
/// `doCommandBySelector:` hook -- a menu-invoked or Services-invoked paste calls this method
/// on the first responder directly and never reaches `doCommandBySelector:`, so intercepting
/// only there missed those paths.
final class ComposerPasteInterceptingTextView: NSTextView {
    var onPasteFileURLs: (([URL]) -> Void)?
    var onPasteImageData: ((Data) -> Void)?
    var onPasteDiagnostic: ((ComposerPasteDiagnostic) -> Void)?
    var pasteboardOverride: NSPasteboard?

    /// `onPasteCommand` may claim Cmd-V before the native text view and then fail to load an
    /// advertised provider. Intercept the key equivalent at the first responder instead, using
    /// the synchronous pasteboard classifier; normal text still falls through to AppKit.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown,
              modifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              window?.firstResponder === self,
              isEditable
        else {
            return super.performKeyEquivalent(with: event)
        }
        if consumeAttachmentPayload(from: pasteboardOverride ?? .general, source: .keyEquivalent) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = pasteboardOverride ?? .general
        if consumeAttachmentPayload(from: pasteboard, source: .nativeTextView) {
            return
        }
        // `super.paste(_:)` always reads `NSPasteboard.general` -- it has no notion of
        // `pasteboardOverride`. Production never sets an override, so this only changes
        // behavior for tests, which route text fallback through the overridden pasteboard
        // instead of touching the real system clipboard.
        if let pasteboardOverride {
            if let string = pasteboardOverride.string(forType: .string) {
                insertText(string, replacementRange: selectedRange())
            }
        } else {
            super.paste(sender)
        }
    }

    /// AppKit may bypass `paste(_:)` for Services and rich clipboard representations and read
    /// the selected type directly. Intercept here too so media never falls through as text.
    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if consumeAttachmentPayload(from: pasteboard, source: .nativeTextView) {
            return true
        }
        return super.readSelection(from: pasteboard, type: type)
    }

    private func consumeAttachmentPayload(
        from pasteboard: NSPasteboard,
        source: ComposerPasteDiagnostic.Source
    ) -> Bool {
        switch ComposerPastePayloadClassifier.classify(pasteboard: pasteboard) {
        case let .fileURLs(urls):
            onPasteFileURLs?(urls)
            onPasteDiagnostic?(ComposerPasteDiagnostic(
                source: source,
                outcome: .queued,
                mediaCategory: .file,
                providerCount: 1,
                itemCount: urls.count
            ))
            return true
        case let .imageData(data):
            onPasteImageData?(data)
            onPasteDiagnostic?(ComposerPasteDiagnostic(
                source: source,
                outcome: .queued,
                mediaCategory: .image,
                providerCount: 1,
                itemCount: 1
            ))
            return true
        case .none:
            return false
        }
    }
}

/// Boxes the composer's callback closures behind one reference so `ComposerTextView` stays a
/// small struct. SwiftUI copies representable structs repeatedly inside layout passes (this was
/// a hotspot in the Phase 63 window-resize hang trace); with the box, each copy is one retain
/// instead of nine closure-context retains plus wide memberwise moves.
final class ComposerTextHandlers {
    let onSubmit: () -> Void
    let onFocus: () -> Void
    let onPasteImageData: (Data) -> Void
    let onPasteFileURLs: ([URL]) -> Void
    let onPasteDiagnostic: (ComposerPasteDiagnostic) -> Void
    let onInlineTriggerChange: (InlineComposerTrigger?) -> Void
    let onNativeEdit: () -> Void
    let onInlineTriggerSuppressed: () -> Void
    let onNavigateMentionAutocomplete: (MentionAutocompleteNavigation) -> Void
    let onSelectHighlightedMentionCandidate: () -> Void
    let onCancelMentionAutocomplete: () -> Void

    init(
        onSubmit: @escaping () -> Void,
        onFocus: @escaping () -> Void,
        onPasteImageData: @escaping (Data) -> Void,
        onPasteFileURLs: @escaping ([URL]) -> Void,
        onPasteDiagnostic: @escaping (ComposerPasteDiagnostic) -> Void,
        onInlineTriggerChange: @escaping (InlineComposerTrigger?) -> Void = { _ in },
        onNativeEdit: @escaping () -> Void = {},
        onInlineTriggerSuppressed: @escaping () -> Void = {},
        onNavigateMentionAutocomplete: @escaping (MentionAutocompleteNavigation) -> Void = { _ in },
        onSelectHighlightedMentionCandidate: @escaping () -> Void = {},
        onCancelMentionAutocomplete: @escaping () -> Void = {}
    ) {
        self.onSubmit = onSubmit
        self.onFocus = onFocus
        self.onPasteImageData = onPasteImageData
        self.onPasteFileURLs = onPasteFileURLs
        self.onPasteDiagnostic = onPasteDiagnostic
        self.onInlineTriggerChange = onInlineTriggerChange
        self.onNativeEdit = onNativeEdit
        self.onInlineTriggerSuppressed = onInlineTriggerSuppressed
        self.onNavigateMentionAutocomplete = onNavigateMentionAutocomplete
        self.onSelectHighlightedMentionCandidate = onSelectHighlightedMentionCandidate
        self.onCancelMentionAutocomplete = onCancelMentionAutocomplete
    }
}

/// Pull-based AppKit selection state. This deliberately has no observation conformance: arrow
/// keys and clicks update two integers without invalidating the SwiftUI composer hierarchy.
@MainActor final class ComposerCaretTracker {
    var utf16Offset: Int?
    var documentUTF16Length = 0

    func update(from textView: NSTextView) {
        let selection = textView.selectedRange()
        utf16Offset = selection.length == 0 ? selection.location : nil
        documentUTF16Length = (textView.string as NSString).length
    }

    func invalidate() {
        utf16Offset = nil
        documentUTF16Length = 0
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequestID: Int
    let caretTracker: ComposerCaretTracker
    var hasMentionCandidates: Bool = false
    var cursorRequest: ComposerCursorRequest? = nil
    let handlers: ComposerTextHandlers

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, handlers: handlers, caretTracker: caretTracker)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = ComposerPasteInterceptingTextView(frame: .zero, textContainer: textContainer)
        textView.onPasteFileURLs = handlers.onPasteFileURLs
        textView.onPasteImageData = handlers.onPasteImageData
        textView.onPasteDiagnostic = handlers.onPasteDiagnostic
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.minSize = NSSize(width: 0, height: ComposerTextSizing.compactHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        // GlassComposer pins the input's height with an explicit frame, so the proposal carries
        // the answer on the hot path; the text-derived estimate is a fallback, memoized on the
        // coordinator so it runs once per text change instead of once per layout pass.
        let height = proposal.height ?? context.coordinator.estimatedHeight(for: text)
        return CGSize(
            width: max(1, width),
            height: min(ComposerTextSizing.maximumHeight, max(ComposerTextSizing.compactHeight, height))
        )
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ComposerPasteInterceptingTextView else { return }
        if textView.string != text {
            textView.string = text
            caretTracker.invalidate()
        }
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        if isEnabled, context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(textView)
            }
        }
        if let cursorRequest, context.coordinator.lastAppliedCursorRequestID != cursorRequest.id {
            context.coordinator.lastAppliedCursorRequestID = cursorRequest.id
            let clampedOffset = max(0, min(cursorRequest.utf16Offset, (textView.string as NSString).length))
            textView.setSelectedRange(NSRange(location: clampedOffset, length: 0))
            textView.scrollRangeToVisible(NSRange(location: clampedOffset, length: 0))
            caretTracker.update(from: textView)
        }
        context.coordinator.text = $text
        context.coordinator.handlers = handlers
        textView.onPasteImageData = handlers.onPasteImageData
        textView.onPasteFileURLs = handlers.onPasteFileURLs
        textView.onPasteDiagnostic = handlers.onPasteDiagnostic
        context.coordinator.hasMentionCandidates = hasMentionCandidates
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var handlers: ComposerTextHandlers
        let caretTracker: ComposerCaretTracker
        var lastFocusRequestID = 0
        var lastAppliedCursorRequestID = 0
        var hasMentionCandidates = false
        private var lastSizingText: String?
        private var lastSizingHeight: CGFloat = ComposerTextSizing.compactHeight
        private var hasReportedInlineTrigger = false
        private var lastReportedInlineTrigger: InlineComposerTrigger?

        init(
            text: Binding<String>,
            handlers: ComposerTextHandlers,
            caretTracker: ComposerCaretTracker = ComposerCaretTracker()
        ) {
            self.text = text
            self.handlers = handlers
            self.caretTracker = caretTracker
        }

        func estimatedHeight(for text: String) -> CGFloat {
            if lastSizingText == text {
                return lastSizingHeight
            }
            let height = ComposerTextSizing.height(for: text)
            lastSizingText = text
            lastSizingHeight = height
            return height
        }

        func textDidBeginEditing(_ notification: Notification) {
            handlers.onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            handlers.onNativeEdit()
            text.wrappedValue = textView.string
            caretTracker.update(from: textView)
            reportInlineTriggerIfChanged(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            caretTracker.update(from: textView)
            reportInlineTriggerIfChanged(in: textView)
        }

        @MainActor private func reportInlineTriggerIfChanged(in textView: NSTextView) {
            let trigger = Self.detectInlineTrigger(in: textView)
            guard !hasReportedInlineTrigger || trigger != lastReportedInlineTrigger else {
                handlers.onInlineTriggerSuppressed()
                return
            }
            hasReportedInlineTrigger = true
            lastReportedInlineTrigger = trigger
            handlers.onInlineTriggerChange(trigger)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if hasMentionCandidates {
                switch commandSelector {
                case #selector(NSResponder.moveUp(_:)):
                    handlers.onNavigateMentionAutocomplete(.up)
                    return true
                case #selector(NSResponder.moveDown(_:)):
                    handlers.onNavigateMentionAutocomplete(.down)
                    return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    handlers.onSelectHighlightedMentionCandidate()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    handlers.onCancelMentionAutocomplete()
                    return true
                default:
                    break
                }
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            if NSEvent.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                text.wrappedValue = textView.string
            } else {
                handlers.onSubmit()
            }
            return true
        }

        /// Phase 71: the inline sigil token immediately before the caret. Scans stay bounded to
        /// protect long drafts and all offsets use AppKit's UTF-16 indexing.
        @MainActor
        static func detectInlineTrigger(in textView: NSTextView) -> InlineComposerTrigger? {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else { return nil }
            let nsString = textView.string as NSString
            let caret = selectedRange.location
            guard caret > 0, caret <= nsString.length else { return nil }
            let scanLimit = 64
            var start = caret
            var scanned = 0
            while start > 0, scanned < scanLimit {
                let previousChar = nsString.substring(with: NSRange(location: start - 1, length: 1))
                if let kind = kind(for: previousChar) {
                    let sigilIndex = start - 1
                    if sigilIndex > 0 {
                        let charBeforeSigil = nsString.substring(with: NSRange(location: sigilIndex - 1, length: 1))
                        if charBeforeSigil.rangeOfCharacter(from: .alphanumerics) != nil {
                            return nil
                        }
                    }
                    let query = nsString.substring(with: NSRange(location: start, length: caret - start))
                    guard isAcceptableQuery(query, kind: kind), !isInsideInlineCode(nsString, sigilIndex: sigilIndex) else {
                        return nil
                    }
                    return InlineComposerTrigger(
                        utf16Location: sigilIndex,
                        utf16Length: caret - sigilIndex,
                        query: query,
                        kind: kind
                    )
                }
                if previousChar.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                    return nil
                }
                start -= 1
                scanned += 1
            }
            return nil
        }

        private static func kind(for sigil: String) -> ComposerAutocompleteKind? {
            switch sigil {
            case "@": .user
            case "#": .channel
            case "%": .role
            case ":": .emoji
            default: nil
            }
        }

        static func isAcceptableQuery(_ query: String, kind: ComposerAutocompleteKind) -> Bool {
            guard query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
            switch kind {
            case .user:
                return true
            case .emoji:
                guard query.count >= 2 else { return false }
                return query.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "_+-".unicodeScalars.contains($0) }
            case .channel:
                guard query.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }) else {
                    return false
                }
                guard !query.isEmpty, !query.allSatisfy(\.isNumber) else { return query.isEmpty }
                let isHexShape = [3, 4, 6, 8].contains(query.count)
                    && query.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
                return !isHexShape
            case .role:
                guard query.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }) else {
                    return false
                }
                return query.isEmpty || !query.allSatisfy(\.isNumber)
            }
        }

        private static func isInsideInlineCode(_ text: NSString, sigilIndex: Int) -> Bool {
            var lineStart = sigilIndex
            while lineStart > 0 {
                let character = text.substring(with: NSRange(location: lineStart - 1, length: 1))
                if character == "\n" { break }
                lineStart -= 1
            }
            let prefix = text.substring(with: NSRange(location: lineStart, length: sigilIndex - lineStart))
            return prefix.filter { $0 == "`" }.count.isMultiple(of: 2) == false
        }
    }
}
#endif

public struct AvatarView: View {
    private let title: String
    private let subtitle: String?
    private let size: CGFloat
    private let isOnline: Bool?
    private let presence: Presence?
    private let imageData: Data?

    public init(title: String, subtitle: String? = nil, size: CGFloat = StoatSize.avatar, isOnline: Bool? = nil, presence: Presence? = nil, imageData: Data? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.isOnline = isOnline
        self.presence = presence
        self.imageData = imageData
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
            if presence != nil || isOnline != nil {
                PresenceDot(presence: presence, isOnline: isOnline)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }

    @ViewBuilder private var avatarContent: some View {
        #if canImport(AppKit)
        if let imageData {
            DecodedDataImage(data: imageData, pixelSize: Int(max(64, size * 2)))
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: min(StoatRadius.avatar, size / 4), style: .continuous))
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: min(StoatRadius.avatar, size / 4), style: .continuous)
            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.78), Color.pink.opacity(0.52)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(StoatInitials.make(title))
                    .font(.system(size: max(11, size * 0.36), weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

public struct ServerIconView: View {
    private let name: String
    private let isSelected: Bool
    private let imageData: Data?

    public init(name: String, isSelected: Bool = false, imageData: Data? = nil) {
        self.name = name
        self.isSelected = isSelected
        self.imageData = imageData
    }

    public var body: some View {
        content
            .frame(width: StoatSize.serverIcon, height: StoatSize.serverIcon)
    }

    @ViewBuilder private var content: some View {
        #if canImport(AppKit)
        if let imageData {
            DecodedDataImage(data: imageData, pixelSize: Int(StoatSize.serverIcon * 2))
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: isSelected ? 15 : StoatRadius.avatar, style: .continuous))
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: isSelected ? 15 : StoatRadius.avatar, style: .continuous)
            .fill(LinearGradient(colors: [Color.cyan.opacity(0.82), Color.indigo.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(StoatInitials.make(name, fallback: "S"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
    }
}

public struct UnreadBadge: View {
    private let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            Text(StoatBadges.displayCount(count))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.blue, in: Capsule())
                .accessibilityLabel(StoatBadges.unreadAccessibilityLabel(count: count))
        }
    }
}

public struct MentionBadge: View {
    private let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            Text(StoatBadges.displayCount(count))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.red, in: Capsule())
                .accessibilityLabel(StoatBadges.mentionAccessibilityLabel(count: count))
        }
    }
}

public struct PresenceDot: View {
    private let presence: Presence?
    private let isOnline: Bool?

    public init(isOnline: Bool) {
        self.presence = nil
        self.isOnline = isOnline
    }

    public init(presence: Presence?, isOnline: Bool? = nil) {
        self.presence = presence
        self.isOnline = isOnline
    }

    public var body: some View {
        Circle()
            .fill(Self.resolve(presence: presence, isOnline: isOnline).color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
            .accessibilityLabel(Self.resolve(presence: presence, isOnline: isOnline).label)
    }

    /// `presence` (`User.status.presence`) is the user's *configured* status and persists
    /// while they're offline, so it must not be trusted on its own: an offline user with a
    /// stored "Online" presence would otherwise render a green dot. When `isOnline` is known
    /// to be `false`, always render offline styling regardless of `presence`. When `isOnline`
    /// is `nil` (some call sites don't know), fall back to presence-first styling.
    static func resolve(presence: Presence?, isOnline: Bool?) -> (color: Color, label: String) {
        if isOnline == false {
            return (.secondary, "Offline")
        }
        switch presence {
        case .online:
            return (.green, Presence.online.displayName)
        case .idle:
            return (.orange, Presence.idle.displayName)
        case .focus:
            return (.blue, Presence.focus.displayName)
        case .busy:
            return (.red, Presence.busy.displayName)
        case .invisible:
            return (.secondary, Presence.invisible.displayName)
        case let .unknown(value):
            return isOnline == true ? (.green, "Online") : (.secondary, Presence.unknown(value).displayName)
        case nil:
            return isOnline == true ? (.green, "Online") : (.secondary, "Offline")
        }
    }
}

public struct EmptyStateView: View {
    private let title: String
    private let message: String
    private let systemImage: String

    public init(title: String, message: String, systemImage: String = "bubble.left.and.bubble.right") {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: StoatSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(StoatSpacing.xxLarge)
    }
}

public struct LoadingStateView: View {
    public init() {}
    public var body: some View {
        ProgressView("Loading")
            .padding(StoatSpacing.xLarge)
    }
}

public struct ErrorStateView: View {
    private let message: String
    public init(_ message: String) { self.message = message }
    public var body: some View {
        EmptyStateView(title: "Something went sideways", message: message, systemImage: "exclamationmark.triangle")
    }
}

public enum TimelineSkeletonAnimationPolicy {
    public static func usesShimmer(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

public struct TimelineSkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let showsAvatar: Bool

    public init(showsAvatar: Bool = true) {
        self.showsAvatar = showsAvatar
    }

    public var body: some View {
        HStack(alignment: .top, spacing: StoatSpacing.medium) {
            Circle()
                .fill(Color.secondary.opacity(0.14))
                .frame(width: StoatSize.avatar, height: StoatSize.avatar)
                .opacity(showsAvatar ? 1 : 0)
            VStack(alignment: .leading, spacing: StoatSpacing.small) {
                RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 156, height: 11)
                RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                    .fill(Color.secondary.opacity(0.11))
                    .frame(maxWidth: 420)
                    .frame(height: 10)
            }
            .padding(.top, StoatSpacing.xSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            #if canImport(AppKit)
            TimelineCoreAnimationShimmer(isActive: TimelineSkeletonAnimationPolicy.usesShimmer(reduceMotion: reduceMotion))
                .mask {
                    HStack(alignment: .top, spacing: StoatSpacing.medium) {
                        Circle()
                            .frame(width: StoatSize.avatar, height: StoatSize.avatar)
                            .opacity(showsAvatar ? 1 : 0)
                        VStack(alignment: .leading, spacing: StoatSpacing.small) {
                            RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                                .frame(width: 156, height: 11)
                            RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                                .frame(maxWidth: 420)
                                .frame(height: 10)
                        }
                        .padding(.top, StoatSpacing.xSmall)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            #endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing message")
    }
}

#if canImport(AppKit)
private struct TimelineCoreAnimationShimmer: NSViewRepresentable {
    var isActive: Bool

    func makeNSView(context: Context) -> TimelineShimmerHostView {
        let view = TimelineShimmerHostView()
        view.setActive(isActive)
        return view
    }

    func updateNSView(_ nsView: TimelineShimmerHostView, context: Context) {
        nsView.setActive(isActive)
    }

    static func dismantleNSView(_ nsView: TimelineShimmerHostView, coordinator: ()) {
        nsView.stop()
    }
}

private final class TimelineShimmerHostView: NSView {
    private let shimmerLayer = CAGradientLayer()
    private var isActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        shimmerLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.24).cgColor,
            NSColor.clear.cgColor
        ]
        shimmerLayer.locations = [0, 0.5, 1]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(shimmerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        shimmerLayer.frame = bounds.insetBy(dx: -bounds.width, dy: 0)
        if isActive {
            start()
        }
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard bounds.width > 0 else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -bounds.width
        animation.toValue = bounds.width
        animation.duration = 1.15
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerLayer.add(animation, forKey: "phase60-shimmer")
    }

    func stop() {
        isActive = false
        shimmerLayer.removeAllAnimations()
    }
}
#endif

private final class MessageRowStorage {
    let message: Message
    let author: User?
    let authorDisplayNameOverride: String?
    let authorDisplayColor: RoleColorValue?
    let showsHeader: Bool
    let statusText: String?
    let isSelected: Bool
    let isFocused: Bool
    let isSearchHighlighted: Bool
    let isCurrentSearchResult: Bool
    let isTargetHighlighted: Bool
    let isCompactDensity: Bool
    let searchAccessibilityStatus: String?
    let replyPreview: String?
    let replyPreviewItem: MessageRowReplyPreviewItem?
    let attachmentItems: [AttachmentDisplayItem]?
    let customEmojiItems: [MessageInlineCustomEmojiItem]
    let referenceItems: [String: MessageInlineReferenceItem]
    let preparedMarkdownContent: PreparedMarkdownContent?
    let embedItems: [MessageEmbedDisplayItem]?
    let authorAvatarData: Data?
    let actionItems: [MessageRowActionItem]
    let reactionItems: [MessageReactionDisplayItem]
    let mentionsCurrentUser: Bool
    let onMessageAction: (String) -> Void
    let onToggleReaction: (String) -> Void
    let onPreviewAttachment: (AttachmentDisplayItem) -> Void
    let onDownloadAttachment: (AttachmentDisplayItem) -> Void
    let onOpenAttachment: (AttachmentDisplayItem) -> Void
    let onRetryAttachment: (AttachmentDisplayItem) -> Void
    let onPreviewEmbedMedia: (AttachmentDisplayItem) -> Void
    let onDownloadEmbedMedia: (AttachmentDisplayItem) -> Void
    let onOpenEmbedMedia: (AttachmentDisplayItem) -> Void
    let onRetryEmbedMedia: (AttachmentDisplayItem) -> Void
    let onOpenAuthorProfile: () -> Void
    let onOpenReplyPreview: () -> Void
    let onOpenMention: (UserID) -> Void

    init(
        message: Message,
        author: User?,
        authorDisplayNameOverride: String?,
        authorDisplayColor: RoleColorValue?,
        showsHeader: Bool,
        statusText: String?,
        isSelected: Bool,
        isFocused: Bool,
        isSearchHighlighted: Bool,
        isCurrentSearchResult: Bool,
        isTargetHighlighted: Bool,
        isCompactDensity: Bool,
        searchAccessibilityStatus: String?,
        replyPreview: String?,
        replyPreviewItem: MessageRowReplyPreviewItem?,
        attachmentItems: [AttachmentDisplayItem]?,
        customEmojiItems: [MessageInlineCustomEmojiItem],
        referenceItems: [String: MessageInlineReferenceItem],
        preparedMarkdownContent: PreparedMarkdownContent?,
        embedItems: [MessageEmbedDisplayItem]?,
        authorAvatarData: Data?,
        actionItems: [MessageRowActionItem],
        reactionItems: [MessageReactionDisplayItem],
        mentionsCurrentUser: Bool,
        onMessageAction: @escaping (String) -> Void,
        onToggleReaction: @escaping (String) -> Void,
        onPreviewAttachment: @escaping (AttachmentDisplayItem) -> Void,
        onDownloadAttachment: @escaping (AttachmentDisplayItem) -> Void,
        onOpenAttachment: @escaping (AttachmentDisplayItem) -> Void,
        onRetryAttachment: @escaping (AttachmentDisplayItem) -> Void,
        onPreviewEmbedMedia: @escaping (AttachmentDisplayItem) -> Void,
        onDownloadEmbedMedia: @escaping (AttachmentDisplayItem) -> Void,
        onOpenEmbedMedia: @escaping (AttachmentDisplayItem) -> Void,
        onRetryEmbedMedia: @escaping (AttachmentDisplayItem) -> Void,
        onOpenAuthorProfile: @escaping () -> Void,
        onOpenReplyPreview: @escaping () -> Void,
        onOpenMention: @escaping (UserID) -> Void
    ) {
        self.message = message
        self.author = author
        self.authorDisplayNameOverride = authorDisplayNameOverride
        self.authorDisplayColor = authorDisplayColor
        self.showsHeader = showsHeader
        self.statusText = statusText
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isSearchHighlighted = isSearchHighlighted
        self.isCurrentSearchResult = isCurrentSearchResult
        self.isTargetHighlighted = isTargetHighlighted
        self.isCompactDensity = isCompactDensity
        self.searchAccessibilityStatus = searchAccessibilityStatus
        self.replyPreview = replyPreview
        self.replyPreviewItem = replyPreviewItem
        self.attachmentItems = attachmentItems
        self.customEmojiItems = customEmojiItems
        self.referenceItems = referenceItems
        self.preparedMarkdownContent = preparedMarkdownContent
        self.embedItems = embedItems
        self.authorAvatarData = authorAvatarData
        self.actionItems = actionItems
        self.reactionItems = reactionItems
        self.mentionsCurrentUser = mentionsCurrentUser
        self.onMessageAction = onMessageAction
        self.onToggleReaction = onToggleReaction
        self.onPreviewAttachment = onPreviewAttachment
        self.onDownloadAttachment = onDownloadAttachment
        self.onOpenAttachment = onOpenAttachment
        self.onRetryAttachment = onRetryAttachment
        self.onPreviewEmbedMedia = onPreviewEmbedMedia
        self.onDownloadEmbedMedia = onDownloadEmbedMedia
        self.onOpenEmbedMedia = onOpenEmbedMedia
        self.onRetryEmbedMedia = onRetryEmbedMedia
        self.onOpenAuthorProfile = onOpenAuthorProfile
        self.onOpenReplyPreview = onOpenReplyPreview
        self.onOpenMention = onOpenMention
    }
}

public struct MessageRow: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false
    private let storage: MessageRowStorage
    private var message: Message { storage.message }
    private var author: User? { storage.author }
    private var authorDisplayNameOverride: String? { storage.authorDisplayNameOverride }
    private var authorDisplayColor: RoleColorValue? { storage.authorDisplayColor }
    private var showsHeader: Bool { storage.showsHeader }
    private var statusText: String? { storage.statusText }
    private var isSelected: Bool { storage.isSelected }
    private var isFocused: Bool { storage.isFocused }
    private var isSearchHighlighted: Bool { storage.isSearchHighlighted }
    private var isCurrentSearchResult: Bool { storage.isCurrentSearchResult }
    private var isTargetHighlighted: Bool { storage.isTargetHighlighted }
    private var isCompactDensity: Bool { storage.isCompactDensity }
    private var searchAccessibilityStatus: String? { storage.searchAccessibilityStatus }
    private var replyPreview: String? { storage.replyPreview }
    private var replyPreviewItem: MessageRowReplyPreviewItem? { storage.replyPreviewItem }
    private var attachmentItems: [AttachmentDisplayItem]? { storage.attachmentItems }
    private var customEmojiItems: [MessageInlineCustomEmojiItem] { storage.customEmojiItems }
    private var referenceItems: [String: MessageInlineReferenceItem] { storage.referenceItems }
    private var preparedMarkdownContent: PreparedMarkdownContent? { storage.preparedMarkdownContent }
    private var embedItems: [MessageEmbedDisplayItem]? { storage.embedItems }
    private var authorAvatarData: Data? { storage.authorAvatarData }
    private var actionItems: [MessageRowActionItem] { storage.actionItems }
    private var reactionItems: [MessageReactionDisplayItem] { storage.reactionItems }
    private var mentionsCurrentUser: Bool { storage.mentionsCurrentUser }
    private var onMessageAction: (String) -> Void { storage.onMessageAction }
    private var onToggleReaction: (String) -> Void { storage.onToggleReaction }
    private var onPreviewAttachment: (AttachmentDisplayItem) -> Void { storage.onPreviewAttachment }
    private var onDownloadAttachment: (AttachmentDisplayItem) -> Void { storage.onDownloadAttachment }
    private var onOpenAttachment: (AttachmentDisplayItem) -> Void { storage.onOpenAttachment }
    private var onRetryAttachment: (AttachmentDisplayItem) -> Void { storage.onRetryAttachment }
    private var onPreviewEmbedMedia: (AttachmentDisplayItem) -> Void { storage.onPreviewEmbedMedia }
    private var onDownloadEmbedMedia: (AttachmentDisplayItem) -> Void { storage.onDownloadEmbedMedia }
    private var onOpenEmbedMedia: (AttachmentDisplayItem) -> Void { storage.onOpenEmbedMedia }
    private var onRetryEmbedMedia: (AttachmentDisplayItem) -> Void { storage.onRetryEmbedMedia }
    private var onOpenAuthorProfile: () -> Void { storage.onOpenAuthorProfile }
    private var onOpenReplyPreview: () -> Void { storage.onOpenReplyPreview }
    private var onOpenMention: (UserID) -> Void { storage.onOpenMention }

    public init(
        message: Message,
        author: User?,
        authorDisplayNameOverride: String? = nil,
        authorDisplayColor: RoleColorValue? = nil,
        showsHeader: Bool = true,
        statusText: String? = nil,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isSearchHighlighted: Bool = false,
        isCurrentSearchResult: Bool = false,
        isTargetHighlighted: Bool = false,
        isCompactDensity: Bool = false,
        searchAccessibilityStatus: String? = nil,
        replyPreview: String? = nil,
        replyPreviewItem: MessageRowReplyPreviewItem? = nil,
        attachmentItems: [AttachmentDisplayItem]? = nil,
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        referenceItems: [String: MessageInlineReferenceItem] = [:],
        preparedMarkdownContent: PreparedMarkdownContent? = nil,
        embedItems: [MessageEmbedDisplayItem]? = nil,
        authorAvatarData: Data? = nil,
        actionItems: [MessageRowActionItem] = [],
        reactionItems: [MessageReactionDisplayItem] = [],
        mentionsCurrentUser: Bool = false,
        onMessageAction: @escaping (String) -> Void = { _ in },
        onToggleReaction: @escaping (String) -> Void = { _ in },
        onPreviewAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onDownloadAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onOpenAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onRetryAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onPreviewEmbedMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onDownloadEmbedMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onOpenEmbedMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onRetryEmbedMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onOpenAuthorProfile: @escaping () -> Void = {},
        onOpenReplyPreview: @escaping () -> Void = {},
        onOpenMention: @escaping (UserID) -> Void = { _ in }
    ) {
        self.storage = MessageRowStorage(
            message: message,
            author: author,
            authorDisplayNameOverride: authorDisplayNameOverride,
            authorDisplayColor: authorDisplayColor,
            showsHeader: showsHeader,
            statusText: statusText,
            isSelected: isSelected,
            isFocused: isFocused,
            isSearchHighlighted: isSearchHighlighted,
            isCurrentSearchResult: isCurrentSearchResult,
            isTargetHighlighted: isTargetHighlighted,
            isCompactDensity: isCompactDensity,
            searchAccessibilityStatus: searchAccessibilityStatus,
            replyPreview: replyPreview,
            replyPreviewItem: replyPreviewItem,
            attachmentItems: attachmentItems,
            customEmojiItems: customEmojiItems,
            referenceItems: referenceItems,
            preparedMarkdownContent: preparedMarkdownContent,
            embedItems: embedItems,
            authorAvatarData: authorAvatarData,
            actionItems: actionItems,
            reactionItems: reactionItems,
            mentionsCurrentUser: mentionsCurrentUser,
            onMessageAction: onMessageAction,
            onToggleReaction: onToggleReaction,
            onPreviewAttachment: onPreviewAttachment,
            onDownloadAttachment: onDownloadAttachment,
            onOpenAttachment: onOpenAttachment,
            onRetryAttachment: onRetryAttachment,
            onPreviewEmbedMedia: onPreviewEmbedMedia,
            onDownloadEmbedMedia: onDownloadEmbedMedia,
            onOpenEmbedMedia: onOpenEmbedMedia,
            onRetryEmbedMedia: onRetryEmbedMedia,
            onOpenAuthorProfile: onOpenAuthorProfile,
            onOpenReplyPreview: onOpenReplyPreview,
            onOpenMention: onOpenMention
        )
    }

    public var body: some View {
        let searchStyle = SearchHighlightStyle(
            isHighlighted: isSearchHighlighted,
            isCurrent: isCurrentSearchResult,
            highContrast: colorSchemeContrast == .increased,
            reduceTransparency: reduceTransparency,
            compactDensity: isCompactDensity
        )
        HStack(alignment: .top, spacing: StoatSpacing.medium) {
            if showsHeader {
                Button(action: onOpenAuthorProfile) {
                    AvatarView(title: authorName, size: StoatSize.avatar, isOnline: author?.online, presence: author?.status?.presence, imageData: authorAvatarData)
                }
                .buttonStyle(.plain)
                .help("Open Profile")
            } else {
                Text(timestampText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: StoatSize.avatar)
                    .opacity(0.75)
            }
            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                if showsHeader {
                    HStack(spacing: StoatSpacing.small) {
                        Button(action: onOpenAuthorProfile) {
                            Text(authorName)
                                .font(StoatTypography.messageAuthor)
                                .foregroundStyle(authorDisplayColor?.foregroundStyle ?? AnyShapeStyle(.primary))
                        }
                        .buttonStyle(.plain)
                        .help("Open Profile")
                        Text(timestampText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if message.isEdited {
                            Text("edited")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if message.isPinned {
                            Label("Pinned", systemImage: "pin.fill")
                                .labelStyle(.iconOnly)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("pinned")
                        }
                    }
                }
                if let system = message.system {
                    SystemEventRow(text: system.content ?? "System event")
                }
                if let replyPreviewItem = effectiveReplyPreviewItem {
                    replyPreviewView(replyPreviewItem)
                }
                if let content = message.content, !content.isEmpty {
                    if let preparedMarkdownContent {
                        MarkdownMessageContent(
                            prepared: preparedMarkdownContent,
                            customEmojiItems: customEmojiItems,
                            referenceItems: referenceItems,
                            onOpenMention: onOpenMention
                        )
                    } else {
                        MarkdownMessageContent(content, customEmojiItems: customEmojiItems, referenceItems: referenceItems, onOpenMention: onOpenMention)
                    }
                }
                let renderedAttachments = attachmentItems ?? message.attachments?.map { AttachmentDisplayItem(file: $0) } ?? []
                if !renderedAttachments.isEmpty {
                    ForEach(renderedAttachments) { attachment in
                        AttachmentTimelineCard(
                            item: attachment,
                            isCompact: isCompactDensity,
                            onPreview: { onPreviewAttachment(attachment) },
                            onDownload: { onDownloadAttachment(attachment) },
                            onOpenExternally: { onOpenAttachment(attachment) },
                            onRetry: { onRetryAttachment(attachment) }
                        )
                    }
                }
                let renderedEmbeds = embedItems ?? fallbackEmbedItems
                if !renderedEmbeds.isEmpty {
                    ForEach(renderedEmbeds) { embed in
                        EmbedTimelineCard(
                            item: embed,
                            isCompact: isCompactDensity,
                            onPreviewMedia: { onPreviewEmbedMedia($0) },
                            onDownloadMedia: { onDownloadEmbedMedia($0) },
                            onOpenMedia: { onOpenEmbedMedia($0) },
                            onRetryMedia: { onRetryEmbedMedia($0) }
                        )
                    }
                }
                let renderedReactions = reactionItems.isEmpty ? fallbackReactionItems : reactionItems
                if !renderedReactions.isEmpty {
                    HStack(spacing: StoatSpacing.small) {
                        ForEach(renderedReactions) { reaction in
                            Button {
                                onToggleReaction(reaction.emoji)
                            } label: {
                                HStack(spacing: StoatSpacing.xxSmall) {
                                    ReactionEmojiLabel(reaction: reaction)
                                    Text("\(reaction.count)")
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, StoatSpacing.small)
                                .padding(.vertical, StoatSpacing.xSmall)
                                .background(reaction.hasCurrentUserReacted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(StoatAccessibility.reactionLabel(emoji: reaction.emoji, count: reaction.count, hasReacted: reaction.hasCurrentUserReacted))
                        }
                    }
                    .padding(.top, StoatSpacing.xSmall)
                }
            }
            Spacer(minLength: StoatSpacing.small)
        }
        .padding(.trailing, actionBarTrailingReservation)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering != isHovering else { return }
            withAnimation(.easeOut(duration: MessageRowActionLayout.hoverFadeDuration)) {
                isHovering = hovering
            }
        }
        .overlay(alignment: .topTrailing) {
            Group {
                if showsActionAffordance {
                    messageActionBar
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(allowsActionAffordanceInteraction)
            .accessibilityHidden(!allowsActionAffordanceInteraction)
        }
        .padding(.vertical, (showsHeader ? StoatSpacing.small : StoatSpacing.xxSmall) + searchStyle.verticalPaddingAdjustment)
        .background(searchBackground(searchStyle), in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        .overlay {
            if searchStyle.isHighlighted {
                RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous)
                    .strokeBorder(Color.orange.opacity(searchStyle.borderOpacity), lineWidth: searchStyle.borderWidth)
            }
            if isFocused {
                RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
            if isTargetHighlighted {
                RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.72), lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if mentionsCurrentUser && !searchStyle.isHighlighted {
                RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous)
                    .fill(Color.yellow.opacity(0.65))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StoatAccessibility.messageLabel(author: authorName, timestamp: timestampText, content: message.content ?? message.system?.content ?? "", isEdited: message.isEdited, isPinned: message.isPinned, reactionCount: reactionCount, status: statusText, isSelected: isSelected, isFocused: isFocused || isTargetHighlighted, searchResultStatus: searchAccessibilityStatus, replyPreview: effectiveReplyPreviewItem?.plainText, mentionsCurrentUser: mentionsCurrentUser))
    }

    private var effectiveReplyPreviewItem: MessageRowReplyPreviewItem? {
        if let replyPreviewItem { return replyPreviewItem }
        return replyPreview.map {
            MessageRowReplyPreviewItem(id: "legacy-\(message.id.rawValue)", summary: $0, canOpen: false)
        }
    }

    @ViewBuilder private func replyPreviewView(_ item: MessageRowReplyPreviewItem) -> some View {
        let content = HStack(spacing: StoatSpacing.xSmall) {
            Image(systemName: item.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let authorName = item.authorName, !authorName.isEmpty {
                Text(authorName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, StoatSpacing.small)
        .padding(.vertical, StoatSpacing.xxSmall)
        .background(item.canOpen ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))

        if item.canOpen {
            Button(action: onOpenReplyPreview) {
                content
            }
            .buttonStyle(.plain)
            .help("Jump to original message")
            .accessibilityLabel(item.accessibilityLabel)
        } else {
            content
                .accessibilityLabel(item.accessibilityLabel)
        }
    }

    @ViewBuilder private var messageActionBar: some View {
        HStack(spacing: StoatSpacing.xxSmall) {
            ForEach(primaryActionItems.prefix(3)) { item in
                actionButton(item)
            }
            if !actionItems.isEmpty {
                Menu {
                    ForEach(actionItems) { item in
                        Button(role: buttonRole(for: item)) {
                            onMessageAction(item.id)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                        .disabled(!item.isEnabled)
                        .accessibilityLabel(StoatAccessibility.messageActionLabel(title: item.title, isDestructive: item.role == .destructive, isEnabled: item.isEnabled))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .accessibilityLabel("More message actions")
            }
        }
        .padding(.horizontal, StoatSpacing.xxSmall)
        .padding(.vertical, StoatSpacing.xxSmall)
        .background(Color.primary.opacity(reduceTransparency ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
    }

    private func actionButton(_ item: MessageRowActionItem) -> some View {
        Button(role: buttonRole(for: item)) {
            onMessageAction(item.id)
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(!item.isEnabled)
        .help(item.title)
        .accessibilityLabel(StoatAccessibility.messageActionLabel(title: item.title, isDestructive: item.role == .destructive, isEnabled: item.isEnabled))
    }

    private var primaryActionItems: [MessageRowActionItem] {
        actionItems.filter { $0.isPrimary && $0.isEnabled }
    }

    private var actionBarTrailingReservation: CGFloat {
        MessageRowActionLayout.trailingReservation(
            primaryActionCount: primaryActionItems.count,
            hasMenu: !actionItems.isEmpty
        )
    }

    private var showsActionAffordance: Bool {
        MessageRowActionLayout.shouldMountActionBar(
            hasActions: !actionItems.isEmpty,
            isHovering: isHovering,
            isFocused: isFocused,
            isSelected: isSelected
        )
    }

    private var allowsActionAffordanceInteraction: Bool {
        MessageRowActionLayout.allowsActionBarInteraction(
            hasActions: !actionItems.isEmpty,
            isHovering: isHovering,
            isFocused: isFocused,
            isSelected: isSelected
        )
    }

    private var fallbackReactionItems: [MessageReactionDisplayItem] {
        message.reactions
            .filter { !$0.value.isEmpty }
            .map { MessageReactionDisplayItem(emoji: $0.key, count: $0.value.count, hasCurrentUserReacted: false) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.emoji < rhs.emoji }
                return lhs.count > rhs.count
            }
    }

    private var fallbackEmbedItems: [MessageEmbedDisplayItem] {
        (message.embeds ?? []).enumerated().map { index, embed in
            MessageEmbedDisplayItem(
                id: "embed-\(message.id.rawValue)-\(index)",
                embed: embed,
                mediaItem: embed.media.map { AttachmentDisplayItem(file: $0) }
            )
        }
    }

    private var reactionCount: Int {
        let renderedReactions = reactionItems.isEmpty ? fallbackReactionItems : reactionItems
        return renderedReactions.reduce(0) { $0 + $1.count }
    }

    private func buttonRole(for item: MessageRowActionItem) -> ButtonRole? {
        item.role == .destructive ? .destructive : nil
    }

    private func searchBackground(_ searchStyle: SearchHighlightStyle) -> Color {
        if searchStyle.isHighlighted {
            return Color.orange.opacity(searchStyle.fillOpacity)
        }
        if isSelected || isFocused {
            return Color.accentColor.opacity(isFocused ? 0.16 : 0.10)
        }
        if mentionsCurrentUser {
            return Color.yellow.opacity(0.08)
        }
        return Color.clear
    }

    private var authorName: String {
        message.masquerade?.name ?? authorDisplayNameOverride ?? author?.displayName ?? author?.username ?? shortenedAuthorID
    }

    private var shortenedAuthorID: String {
        let raw = message.authorID.rawValue
        guard raw.count > 10 else { return raw }
        return "\(raw.prefix(4))...\(raw.suffix(4))"
    }

    private var timestampText: String {
        guard let date = message.createdAt else { return "now" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct ReactionEmojiLabel: View {
    let reaction: MessageReactionDisplayItem

    var body: some View {
        #if canImport(AppKit)
        if let data = reaction.customEmojiImageData {
            DecodedDataImage(data: data, pixelSize: 32)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityLabel(reaction.customEmojiName ?? reaction.emoji)
        } else {
            Text(reaction.customEmojiName.map { ":\($0):" } ?? reaction.emoji)
        }
        #else
        Text(reaction.customEmojiName.map { ":\($0):" } ?? reaction.emoji)
        #endif
    }
}

public struct MessageGroupView<GroupID: Hashable>: View {
    private let id: GroupID
    private let messages: [Message]
    private let author: User?

    public init(id: GroupID, messages: [Message], author: User?) {
        self.id = id
        self.messages = messages
        self.author = author
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                MessageRow(message: message, author: author, showsHeader: index == 0)
            }
        }
        .id(id)
    }
}

public struct AttachmentPreviewPlaceholder: View {
    private let attachment: File
    public init(title: String) {
        self.attachment = File(id: FileID(rawValue: title), tag: "attachments", filename: title, contentType: "application/octet-stream", size: 0)
    }
    public init(attachment: File) {
        self.attachment = attachment
    }
    public var body: some View {
        AttachmentTimelineCard(item: AttachmentDisplayItem(file: attachment))
    }
}

#if canImport(AVKit)
struct VideoPosterDiagnostics: Hashable, Sendable {
    var cacheCount: Int
    var byteCount: Int
    var inFlightCount: Int
}

actor VideoPosterStore {
    static let shared = VideoPosterStore()

    private var posters: [URL: Data] = [:]
    private var order: [URL] = []
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private var byteCount = 0
    private let maxEntries: Int
    private let maxBytes: Int

    init(maxEntries: Int = 40, maxBytes: Int = 16 * 1024 * 1024) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
    }

    func poster(for url: URL) async -> Data? {
        if let data = posters[url] {
            order.removeAll { $0 == url }
            order.append(url)
            return data
        }
        if let task = inFlight[url] {
            return await task.value
        }
        let task = Task.detached(priority: .utility) {
            await Self.generatePoster(for: url)
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if let data {
            insert(data, for: url)
        }
        return data
    }

    func insert(_ data: Data, for url: URL) {
        if let previous = posters[url] {
            byteCount -= previous.count
        }
        posters[url] = data
        byteCount += data.count
        order.removeAll { $0 == url }
        order.append(url)
        while (order.count > maxEntries || byteCount > maxBytes), let oldest = order.first {
            order.removeFirst()
            if let removed = posters.removeValue(forKey: oldest) {
                byteCount -= removed.count
            }
        }
    }

    func cachedPoster(for url: URL) -> Data? {
        posters[url]
    }

    func diagnostics() -> VideoPosterDiagnostics {
        VideoPosterDiagnostics(cacheCount: posters.count, byteCount: byteCount, inFlightCount: inFlight.count)
    }

    private nonisolated static func generatePoster(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_160, height: 760)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        do {
            let result = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            let representation = NSBitmapImageRep(cgImage: result.image)
            return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
        } catch {
            return nil
        }
    }
}

public struct VideoAttachmentPlayer: View {
    private let url: URL
    private let isCompact: Bool
    private let maxWidth: CGFloat
    private let height: CGFloat
    @State private var player: AVPlayer?
    @State private var posterData: Data?

    public init(url: URL, isCompact: Bool = false, maxWidth: CGFloat? = nil, height: CGFloat? = nil) {
        self.url = url
        self.isCompact = isCompact
        self.maxWidth = maxWidth ?? (isCompact ? 430 : 580)
        self.height = height ?? (isCompact ? 260 : 380)
    }

    public var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Button {
                    let player = AVPlayer(url: url)
                    self.player = player
                    player.play()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                        if let posterData {
                            DecodedDataImage(data: posterData, pixelSize: 1_160)
                                .scaledToFill()
                                .overlay(Color.black.opacity(0.28))
                        }
                        VStack(spacing: StoatSpacing.small) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44))
                            Text("Play video")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: maxWidth)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .task(id: url) {
            guard player == nil else { return }
            posterData = nil
            posterData = await VideoPosterStore.shared.poster(for: url)
        }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
        .accessibilityLabel(player == nil ? "Play video" : "Video player")
    }
}
#endif

public struct AttachmentTimelineCard: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let item: AttachmentDisplayItem
    private let isCompact: Bool
    private let onPreview: () -> Void
    private let onDownload: () -> Void
    private let onOpenExternally: () -> Void
    private let onRetry: () -> Void

    public init(
        item: AttachmentDisplayItem,
        isCompact: Bool = false,
        onPreview: @escaping () -> Void = {},
        onDownload: @escaping () -> Void = {},
        onOpenExternally: @escaping () -> Void = {},
        onRetry: @escaping () -> Void = {}
    ) {
        self.item = item
        self.isCompact = isCompact
        self.onPreview = onPreview
        self.onDownload = onDownload
        self.onOpenExternally = onOpenExternally
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            inlineImagePreview
            inlineVideoPlayer
            HStack(spacing: StoatSpacing.small) {
                thumbnail
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    Text(item.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    stateLine
                }
                Spacer(minLength: StoatSpacing.small)
            }
            controls
        }
        .padding(isCompact ? StoatSpacing.small : StoatSpacing.medium)
        .frame(maxWidth: isCompact ? 460 : 620, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                .strokeBorder(borderColor, lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(StoatAccessibility.attachmentLabel(filename: item.displayName, kind: item.kind.label, size: AttachmentDisplayFormatting.formattedSize(item.byteCount), state: item.previewState.safeLabel))
    }

    @ViewBuilder private var inlineImagePreview: some View {
        #if canImport(AppKit)
        if item.kind == .image,
           item.previewState.isReady,
           let data = item.previewData {
            Button(action: onPreview) {
                DecodedDataImage(data: data, pixelSize: isCompact ? 860 : 1160)
                    .scaledToFit()
                    .frame(maxWidth: isCompact ? 430 : 580, maxHeight: isCompact ? 260 : 380, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open image \(item.displayName)")
        }
        #endif
    }

    @ViewBuilder private var inlineVideoPlayer: some View {
        #if canImport(AVKit)
        if item.kind == .video, let url = item.playbackURL {
            VideoAttachmentPlayer(url: url, isCompact: isCompact)
        }
        #endif
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous)
                .fill(Color.primary.opacity(reduceTransparency ? 0.10 : 0.06))
            thumbnailContent
            if case .loading = item.previewState {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(width: isCompact ? 34 : 44, height: isCompact ? 34 : 44)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var thumbnailContent: some View {
        #if canImport(AppKit)
        if item.kind == .image,
           let data = item.previewData {
            DecodedDataImage(data: data, pixelSize: isCompact ? 68 : 88)
                .scaledToFill()
                .frame(width: isCompact ? 34 : 44, height: isCompact ? 34 : 44)
                .clipShape(RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
        } else {
            fallbackThumbnailIcon
        }
        #else
        fallbackThumbnailIcon
        #endif
    }

    private var fallbackThumbnailIcon: some View {
        Image(systemName: item.kind.systemImage)
            .font(.system(size: isCompact ? 16 : 20, weight: .semibold))
            .foregroundStyle(iconColor)
    }

    @ViewBuilder private var stateLine: some View {
        switch item.previewState {
        case .notLoaded, .readyLocal, .readyRemote:
            EmptyView()
        case .loading:
            Text("Loading preview")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        case let .unsupported(message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: StoatSpacing.xSmall) {
            if showsPreview {
                Button {
                    onPreview()
                } label: {
                    Label(previewTitle, systemImage: "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(StoatAccessibility.attachmentActionLabel(action: previewTitle, filename: item.displayName))
            }
            if item.source.isRemoteLoadable {
                Button {
                    onDownload()
                } label: {
                    Label("Save As", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(StoatAccessibility.attachmentActionLabel(action: "Save As", filename: item.displayName))
            }
            if item.previewState.isReady {
                Button {
                    onOpenExternally()
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(StoatAccessibility.attachmentActionLabel(action: "Open Externally", filename: item.displayName))
            }
            if case .failed = item.previewState {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(StoatAccessibility.attachmentActionLabel(action: "Retry preview", filename: item.displayName))
            }
        }
        .font(.caption)
    }

    private var subtitle: String {
        let type = item.contentType ?? item.kind.label
        return "\(item.kind.label) · \(type) · \(AttachmentDisplayFormatting.formattedSize(item.byteCount))"
    }

    private var showsPreview: Bool {
        switch item.previewState {
        case .unsupported:
            false
        case .loading:
            false
        case .notLoaded, .readyLocal, .readyRemote, .failed:
            item.kind.isPreviewable || item.previewState.isReady
        }
    }

    private var previewTitle: String {
        if item.previewState.isReady { return "Preview" }
        return item.kind == .image ? "Load Image" : "Load Preview"
    }

    private var backgroundColor: Color {
        if colorSchemeContrast == .increased {
            return Color.primary.opacity(0.10)
        }
        return Color.primary.opacity(reduceTransparency ? 0.09 : 0.055)
    }

    private var borderColor: Color {
        if colorSchemeContrast == .increased {
            return Color.primary.opacity(0.35)
        }
        return Color.primary.opacity(0.08)
    }

    private var iconColor: Color {
        switch item.kind {
        case .unsupported:
            .secondary
        case .image:
            .accentColor
        case .video:
            .purple
        case .pdf:
            .red
        case .text:
            .blue
        case .archive:
            .orange
        case .generic:
            .secondary
        }
    }
}

private enum ComposerAttachmentDraftSafeName {
    static func sanitize(_ filename: String) -> String {
        let controlSet = CharacterSet.controlCharacters
        let scalars = URL(fileURLWithPath: filename).lastPathComponent.unicodeScalars.filter { !controlSet.contains($0) }
        let value = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "attachment" : value
    }
}

public struct SystemEventRow: View {
    private let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: StoatSpacing.small) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, StoatSpacing.xSmall)
        .accessibilityLabel(text)
    }
}


/// Line-metric geometry for the profile bio's collapsed disclosure, replacing the old magic
/// point constant so the collapse threshold tracks the actual rendered body-text line height.
public enum ProfileBioMetrics {
    /// The rendered line height of `StoatTypography.messageBody` (`Font.body`), taken from the
    /// same layout machinery AppKit-backed text uses.
    @MainActor public static var messageBodyLineHeight: CGFloat {
        #if canImport(AppKit)
        NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .body))
        #else
        17
        #endif
    }

    /// Pure so tests can drive it with injected metrics.
    public static func collapsedHeight(lineLimit: Int, lineHeight: CGFloat) -> CGFloat {
        (CGFloat(max(1, lineLimit)) * max(1, lineHeight)).rounded(.up)
    }
}

// MARK: - Role colour values (Phase 63)

/// One colour stop of a parsed role colour. Components are 0...1.
public struct CSSColorStop: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    /// 0...1 position along the gradient line; nil means "distribute like CSS does".
    public var location: Double?

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1, location: Double? = nil) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.location = location
    }
}

/// A role's parsed colour. Revolt's `role.colour` is any CSS background value; we support plain
/// colours and `linear-gradient(...)`, and treat everything else as colourless (matching the
/// pre-gradient behavior for unparseable values).
public enum RoleColorValue: Hashable, Sendable {
    case solid(CSSColorStop)
    /// CSS angle convention: 0deg points up, degrees increase clockwise.
    case linearGradient(angleDegrees: Double, stops: [CSSColorStop])

    /// The stop used wherever a single flat colour is required (mentions, chip backgrounds,
    /// diagnostics): the first gradient stop, or the solid colour itself.
    public var primaryStop: CSSColorStop {
        switch self {
        case let .solid(stop): return stop
        case let .linearGradient(_, stops): return stops[0]
        }
    }

    public var isGradient: Bool {
        if case .linearGradient = self { return true }
        return false
    }
}

/// Maps the CSS gradient angle convention onto SwiftUI's unit-square coordinates
/// (y grows downward): the gradient line passes through the centre pointing at `angleDegrees`.
public enum LinearGradientGeometry {
    public static func unitPoints(angleDegrees: Double) -> (start: UnitPoint, end: UnitPoint) {
        let radians = angleDegrees * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        return (
            start: UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2),
            end: UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
        )
    }
}

/// Parses the supported subset of CSS colour values used by Revolt role colours:
/// `#RGB` / `#RRGGBB` / `#RRGGBBAA`, `rgb()` / `rgba()`, and
/// `linear-gradient(<angle>deg | to <side/corner>, <stop>[, <stop>...])`.
/// Anything else (named colours, `var()`, conic/radial gradients, `url()`) returns nil.
public enum CSSRoleColorParser {
    public static func parse(_ raw: String) -> RoleColorValue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("linear-gradient(") {
            return parseLinearGradient(trimmed)
        }
        if let stop = parseColor(trimmed) {
            return .solid(stop)
        }
        return nil
    }

    public static func parseColor(_ raw: String) -> CSSColorStop? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            return parseHexColor(trimmed)
        }
        return parseFunctionalColor(trimmed)
    }

    public static func parseHexColor(_ raw: String) -> CSSColorStop? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        switch hex.count {
        case 3:
            let expanded = hex.map { "\($0)\($0)" }.joined()
            return parseSixDigitHex(expanded, alpha: 1)
        case 6:
            return parseSixDigitHex(hex, alpha: 1)
        case 8:
            guard let alphaByte = Int(hex.suffix(2), radix: 16) else { return nil }
            return parseSixDigitHex(String(hex.prefix(6)), alpha: Double(alphaByte) / 255)
        default:
            return nil
        }
    }

    public static func parseFunctionalColor(_ raw: String) -> CSSColorStop? {
        let lowered = raw.lowercased()
        let isRGBA = lowered.hasPrefix("rgba(")
        guard (lowered.hasPrefix("rgb(") || isRGBA), lowered.hasSuffix(")") else { return nil }
        let inner = raw.dropFirst(isRGBA ? 5 : 4).dropLast()
        // Accept both comma and space separated component syntax; "/" introduces alpha in the
        // space-separated form.
        let normalized = inner.replacingOccurrences(of: "/", with: " ")
        let components = normalized
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
        guard components.count == 3 || components.count == 4 else { return nil }
        func channel(_ value: String) -> Double? {
            if value.hasSuffix("%") {
                guard let percent = Double(value.dropLast()) else { return nil }
                return min(1, max(0, percent / 100))
            }
            guard let number = Double(value) else { return nil }
            return min(1, max(0, number / 255))
        }
        guard let red = channel(components[0]),
              let green = channel(components[1]),
              let blue = channel(components[2])
        else { return nil }
        var alpha: Double = 1
        if components.count == 4 {
            let value = components[3]
            if value.hasSuffix("%") {
                guard let percent = Double(value.dropLast()) else { return nil }
                alpha = min(1, max(0, percent / 100))
            } else {
                guard let number = Double(value) else { return nil }
                alpha = min(1, max(0, number))
            }
        }
        return CSSColorStop(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func parseLinearGradient(_ raw: String) -> RoleColorValue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("linear-gradient("), trimmed.hasSuffix(")") else { return nil }
        let inner = String(trimmed.dropFirst("linear-gradient(".count).dropLast())
        var arguments = splitTopLevelArguments(inner)
        guard !arguments.isEmpty else { return nil }

        var angleDegrees: Double = 180 // CSS default: "to bottom"
        if let direction = parseDirection(arguments[0]) {
            angleDegrees = direction
            arguments.removeFirst()
        }

        let stops = arguments.compactMap(parseStop)
        guard stops.count == arguments.count, stops.count >= 2 else { return nil }
        return .linearGradient(angleDegrees: angleDegrees, stops: stops)
    }

    /// Splits gradient arguments on commas that are not nested inside `rgb()`/`rgba()` parens.
    private static func splitTopLevelArguments(_ input: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var depth = 0
        for character in input {
            switch character {
            case "(":
                depth += 1
                current.append(character)
            case ")":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                arguments.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        arguments.append(current)
        return arguments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseDirection(_ raw: String) -> Double? {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowered.hasSuffix("deg") {
            guard let degrees = Double(lowered.dropLast(3).trimmingCharacters(in: .whitespaces)) else { return nil }
            return degrees.truncatingRemainder(dividingBy: 360)
        }
        guard lowered.hasPrefix("to ") else { return nil }
        let keywords = Set(lowered.dropFirst(3).split(separator: " ").map(String.init))
        switch keywords {
        case ["top"]: return 0
        case ["right"]: return 90
        case ["bottom"]: return 180
        case ["left"]: return 270
        case ["top", "right"], ["right", "top"]: return 45
        case ["bottom", "right"], ["right", "bottom"]: return 135
        case ["bottom", "left"], ["left", "bottom"]: return 225
        case ["top", "left"], ["left", "top"]: return 315
        default: return nil
        }
    }

    /// `<color> [<percent>]` -- the colour token is a hex literal or an rgb()/rgba() call.
    private static func parseStop(_ raw: String) -> CSSColorStop? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorToken: String
        let remainder: String
        if trimmed.lowercased().hasPrefix("rgb") {
            guard let closeIndex = trimmed.firstIndex(of: ")") else { return nil }
            colorToken = String(trimmed[...closeIndex])
            remainder = String(trimmed[trimmed.index(after: closeIndex)...])
        } else {
            if let spaceIndex = trimmed.firstIndex(where: \.isWhitespace) {
                colorToken = String(trimmed[..<spaceIndex])
                remainder = String(trimmed[spaceIndex...])
            } else {
                colorToken = trimmed
                remainder = ""
            }
        }
        guard var stop = parseColor(colorToken) else { return nil }
        let position = remainder.trimmingCharacters(in: .whitespaces)
        if !position.isEmpty {
            guard position.hasSuffix("%"), let percent = Double(position.dropLast()) else { return nil }
            stop.location = min(1, max(0, percent / 100))
        }
        return stop
    }

    private static func parseSixDigitHex(_ hex: String, alpha: Double) -> CSSColorStop? {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return CSSColorStop(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension CSSColorStop {
    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension RoleColorValue {
    /// The style applied to role-coloured text: a flat colour, or a `LinearGradient` for
    /// multi-colour roles.
    public var foregroundStyle: AnyShapeStyle {
        switch self {
        case let .solid(stop):
            return AnyShapeStyle(stop.color)
        case let .linearGradient(angleDegrees, stops):
            let points = LinearGradientGeometry.unitPoints(angleDegrees: angleDegrees)
            return AnyShapeStyle(LinearGradient(
                gradient: Gradient(stops: resolvedGradientStops(stops)),
                startPoint: points.start,
                endPoint: points.end
            ))
        }
    }

    /// A single flat colour for surfaces where a gradient would not read (mention chips,
    /// low-opacity chip backgrounds, diagnostics tokens).
    public var solidFallbackColor: Color {
        primaryStop.color
    }

    /// Fills in missing stop locations the way CSS distributes them: first stop 0, last stop 1,
    /// unpositioned interior stops spread evenly between their positioned neighbours, and
    /// positions clamped to be non-decreasing.
    private func resolvedGradientStops(_ stops: [CSSColorStop]) -> [Gradient.Stop] {
        var locations: [Double?] = stops.map(\.location)
        if locations[0] == nil { locations[0] = 0 }
        if locations[locations.count - 1] == nil { locations[locations.count - 1] = 1 }
        var index = 0
        while index < locations.count {
            guard locations[index] == nil else {
                index += 1
                continue
            }
            let previousIndex = index - 1
            var nextIndex = index
            while locations[nextIndex] == nil { nextIndex += 1 }
            let previousValue = locations[previousIndex] ?? 0
            let nextValue = locations[nextIndex] ?? 1
            let gapCount = nextIndex - previousIndex
            for offset in 1..<gapCount {
                locations[previousIndex + offset] = previousValue
                    + (nextValue - previousValue) * Double(offset) / Double(gapCount)
            }
            index = nextIndex
        }
        var running = 0.0
        return zip(stops, locations).map { stop, location in
            running = max(running, min(1, max(0, location ?? 0)))
            return Gradient.Stop(color: stop.color, location: running)
        }
    }
}













public struct ChannelRow: View {
    private let channel: Channel
    private let isSelected: Bool
    private let unreadCount: Int
    private let mentionCount: Int
    private let action: () -> Void

    public init(channel: Channel, isSelected: Bool, unreadCount: Int = 0, mentionCount: Int = 0, action: @escaping () -> Void) {
        self.channel = channel
        self.isSelected = isSelected
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StoatSpacing.small) {
                Image(systemName: iconName)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                    .frame(width: 18)
                Text(channel.displayName)
                    .font(isSelected ? StoatTypography.rowSelected : StoatTypography.row)
                    .lineLimit(1)
                Spacer(minLength: StoatSpacing.small)
                if mentionCount > 0 {
                    MentionBadge(count: mentionCount)
                } else if unreadCount > 0 {
                    Circle().fill(Color.secondary).frame(width: 7, height: 7)
                }
                if channel.permissions?.contains(.viewChannel) == false {
                    Image(systemName: "lock.fill").foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, StoatSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: StoatSize.minimumRowHeight)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
        .accessibilityLabel(StoatAccessibility.channelLabel(name: channel.displayName, unreadCount: unreadCount, mentionCount: mentionCount, isSelected: isSelected, isDisabled: isDisabled))
        .accessibilityHint(isDisabled ? "Voice channels are deferred in this phase" : "Open channel")
    }

    private var isDisabled: Bool { channel.kind == .voiceChannel }

    private var iconName: String {
        switch channel.kind {
        case .directMessage: "person"
        case .group: "person.2"
        case .savedMessages: "tray"
        case .voiceChannel: "speaker.wave.2"
        default: "number"
        }
    }
}

public struct ServerRailItem: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let unreadCount: Int
    private let mentionCount: Int
    private let isDisabled: Bool
    private let imageData: Data?
    private let action: () -> Void

    public init(title: String, systemImage: String? = nil, isSelected: Bool = false, unreadCount: Int = 0, mentionCount: Int = 0, isDisabled: Bool = false, imageData: Data? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
        self.isDisabled = isDisabled
        self.imageData = imageData
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSelected ? Color.accentColor : (unreadCount > 0 ? Color.secondary : Color.clear))
                        .frame(width: 4, height: isSelected ? 30 : 12)
                    Spacer(minLength: 0)
                    icon
                    Spacer(minLength: 0)
                }
                if mentionCount > 0 {
                    MentionBadge(count: mentionCount)
                        .offset(x: -2, y: -4)
                }
            }
            .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(title)
        .contextMenu {
            Button("Server menu unavailable in Phase 3") {}
                .disabled(true)
        }
        .accessibilityLabel(StoatAccessibility.serverLabel(name: title, unreadCount: unreadCount, mentionCount: mentionCount, isSelected: isSelected))
        .accessibilityHint(isDisabled ? "Unavailable in this phase" : "Open server or route")
    }

    @ViewBuilder private var icon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: StoatSize.serverIcon, height: StoatSize.serverIcon)
                .background(isSelected ? Color.accentColor.opacity(0.26) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: isSelected ? 15 : StoatRadius.avatar, style: .continuous))
        } else {
            ServerIconView(name: title, isSelected: isSelected, imageData: imageData)
        }
    }
}

public struct MemberRow: View {
    private let user: User
    private let subtitle: String?
    private let displayName: String?
    private let imageData: Data?

    public init(user: User, subtitle: String? = nil, displayName: String? = nil, imageData: Data? = nil) {
        self.user = user
        self.subtitle = subtitle
        self.displayName = displayName
        self.imageData = imageData
    }

    public var body: some View {
        let name = displayName ?? user.displayName ?? user.username
        HStack(spacing: StoatSpacing.medium) {
            AvatarView(title: name, size: StoatSize.compactAvatar, isOnline: user.online, presence: user.status?.presence, imageData: imageData)
            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle ?? "@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, StoatSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}

@available(macOS 15.0, *)
#Preview("UI Components") {
    VStack(alignment: .leading, spacing: StoatSpacing.large) {
        GlassSearchField {}
        ChannelRow(channel: Channel(id: "preview-channel", kind: .textChannel, name: "general"), isSelected: true, unreadCount: 3) {}
        MemberRow(user: User(id: "preview-user", username: "liquidbagel", displayName: "Liquid Bagel", online: true))
        GlassComposer(text: .constant(""), placeholder: "Message #general")
    }
    .padding()
    .frame(width: 420)
}
