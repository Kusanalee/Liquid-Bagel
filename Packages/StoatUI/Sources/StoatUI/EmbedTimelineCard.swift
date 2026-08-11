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
    // The card previously declared no environment at all, so it ignored Reduce Transparency,
    // Increase Contrast, and the Liquid Glass slider that every other surface honors.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
        // The accent bar is a laid-out sibling rather than an overlay. As an overlay it was drawn
        // on top of the rounded background, so its square corners poked past the corner radius,
        // and the uniform padding meant the text started underneath it.
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: EmbedCardMetrics.accentBarWidth)
            content
                .padding(isCompact ? StoatSpacing.small : StoatSpacing.medium)
        }
        .frame(maxWidth: EmbedCardMetrics.maximumWidth(isCompact: isCompact), alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                .strokeBorder(borderColor, lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
        }
        .contextMenu { mediaMenuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            siteHeader
            if let title = item.title {
                if let url = item.externalURL {
                    Link(title, destination: url)
                        .font(.headline)
                } else {
                    Text(title).font(.headline)
                }
            }
            if let description = item.description {
                MarkdownMessageContent(description)
                    .font(StoatTypography.messageBody)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            embedMediaSection
        }
    }

    /// Site name with a bounded local monogram. `embed.iconURL` is an external URL, so fetching it
    /// unconditionally would break the "external embed media does not autoload" guarantee; the
    /// monogram carries the same provenance without a network request.
    @ViewBuilder private var siteHeader: some View {
        if let provider = item.siteName {
            HStack(spacing: StoatSpacing.xSmall) {
                Text(EmbedSiteMonogram.monogram(for: provider))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text(provider)
                    .font(StoatTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if item.externalURL != nil {
            Image(systemName: "globe")
                .font(StoatTypography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var embedMediaSection: some View {
        if let mediaItem = renderedMediaItem {
            embedMedia(mediaItem)
        } else if let placement = unloadedMediaPlacement {
            // Reserve the final size before the image arrives so the row never reflows when media
            // loads. The old placeholder was a text label of a completely different height.
            RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: placement.width, height: placement.height)
                .overlay {
                    Image(systemName: item.embed.video != nil ? "play.rectangle" : "photo")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityHidden(true)
        }
    }

    /// Media actions live in the card's context menu. A row of Preview/Save As/Open/Retry buttons
    /// inside a link preview is the least native element the card had; no real client shows one.
    @ViewBuilder private var mediaMenuItems: some View {
        if let mediaItem = renderedMediaItem {
            if mediaItem.kind.isPreviewable, !(mediaItem.isExternalEmbedMedia && mediaItem.previewState.isReady) {
                Button(mediaItem.previewState.isReady ? "Preview" : "Load Preview") { onPreviewMedia(mediaItem) }
            }
            if mediaItem.source.isRemoteLoadable, !mediaItem.isExternalEmbedMedia {
                Button("Save As\u{2026}") { onDownloadMedia(mediaItem) }
            }
            if mediaItem.previewState.isReady, !mediaItem.isExternalEmbedMedia {
                Button("Open") { onOpenMedia(mediaItem) }
            }
            if case .failed = mediaItem.previewState {
                Button("Retry") { onRetryMedia(mediaItem) }
            }
        }
        if let url = item.externalURL {
            Divider()
            Link("Open Link", destination: url)
        }
    }

    private var unloadedMediaPlacement: CGSize? {
        guard item.embed.image != nil || item.embed.video != nil else { return nil }
        guard case let .below(size) = mediaPlacement else { return nil }
        return size
    }

    private var mediaPlacement: EmbedMediaLayout.Placement {
        EmbedMediaLayout.placement(
            width: item.embed.image?.width ?? item.embed.video?.width,
            height: item.embed.image?.height ?? item.embed.video?.height,
            size: item.embed.image?.size,
            maxWidth: EmbedCardMetrics.maximumMediaWidth(isCompact: isCompact),
            maxHeight: EmbedCardMetrics.maximumMediaHeight(isCompact: isCompact)
        )
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

    @ViewBuilder private func embedMedia(_ mediaItem: AttachmentDisplayItem) -> some View {
        switch mediaPlacement {
        case let .trailingThumbnail(size):
            // ImageSize.preview is the official clients' side-thumbnail case; it used to render as
            // an oversized image below the text like everything else.
            HStack(alignment: .top, spacing: StoatSpacing.small) {
                mediaPreview(mediaItem, size: size)
                Spacer(minLength: 0)
            }
        case let .below(size):
            mediaPreview(mediaItem, size: size)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private func mediaPreview(_ mediaItem: AttachmentDisplayItem, size: CGSize) -> some View {
        #if canImport(AVKit)
        if mediaItem.kind == .video, let url = mediaItem.playbackURL {
            VideoAttachmentPlayer(url: url, isCompact: isCompact, maxWidth: size.width, height: size.height)
        } else {
            imageMediaPreview(mediaItem, size: size)
        }
        #else
        imageMediaPreview(mediaItem, size: size)
        #endif
    }

    @ViewBuilder private func imageMediaPreview(_ mediaItem: AttachmentDisplayItem, size: CGSize) -> some View {
        #if canImport(AppKit)
        if mediaItem.kind == .image,
           mediaItem.previewState.isReady,
           let data = mediaItem.previewData {
            Button {
                onPreviewMedia(mediaItem)
            } label: {
                DecodedDataImage(data: data, pixelSize: isCompact ? 560 : 720)
                    .scaledToFit()
                    .frame(width: size.width, height: size.height, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open embed image \(mediaItem.displayName)")
        } else if case .loading = mediaItem.previewState {
            // Same reserved geometry as the loaded image, so finishing the load does not reflow.
            RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: size.width, height: size.height)
                .overlay { ProgressView().controlSize(.small) }
                .accessibilityLabel("Loading embed media")
        }
        #else
        if case .loading = mediaItem.previewState {
            Text("Loading embed media")
                .font(StoatTypography.metadata)
                .foregroundStyle(.secondary)
        }
        #endif
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

public enum EmbedCardMetrics {
    public static let accentBarWidth: CGFloat = 3

    /// Matched to `AttachmentTimelineCard` so embeds and attachments do not read as two different
    /// widths in the same timeline. Embeds used to cap at 320/420 against the attachment 460/620.
    public static func maximumWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 460 : 620
    }

    public static func maximumMediaWidth(isCompact: Bool) -> CGFloat {
        maximumWidth(isCompact: isCompact) - accentBarWidth - (isCompact ? StoatSpacing.small : StoatSpacing.medium) * 2
    }

    public static func maximumMediaHeight(isCompact: Bool) -> CGFloat {
        isCompact ? 180 : 240
    }
}

public enum EmbedSiteMonogram {
    /// First letter of the site name, uppercased. Falls back to a globe sentinel when the name
    /// has no usable letter, so the header never renders an empty tile.
    public static func monogram(for siteName: String) -> String {
        let trimmed = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first(where: { $0.isLetter || $0.isNumber }) else { return "\u{2022}" }
        return String(first).uppercased()
    }
}

/// Sizes embed media from the *model's* declared dimensions rather than from the decoded image.
///
/// `EmbedImage.width`/`height` and `ImageSize` were never consulted, so a wide banner and a square
/// thumbnail were squeezed into the same box. Sizing from the model also means the placeholder can
/// be reserved at the final size before the image arrives, so the row never reflows on load.
public enum EmbedMediaLayout {
    public enum Placement: Hashable, Sendable {
        case below(CGSize)
        case trailingThumbnail(CGSize)
        case none
    }

    public static let thumbnailSide: CGFloat = 80
    private static let fallbackAspectRatio: CGFloat = 16.0 / 9.0

    public static func placement(
        width: Int?,
        height: Int?,
        size: ImageSize?,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> Placement {
        guard maxWidth > 0, maxHeight > 0 else { return .none }

        if size == .preview {
            let side = min(thumbnailSide, maxWidth, maxHeight)
            return .trailingThumbnail(CGSize(width: side, height: side))
        }

        // Explicitly zero or negative dimensions mean there is nothing to show; absent dimensions
        // only mean the server did not report them, so those still get a reasonable box.
        if let width, let height, width <= 0 || height <= 0 { return .none }

        let ratio: CGFloat
        if let width, let height, width > 0, height > 0 {
            ratio = CGFloat(width) / CGFloat(height)
        } else {
            ratio = fallbackAspectRatio
        }

        var fittedWidth = maxWidth
        var fittedHeight = maxWidth / ratio
        if fittedHeight > maxHeight {
            fittedHeight = maxHeight
            fittedWidth = maxHeight * ratio
        }
        return .below(CGSize(width: fittedWidth.rounded(), height: fittedHeight.rounded()))
    }
}
