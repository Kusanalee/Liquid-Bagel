import CryptoKit
import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

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
        guard let colour = item.embed.colour?.trimmingCharacters(in: .whitespacesAndNewlines), !colour.isEmpty,
              let parsed = CSSRoleColorParser.parse(colour)
        else {
            return Color.accentColor
        }
        // Embed accents render as a thin edge stripe; a gradient collapses to its primary stop.
        return parsed.solidFallbackColor
    }
}
