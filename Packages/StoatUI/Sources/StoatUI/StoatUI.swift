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
private actor DecodedImageStore {
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

    public static func reset() async {
        #if canImport(AppKit)
        await DecodedImageStore.shared.reset()
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

public struct MessageEmbedDisplayItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var embed: Embed
    public var label: String
    public var title: String?
    public var description: String?
    public var siteName: String?
    public var displayURL: String?
    public var externalURL: URL?
    public var mediaItem: AttachmentDisplayItem?
    public var mediaPreviewData: Data?
    public var accessibilityLabel: String

    public init(
        id: String = UUID().uuidString,
        embed: Embed,
        mediaItem: AttachmentDisplayItem? = nil,
        mediaPreviewData: Data? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.embed = embed
        self.label = Self.label(for: embed.kind)
        self.title = Self.safeText(embed.title, limit: 120)
        self.description = Self.safeText(embed.description, limit: 500)
        self.siteName = Self.safeText(embed.siteName, limit: 80)
        self.displayURL = Self.safeDisplayURL(embed.url ?? embed.originalURL)
        self.externalURL = Self.safeExternalURL(embed.url ?? embed.originalURL)
        self.mediaItem = mediaItem
        self.mediaPreviewData = mediaPreviewData
        self.accessibilityLabel = accessibilityLabel ?? Self.makeAccessibilityLabel(
            label: self.label,
            title: self.title,
            siteName: self.siteName,
            displayURL: self.displayURL,
            mediaItem: mediaItem,
            hasExternalImage: embed.image != nil,
            hasExternalVideo: embed.video != nil
        )
    }

    public static func label(for kind: EmbedKind) -> String {
        switch kind {
        case .website:
            return "Link"
        case .image:
            return "Image"
        case .video:
            return "Video"
        case .text, .none:
            return "Embed"
        case let .unknown(value):
            let trimmed = safeText(value, limit: 32)
            return trimmed.map { "Embed \($0)" } ?? "Embed"
        }
    }

    public static func safeText(_ value: String?, limit: Int = 180) -> String? {
        guard let value else { return nil }
        let scalars = value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: max(0, limit - 3))
        return String(trimmed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    public static func safeExternalURL(_ raw: String?) -> URL? {
        guard let raw,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false
        else { return nil }
        return components.url
    }

    public static func safeDisplayURL(_ raw: String?) -> String? {
        guard var components = raw.flatMap(URLComponents.init(string:)),
              components.host?.isEmpty == false
        else { return nil }
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private static func makeAccessibilityLabel(
        label: String,
        title: String?,
        siteName: String?,
        displayURL: String?,
        mediaItem: AttachmentDisplayItem?,
        hasExternalImage: Bool,
        hasExternalVideo: Bool
    ) -> String {
        var parts = [label]
        if let title { parts.append(title) }
        if let siteName { parts.append(siteName) }
        if let displayURL { parts.append(displayURL) }
        if let mediaItem {
            parts.append("media \(mediaItem.displayName)")
        } else if hasExternalImage {
            parts.append("external image preview available")
        } else if hasExternalVideo {
            parts.append("external video preview available")
        }
        return parts.joined(separator: ", ")
    }
}

public enum ExternalEmbedMediaFactory {
    public static func mediaItem(for embed: Embed) -> AttachmentDisplayItem? {
        if let thumbnail = youtubeThumbnailItem(special: embed.special) {
            return thumbnail
        }
        if let image = embed.image {
            return imageItem(urlString: image.url)
        }
        if embed.kind == .image, let url = embed.url ?? embed.originalURL {
            return imageItem(urlString: url)
        }
        if let video = embed.video {
            return videoItem(urlString: video.url)
        }
        if embed.kind == .video, let url = embed.url ?? embed.originalURL {
            return videoItem(urlString: url)
        }
        return nil
    }

    public static func imageItem(urlString: String) -> AttachmentDisplayItem? {
        guard let url = safeHTTPSURL(urlString) else { return nil }
        let id = "embed-ext-\(digest(url.absoluteString))"
        return AttachmentDisplayItem(
            id: id,
            displayName: displayName(for: url, fallback: "embed-image"),
            kind: .image,
            source: .remote(fileID: FileID(rawValue: id), tag: "external", url: url)
        )
    }

    public static func videoItem(urlString: String) -> AttachmentDisplayItem? {
        guard let url = safeHTTPSURL(urlString) else { return nil }
        guard ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) else { return nil }
        let id = "embed-ext-\(digest(url.absoluteString))"
        return AttachmentDisplayItem(
            id: id,
            displayName: displayName(for: url, fallback: "embed-video"),
            kind: .video,
            source: .remote(fileID: FileID(rawValue: id), tag: "external", url: url)
        )
    }

    public static func youtubeThumbnailItem(special: JSONValue?) -> AttachmentDisplayItem? {
        guard case let .object(fields) = special,
              case .string("YouTube") = fields["type"] ?? .null,
              case let .string(videoID) = fields["id"] ?? .null
        else { return nil }
        let allowed = videoID.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
        guard allowed, !videoID.isEmpty else { return nil }
        return imageItem(urlString: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    private static func safeHTTPSURL(_ raw: String) -> URL? {
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false
        else { return nil }
        return components.url
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func displayName(for url: URL, fallback: String) -> String {
        let last = url.lastPathComponent
        return last.isEmpty || last == "/" ? fallback : last
    }
}

public struct EmojiPickerSection: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var items: [String]

    public init(id: String, title: String, items: [String]) {
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

public struct GlassComposer: View {
    @State private var isEmojiPopoverPresented = false
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
    private let onInsertEmoji: (String) -> Void
    private let onPasteImageData: (Data) -> Void
    private let onPasteFileURLs: ([URL]) -> Void
    private let onSend: () -> Void
    private let onFocus: () -> Void

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
        onInsertEmoji: @escaping (String) -> Void = { _ in },
        onPasteImageData: @escaping (Data) -> Void = { _ in },
        onPasteFileURLs: @escaping ([URL]) -> Void = { _ in },
        onSend: @escaping () -> Void = {},
        onFocus: @escaping () -> Void = {}
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
        self.onPasteImageData = onPasteImageData
        self.onPasteFileURLs = onPasteFileURLs
        self.onSend = onSend
        self.onFocus = onFocus
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
                        ComposerTextInput(text: $text, isEnabled: isEnabled, focusRequestID: focusRequestID, onSubmit: onSend, onFocus: onFocus, onPasteImageData: onPasteImageData, onPasteFileURLs: onPasteFileURLs)
                            .frame(height: ComposerTextSizing.height(for: text))
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
                    } label: {
                        Image(systemName: "face.smiling")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $isEmojiPopoverPresented, arrowEdge: .top) {
                        EmojiPickerPopover(
                            sections: emojiSections.isEmpty ? [EmojiPickerSection(id: "emoji", title: "Emoji", items: emojiItems)] : emojiSections,
                            disabledReason: isEnabled ? nil : disabledReason,
                            onInsertEmoji: { emoji in
                                onInsertEmoji(emoji)
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

private struct EmojiPickerPopover: View {
    let sections: [EmojiPickerSection]
    let disabledReason: String?
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
                                    ForEach(section.items, id: \.self) { emoji in
                                        Button {
                                            onInsertEmoji(emoji)
                                        } label: {
                                            Text(emoji)
                                                .font(emoji.hasPrefix(":") ? .caption.weight(.semibold) : .title3)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Insert emoji \(emoji)")
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
                item.localizedCaseInsensitiveContains(query)
                    || item.trimmingCharacters(in: CharacterSet(charactersIn: ":")).localizedCaseInsensitiveContains(query)
                    || Self.aliases(for: item).contains { $0.localizedCaseInsensitiveContains(query) }
            }
            return matches.isEmpty ? nil : EmojiPickerSection(id: section.id, title: section.title, items: matches)
        }
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
    let onSubmit: () -> Void
    let onFocus: () -> Void
    let onPasteImageData: (Data) -> Void
    let onPasteFileURLs: ([URL]) -> Void

    var body: some View {
        #if canImport(AppKit)
        ComposerTextView(text: $text, isEnabled: isEnabled, focusRequestID: focusRequestID, onSubmit: onSubmit, onFocus: onFocus, onPasteImageData: onPasteImageData, onPasteFileURLs: onPasteFileURLs)
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
private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequestID: Int
    let onSubmit: () -> Void
    let onFocus: () -> Void
    let onPasteImageData: (Data) -> Void
    let onPasteFileURLs: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onFocus: onFocus, onPasteImageData: onPasteImageData, onPasteFileURLs: onPasteFileURLs)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
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
        return scrollView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        let height = proposal.height ?? ComposerTextSizing.height(for: text)
        return CGSize(
            width: max(1, width),
            height: min(ComposerTextSizing.maximumHeight, max(ComposerTextSizing.compactHeight, height))
        )
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        if isEnabled, context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(textView)
            }
        }
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onFocus = onFocus
        context.coordinator.onPasteImageData = onPasteImageData
        context.coordinator.onPasteFileURLs = onPasteFileURLs
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onFocus: () -> Void
        var onPasteImageData: (Data) -> Void
        var onPasteFileURLs: ([URL]) -> Void
        var lastFocusRequestID = 0

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onFocus: @escaping () -> Void,
            onPasteImageData: @escaping (Data) -> Void,
            onPasteFileURLs: @escaping ([URL]) -> Void
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onFocus = onFocus
            self.onPasteImageData = onPasteImageData
            self.onPasteFileURLs = onPasteFileURLs
        }

        func textDidBeginEditing(_ notification: Notification) {
            onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSText.paste(_:)) {
                return handlePaste()
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            if NSEvent.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                text.wrappedValue = textView.string
            } else {
                onSubmit()
            }
            return true
        }

        private func handlePaste() -> Bool {
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string)?.isEmpty == false {
                return false
            }
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
            if !urls.isEmpty {
                onPasteFileURLs(urls)
                return true
            }
            if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
                onPasteImageData(data)
                return true
            }
            return false
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

public struct MessageRow: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false
    private let message: Message
    private let author: User?
    private let authorDisplayNameOverride: String?
    private let authorDisplayColor: Color?
    private let showsHeader: Bool
    private let statusText: String?
    private let isSelected: Bool
    private let isFocused: Bool
    private let isSearchHighlighted: Bool
    private let isCurrentSearchResult: Bool
    private let isTargetHighlighted: Bool
    private let isCompactDensity: Bool
    private let searchAccessibilityStatus: String?
    private let replyPreview: String?
    private let replyPreviewItem: MessageRowReplyPreviewItem?
    private let attachmentItems: [AttachmentDisplayItem]?
    private let customEmojiItems: [MessageInlineCustomEmojiItem]
    private let preparedMarkdownContent: PreparedMarkdownContent?
    private let embedItems: [MessageEmbedDisplayItem]?
    private let authorAvatarData: Data?
    private let actionItems: [MessageRowActionItem]
    private let reactionItems: [MessageReactionDisplayItem]
    private let onMessageAction: (String) -> Void
    private let onToggleReaction: (String) -> Void
    private let onPreviewAttachment: (AttachmentDisplayItem) -> Void
    private let onDownloadAttachment: (AttachmentDisplayItem) -> Void
    private let onOpenAttachment: (AttachmentDisplayItem) -> Void
    private let onRetryAttachment: (AttachmentDisplayItem) -> Void
    private let onPreviewEmbedMedia: (AttachmentDisplayItem) -> Void
    private let onDownloadEmbedMedia: (AttachmentDisplayItem) -> Void
    private let onOpenEmbedMedia: (AttachmentDisplayItem) -> Void
    private let onRetryEmbedMedia: (AttachmentDisplayItem) -> Void
    private let onOpenAuthorProfile: () -> Void
    private let onOpenReplyPreview: () -> Void

    public init(
        message: Message,
        author: User?,
        authorDisplayNameOverride: String? = nil,
        authorDisplayColor: Color? = nil,
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
        preparedMarkdownContent: PreparedMarkdownContent? = nil,
        embedItems: [MessageEmbedDisplayItem]? = nil,
        authorAvatarData: Data? = nil,
        actionItems: [MessageRowActionItem] = [],
        reactionItems: [MessageReactionDisplayItem] = [],
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
        onOpenReplyPreview: @escaping () -> Void = {}
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
        self.preparedMarkdownContent = preparedMarkdownContent
        self.embedItems = embedItems
        self.authorAvatarData = authorAvatarData
        self.actionItems = actionItems
        self.reactionItems = reactionItems
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
                                .foregroundStyle(authorDisplayColor ?? .primary)
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
                            customEmojiItems: customEmojiItems
                        )
                    } else {
                        MarkdownMessageContent(content, customEmojiItems: customEmojiItems)
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
            if showsActionAffordance {
                messageActionBar
            }
        }
        .onHover { isHovering = $0 }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StoatAccessibility.messageLabel(author: authorName, timestamp: timestampText, content: message.content ?? message.system?.content ?? "", isEdited: message.isEdited, isPinned: message.isPinned, reactionCount: reactionCount, status: statusText, isSelected: isSelected, isFocused: isFocused || isTargetHighlighted, searchResultStatus: searchAccessibilityStatus, replyPreview: effectiveReplyPreviewItem?.plainText))
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

    private var showsActionAffordance: Bool {
        !actionItems.isEmpty && (isHovering || isFocused || isSelected)
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

public struct PreparedMarkdownContent: Hashable, Sendable {
    public var source: String
    fileprivate var blocks: [MarkdownBlock]

    fileprivate init(source: String, blocks: [MarkdownBlock]) {
        self.source = source
        self.blocks = blocks
    }
}

public enum MarkdownContentPreparer {
    nonisolated public static func prepare(
        _ source: String,
        customEmojiItems: [MessageInlineCustomEmojiItem] = []
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
            let tokens = MarkdownInlineCache.shared.tokens(source: inlineSource, items: customEmojiItems)
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
    @State private var asynchronouslyPreparedContent: PreparedMarkdownContent?

    public init(_ source: String, customEmojiItems: [MessageInlineCustomEmojiItem] = []) {
        self.source = source
        self.preparedContent = nil
        self.customEmojiItems = customEmojiItems
        _asynchronouslyPreparedContent = State(initialValue: nil)
    }

    public init(
        prepared: PreparedMarkdownContent,
        customEmojiItems: [MessageInlineCustomEmojiItem] = []
    ) {
        self.source = prepared.source
        self.preparedContent = prepared
        self.customEmojiItems = customEmojiItems
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
            asynchronouslyPreparedContent = await Task.detached(priority: .userInitiated) {
                MarkdownContentPreparer.prepare(source, customEmojiItems: customEmojiItems)
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
                    MarkdownInlineContent(source: quote, customEmojiItems: customEmojiItems, font: StoatTypography.messageBody)
                        .padding(.leading, StoatSpacing.small)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2)
                        }
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                case let .heading(level, text):
                    MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, font: level <= 1 ? .title3.weight(.semibold) : .headline)
                        .textSelection(.enabled)
                case let .listItem(marker, text):
                    HStack(alignment: .firstTextBaseline, spacing: StoatSpacing.small) {
                        Text(marker)
                            .font(StoatTypography.messageBody)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, font: StoatTypography.messageBody)
                            .textSelection(.enabled)
                    }
                case let .text(text):
                    MarkdownInlineContent(source: text, customEmojiItems: customEmojiItems, font: StoatTypography.messageBody)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

public struct MarkdownCacheDiagnostics: Hashable, Sendable {
    public var cacheCount: Int
    public var parseCount: Int
    public var cacheHitCount: Int
}

private final class MarkdownBlockCache: @unchecked Sendable {
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

extension MarkdownMessageContent {
    public static func cacheDiagnostics() -> MarkdownCacheDiagnostics {
        MarkdownBlockCache.shared.diagnostics()
    }

    nonisolated static func _testBlockDescriptions(for source: String) -> [String] {
        MarkdownBlock.parse(source).map(\.testDescription)
    }

    nonisolated static func _testInlineTokenDescriptions(for source: String, customEmojiItems: [MessageInlineCustomEmojiItem]) -> [String] {
        InlineCustomEmojiToken.tokenize(source: source, items: customEmojiItems).map(\.testDescription)
    }
}

private struct InlineCustomEmojiMessageContent: View {
    let source: String
    let customEmojiItems: [MessageInlineCustomEmojiItem]

    var body: some View {
        MarkdownMessageContent(source, customEmojiItems: customEmojiItems)
    }
}

private struct MarkdownInlineContent: View {
    let source: String
    let customEmojiItems: [MessageInlineCustomEmojiItem]
    let font: Font
    private let tokens: [InlineCustomEmojiToken]

    init(source: String, customEmojiItems: [MessageInlineCustomEmojiItem], font: Font) {
        self.source = source
        self.customEmojiItems = customEmojiItems
        self.font = font
        self.tokens = MarkdownInlineCache.shared.tokens(source: source, items: customEmojiItems)
    }

    var body: some View {
        HStack(alignment: .center, spacing: StoatSpacing.xxSmall) {
            ForEach(tokens.indices, id: \.self) { index in
                switch tokens[index] {
                case let .text(value):
                    Text(Self.attributed(value))
                        .font(font)
                        .textSelection(.enabled)
                case let .emoji(item):
                    inlineEmoji(item)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(source)
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

    private static func attributed(_ value: String) -> AttributedString {
        MarkdownInlineCache.shared.attributed(value)
    }
}

private enum InlineCustomEmojiToken: Hashable {
    case text(String)
    case emoji(MessageInlineCustomEmojiItem)

    static func tokenize(source: String, items: [MessageInlineCustomEmojiItem]) -> [InlineCustomEmojiToken] {
        var remaining = source[...]
        var result: [InlineCustomEmojiToken] = []
        let byShortcode = Dictionary(uniqueKeysWithValues: items.map { ($0.shortcode, $0) })

        while let start = remaining.firstIndex(of: ":"),
              let end = remaining[remaining.index(after: start)...].firstIndex(of: ":") {
            let before = String(remaining[..<start])
            if !before.isEmpty { result.append(.text(before)) }
            let shortcode = String(remaining[start...end])
            if let item = byShortcode[shortcode] {
                result.append(.emoji(item))
            } else {
                result.append(.text(shortcode))
            }
            remaining = remaining[remaining.index(after: end)...]
        }
        let tail = String(remaining)
        if !tail.isEmpty { result.append(.text(tail)) }
        return result.isEmpty ? [.text(source)] : result
    }

    var testDescription: String {
        switch self {
        case let .text(value):
            return "text::\(value)"
        case let .emoji(item):
            return "emoji::\(item.shortcode)"
        }
    }
}

private final class MarkdownInlineCache: @unchecked Sendable {
    static let shared = MarkdownInlineCache()

    private struct TokenKey: Hashable {
        var source: String
        var items: [MessageInlineCustomEmojiItem]
    }

    private let lock = NSLock()
    private var tokensByKey: [TokenKey: [InlineCustomEmojiToken]] = [:]
    private var attributedBySource: [String: AttributedString] = [:]
    private var tokenOrder: [TokenKey] = []
    private var attributedOrder: [String] = []
    private var tokenByteCount = 0
    private var attributedByteCount = 0
    private let maxEntries = 800
    private let maxBytes = 4 * 1024 * 1024

    func tokens(source: String, items: [MessageInlineCustomEmojiItem]) -> [InlineCustomEmojiToken] {
        let key = TokenKey(source: source, items: items)
        lock.lock()
        if let cached = tokensByKey[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let parsed = InlineCustomEmojiToken.tokenize(source: source, items: items)
        lock.lock()
        tokensByKey[key] = parsed
        tokenByteCount += source.utf8.count + items.reduce(0) { $0 + $1.shortcode.utf8.count }
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

    private func trimTokens() {
        while (tokenOrder.count > maxEntries || tokenByteCount > maxBytes), let oldest = tokenOrder.first {
            tokenOrder.removeFirst()
            tokensByKey.removeValue(forKey: oldest)
            tokenByteCount -= oldest.source.utf8.count
                + oldest.items.reduce(0) { $0 + $1.shortcode.utf8.count }
        }
    }
}

private enum MarkdownBlock: Hashable, Sendable {
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

public struct EmbedTimelineCard: View {
    private let item: MessageEmbedDisplayItem
    private let isCompact: Bool
    private let onPreviewMedia: (AttachmentDisplayItem) -> Void
    private let onDownloadMedia: (AttachmentDisplayItem) -> Void
    private let onOpenMedia: (AttachmentDisplayItem) -> Void
    private let onRetryMedia: (AttachmentDisplayItem) -> Void

    public init(embed: Embed, isCompact: Bool = false) {
        self.init(
            item: MessageEmbedDisplayItem(
                embed: embed,
                mediaItem: embed.media.map { AttachmentDisplayItem(file: $0) } ?? ExternalEmbedMediaFactory.mediaItem(for: embed)
            ),
            isCompact: isCompact
        )
    }

    public init(
        item: MessageEmbedDisplayItem,
        isCompact: Bool = false,
        onPreviewMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onDownloadMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onOpenMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onRetryMedia: @escaping (AttachmentDisplayItem) -> Void = { _ in }
    ) {
        self.item = item
        self.isCompact = isCompact
        self.onPreviewMedia = onPreviewMedia
        self.onDownloadMedia = onDownloadMedia
        self.onOpenMedia = onOpenMedia
        self.onRetryMedia = onRetryMedia
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            HStack(spacing: StoatSpacing.small) {
                Text(item.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let provider = item.siteName {
                    Text(provider)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if let title = item.title {
                if let url = item.externalURL {
                    Link(title, destination: url)
                        .font(.caption.weight(.semibold))
                } else {
                    Text(title).font(.caption.weight(.semibold))
                }
            }
            if let description = item.description {
                MarkdownMessageContent(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if let mediaItem = renderedMediaItem {
                embedMedia(mediaItem)
            } else if item.embed.image != nil {
                Label("External image preview available", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if item.embed.video != nil {
                Label("External video preview available", systemImage: "play.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let displayURL = item.displayURL {
                Text(displayURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(isCompact ? StoatSpacing.small : StoatSpacing.medium)
        .frame(maxWidth: isCompact ? 320 : 420, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(accentColor).frame(width: 3)
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder private func embedMedia(_ mediaItem: AttachmentDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
            mediaPreview(mediaItem)
            if !mediaItem.isExternalEmbedMedia {
                HStack(spacing: StoatSpacing.xSmall) {
                    Image(systemName: mediaItem.kind.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mediaItem.displayName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("\(mediaItem.kind.label) · \(AttachmentDisplayFormatting.formattedSize(mediaItem.byteCount))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            mediaControls(mediaItem)
        }
    }

    @ViewBuilder private func mediaPreview(_ mediaItem: AttachmentDisplayItem) -> some View {
        #if canImport(AVKit)
        if mediaItem.kind == .video, let url = mediaItem.playbackURL {
            VideoAttachmentPlayer(url: url, isCompact: isCompact, maxWidth: isCompact ? 280 : 360, height: isCompact ? 180 : 240)
        } else {
            imageMediaPreview(mediaItem)
        }
        #else
        imageMediaPreview(mediaItem)
        #endif
    }

    @ViewBuilder private func imageMediaPreview(_ mediaItem: AttachmentDisplayItem) -> some View {
        #if canImport(AppKit)
        if mediaItem.kind == .image,
           mediaItem.previewState.isReady,
           let data = mediaItem.previewData {
            Button {
                onPreviewMedia(mediaItem)
            } label: {
                DecodedDataImage(data: data, pixelSize: isCompact ? 560 : 720)
                    .scaledToFit()
                    .frame(maxWidth: isCompact ? 280 : 360, maxHeight: isCompact ? 180 : 240, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open embed image \(mediaItem.displayName)")
        } else if case .loading = mediaItem.previewState {
            HStack(spacing: StoatSpacing.small) {
                ProgressView().controlSize(.small)
                Text("Loading embed media")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #else
        if case .loading = mediaItem.previewState {
            Text("Loading embed media")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        #endif
    }

    @ViewBuilder private func mediaControls(_ mediaItem: AttachmentDisplayItem) -> some View {
        HStack(spacing: StoatSpacing.xSmall) {
            if mediaItem.kind.isPreviewable, !(mediaItem.isExternalEmbedMedia && mediaItem.previewState.isReady) {
                Button {
                    onPreviewMedia(mediaItem)
                } label: {
                    Label(mediaItem.previewState.isReady ? "Preview" : "Load Preview", systemImage: "eye")
                }
                .buttonStyle(.borderless)
            }
            if mediaItem.source.isRemoteLoadable, !mediaItem.isExternalEmbedMedia {
                Button {
                    onDownloadMedia(mediaItem)
                } label: {
                    Label("Save As", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
            }
            if mediaItem.previewState.isReady, !mediaItem.isExternalEmbedMedia {
                Button {
                    onOpenMedia(mediaItem)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
            }
            if case .failed = mediaItem.previewState {
                Button {
                    onRetryMedia(mediaItem)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
    }

    private var renderedMediaItem: AttachmentDisplayItem? {
        guard var mediaItem = item.mediaItem else { return nil }
        if let mediaPreviewData = item.mediaPreviewData {
            mediaItem.previewData = mediaPreviewData
            if !mediaItem.previewState.isReady {
                mediaItem.previewState = .readyRemote
            }
        }
        return mediaItem
    }

    private var accentColor: Color {
        guard let colour = item.embed.colour?.trimmingCharacters(in: .whitespacesAndNewlines), !colour.isEmpty else {
            return Color.accentColor
        }
        #if canImport(AppKit)
        var hex = colour
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return Color.accentColor }
        return Color(nsColor: NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        ))
        #else
        return Color.accentColor
        #endif
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
