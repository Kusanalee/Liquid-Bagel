import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

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
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.thinMaterial))
    }
}

public struct GlassToolbar<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(height: 52)
            .padding(.horizontal, StoatSpacing.large)
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.bar))
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
    case pdf
    case text
    case archive
    case generic
    case unsupported

    public var label: String {
        switch self {
        case .image: "Image"
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
        case .archive, .generic, .unsupported:
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

public struct MessageReactionDisplayItem: Identifiable, Hashable, Sendable {
    public var emoji: String
    public var count: Int
    public var hasCurrentUserReacted: Bool

    public var id: String { emoji }

    public init(emoji: String, count: Int, hasCurrentUserReacted: Bool) {
        self.emoji = emoji
        self.count = count
        self.hasCurrentUserReacted = hasCurrentUserReacted
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
            case .video, .audio:
                return .unsupported
            case .file, .unknown:
                break
            }
        }
        let loweredType = (contentType ?? "").lowercased()
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if loweredType.hasPrefix("image/") || ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext) { return .image }
        if loweredType == "application/pdf" || ext == "pdf" { return .pdf }
        if loweredType.hasPrefix("text/") || ["md", "markdown", "json", "csv", "rtf", "txt"].contains(ext) { return .text }
        if ["zip", "gz", "tgz", "tar", "7z", "rar"].contains(ext) { return .archive }
        return .generic
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
                    GlassIconButton("Emoji unavailable in Phase 4", systemImage: "face.smiling", isDisabled: true) {}
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
        if let data = attachment.previewData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
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
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
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
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        return scrollView
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
    private let imageData: Data?

    public init(title: String, subtitle: String? = nil, size: CGFloat = StoatSize.avatar, isOnline: Bool? = nil, imageData: Data? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.isOnline = isOnline
        self.imageData = imageData
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
            if let isOnline {
                PresenceDot(isOnline: isOnline)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }

    @ViewBuilder private var avatarContent: some View {
        #if canImport(AppKit)
        if let imageData, let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
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
        if let imageData, let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
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
    private let isOnline: Bool

    public init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    public var body: some View {
        Circle()
            .fill(isOnline ? Color.green : Color.secondary)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
            .accessibilityLabel(isOnline ? "Online" : "Offline")
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
    private let showsHeader: Bool
    private let statusText: String?
    private let isSelected: Bool
    private let isFocused: Bool
    private let isSearchHighlighted: Bool
    private let isCurrentSearchResult: Bool
    private let isCompactDensity: Bool
    private let searchAccessibilityStatus: String?
    private let replyPreview: String?
    private let attachmentItems: [AttachmentDisplayItem]?
    private let authorAvatarData: Data?
    private let actionItems: [MessageRowActionItem]
    private let reactionItems: [MessageReactionDisplayItem]
    private let onMessageAction: (String) -> Void
    private let onToggleReaction: (String) -> Void
    private let onPreviewAttachment: (AttachmentDisplayItem) -> Void
    private let onDownloadAttachment: (AttachmentDisplayItem) -> Void
    private let onOpenAttachment: (AttachmentDisplayItem) -> Void
    private let onRetryAttachment: (AttachmentDisplayItem) -> Void

    public init(
        message: Message,
        author: User?,
        authorDisplayNameOverride: String? = nil,
        showsHeader: Bool = true,
        statusText: String? = nil,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isSearchHighlighted: Bool = false,
        isCurrentSearchResult: Bool = false,
        isCompactDensity: Bool = false,
        searchAccessibilityStatus: String? = nil,
        replyPreview: String? = nil,
        attachmentItems: [AttachmentDisplayItem]? = nil,
        authorAvatarData: Data? = nil,
        actionItems: [MessageRowActionItem] = [],
        reactionItems: [MessageReactionDisplayItem] = [],
        onMessageAction: @escaping (String) -> Void = { _ in },
        onToggleReaction: @escaping (String) -> Void = { _ in },
        onPreviewAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onDownloadAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onOpenAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in },
        onRetryAttachment: @escaping (AttachmentDisplayItem) -> Void = { _ in }
    ) {
        self.message = message
        self.author = author
        self.authorDisplayNameOverride = authorDisplayNameOverride
        self.showsHeader = showsHeader
        self.statusText = statusText
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isSearchHighlighted = isSearchHighlighted
        self.isCurrentSearchResult = isCurrentSearchResult
        self.isCompactDensity = isCompactDensity
        self.searchAccessibilityStatus = searchAccessibilityStatus
        self.replyPreview = replyPreview
        self.attachmentItems = attachmentItems
        self.authorAvatarData = authorAvatarData
        self.actionItems = actionItems
        self.reactionItems = reactionItems
        self.onMessageAction = onMessageAction
        self.onToggleReaction = onToggleReaction
        self.onPreviewAttachment = onPreviewAttachment
        self.onDownloadAttachment = onDownloadAttachment
        self.onOpenAttachment = onOpenAttachment
        self.onRetryAttachment = onRetryAttachment
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
                AvatarView(title: authorName, size: StoatSize.avatar, isOnline: author?.online, imageData: authorAvatarData)
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
                        Text(authorName)
                            .font(StoatTypography.messageAuthor)
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
                if let replyPreview {
                    HStack(spacing: StoatSpacing.xSmall) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(replyPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, StoatSpacing.small)
                    .padding(.vertical, StoatSpacing.xxSmall)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                    .accessibilityLabel(StoatAccessibility.replyPreviewLabel(replyPreview))
                }
                if let content = message.content, !content.isEmpty {
                    MarkdownMessageContent(content)
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
                if let embeds = message.embeds, !embeds.isEmpty {
                    ForEach(Array(embeds.enumerated()), id: \.offset) { _, embed in
                        EmbedTimelineCard(embed: embed, isCompact: isCompactDensity)
                    }
                }
                let renderedReactions = reactionItems.isEmpty ? fallbackReactionItems : reactionItems
                if !renderedReactions.isEmpty {
                    HStack(spacing: StoatSpacing.small) {
                        ForEach(renderedReactions) { reaction in
                            Button {
                                onToggleReaction(reaction.emoji)
                            } label: {
                                Text("\(reaction.emoji) \(reaction.count)")
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StoatAccessibility.messageLabel(author: authorName, timestamp: timestampText, content: message.content ?? message.system?.content ?? "", isEdited: message.isEdited, isPinned: message.isPinned, reactionCount: reactionCount, status: statusText, isSelected: isSelected, isFocused: isFocused, searchResultStatus: searchAccessibilityStatus, replyPreview: replyPreview))
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
        message.masquerade?.name ?? authorDisplayNameOverride ?? author?.displayName ?? author?.username ?? message.authorID.rawValue
    }

    private var timestampText: String {
        guard let date = message.createdAt else { return "now" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        .frame(maxWidth: isCompact ? 320 : 380, alignment: .leading)
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
           let data = item.previewData,
           let image = NSImage(data: data) {
            Button(action: onPreview) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: isCompact ? 300 : 360, maxHeight: isCompact ? 180 : 240, alignment: .leading)
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
           let data = item.previewData,
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
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

public struct MarkdownMessageContent: View {
    private let source: String

    public init(_ source: String) {
        self.source = source
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            ForEach(blocks.indices, id: \.self) { index in
                switch blocks[index] {
                case let .code(code):
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(StoatSpacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                        .textSelection(.enabled)
                case let .quote(quote):
                    Text(attributed(quote))
                        .font(StoatTypography.messageBody)
                        .foregroundStyle(.secondary)
                        .padding(.leading, StoatSpacing.small)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2)
                        }
                        .textSelection(.enabled)
                case let .text(text):
                    Text(attributed(text))
                        .font(StoatTypography.messageBody)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(source)
    }

    private func attributed(_ value: String) -> AttributedString {
        let sanitized = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return (try? AttributedString(markdown: sanitized, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(sanitized)
    }
}

private enum MarkdownBlock: Hashable {
    case text(String)
    case code(String)
    case quote(String)

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
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                flushText()
                let quote = line.replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression)
                result.append(.quote(quote))
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
}

public struct EmbedTimelineCard: View {
    private let embed: Embed
    private let isCompact: Bool

    public init(embed: Embed, isCompact: Bool = false) {
        self.embed = embed
        self.isCompact = isCompact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            HStack(spacing: StoatSpacing.small) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let provider = safeText(embed.siteName) {
                    Text(provider)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if let title = safeText(embed.title) {
                if let url = SafeEmbedURL.externalURL(embed.url ?? embed.originalURL) {
                    Link(title, destination: url)
                        .font(.caption.weight(.semibold))
                } else {
                    Text(title).font(.caption.weight(.semibold))
                }
            }
            if let description = safeText(embed.description) {
                MarkdownMessageContent(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if embed.image != nil || embed.media != nil {
                Label(embed.media?.filename ?? "Image preview available", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if embed.video != nil {
                Label("Video preview", systemImage: "play.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let displayURL = SafeEmbedURL.display(embed.url ?? embed.originalURL) {
                Text(displayURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(isCompact ? StoatSpacing.small : StoatSpacing.medium)
        .frame(maxWidth: 340, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(accentColor).frame(width: 3)
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        switch embed.kind {
        case .website: "Link"
        case .image: "Image"
        case .video: "Video"
        case .text: "Embed"
        case .none: "Embed"
        case let .unknown(value): value.isEmpty ? "Embed" : "Embed \(value)"
        }
    }

    private var accentColor: Color {
        guard let colour = embed.colour?.trimmingCharacters(in: .whitespacesAndNewlines), !colour.isEmpty else {
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

    private var accessibilityLabel: String {
        [label, safeText(embed.title), safeText(embed.siteName), SafeEmbedURL.display(embed.url ?? embed.originalURL)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func safeText(_ value: String?) -> String? {
        let trimmed = value?
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private enum SafeEmbedURL {
    static func externalURL(_ raw: String?) -> URL? {
        guard let raw,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false
        else { return nil }
        return components.url
    }

    static func display(_ raw: String?) -> String? {
        guard var components = raw.flatMap(URLComponents.init(string:)),
              components.host?.isEmpty == false
        else { return nil }
        components.query = nil
        components.fragment = nil
        return components.string
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
            AvatarView(title: name, size: StoatSize.compactAvatar, isOnline: user.online, imageData: imageData)
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
