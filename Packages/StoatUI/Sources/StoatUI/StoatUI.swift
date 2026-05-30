import StoatDesignSystem
import StoatModels
import SwiftUI

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
    private let replyAuthor: String?
    private let replyPreview: String?
    @Binding private var shouldMentionReplyAuthor: Bool
    private let focusRequestID: Int
    private let onCancelReply: () -> Void
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
        replyAuthor: String? = nil,
        replyPreview: String? = nil,
        focusRequestID: Int = 0,
        onCancelReply: @escaping () -> Void = {},
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
        self.replyAuthor = replyAuthor
        self.replyPreview = replyPreview
        self.focusRequestID = focusRequestID
        self.onCancelReply = onCancelReply
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
                HStack(alignment: .bottom, spacing: StoatSpacing.medium) {
                    GlassIconButton(canAttach ? "Attach file unavailable in Phase 4" : "Attach file unavailable", systemImage: "paperclip", isDisabled: true) {}
                    ZStack(alignment: .topLeading) {
                        ComposerTextInput(text: $text, isEnabled: isEnabled, focusRequestID: focusRequestID, onSubmit: onSend, onFocus: onFocus)
                            .frame(minHeight: 34, maxHeight: 92)
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
    }
}

private struct ComposerTextInput: View {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequestID: Int
    let onSubmit: () -> Void
    let onFocus: () -> Void

    var body: some View {
        #if canImport(AppKit)
        ComposerTextView(text: $text, isEnabled: isEnabled, focusRequestID: focusRequestID, onSubmit: onSubmit, onFocus: onFocus)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onFocus: onFocus)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
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
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onFocus: () -> Void
        var lastFocusRequestID = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onFocus: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
            self.onFocus = onFocus
        }

        func textDidBeginEditing(_ notification: Notification) {
            onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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
    }
}
#endif

public struct AvatarView: View {
    private let title: String
    private let subtitle: String?
    private let size: CGFloat
    private let isOnline: Bool?

    public init(title: String, subtitle: String? = nil, size: CGFloat = StoatSize.avatar, isOnline: Bool? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.isOnline = isOnline
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: min(StoatRadius.avatar, size / 4), style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.78), Color.pink.opacity(0.52)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Text(StoatInitials.make(title))
                        .font(.system(size: max(11, size * 0.36), weight: .bold))
                        .foregroundStyle(.white)
                }
            if let isOnline {
                PresenceDot(isOnline: isOnline)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

public struct ServerIconView: View {
    private let name: String
    private let isSelected: Bool

    public init(name: String, isSelected: Bool = false) {
        self.name = name
        self.isSelected = isSelected
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: isSelected ? 15 : StoatRadius.avatar, style: .continuous)
            .fill(LinearGradient(colors: [Color.cyan.opacity(0.82), Color.indigo.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(StoatInitials.make(name, fallback: "S"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: StoatSize.serverIcon, height: StoatSize.serverIcon)
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
    private let message: Message
    private let author: User?
    private let showsHeader: Bool
    private let statusText: String?
    private let isSelected: Bool
    private let isFocused: Bool
    private let replyPreview: String?

    public init(message: Message, author: User?, showsHeader: Bool = true, statusText: String? = nil, isSelected: Bool = false, isFocused: Bool = false, replyPreview: String? = nil) {
        self.message = message
        self.author = author
        self.showsHeader = showsHeader
        self.statusText = statusText
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.replyPreview = replyPreview
    }

    public var body: some View {
        HStack(alignment: .top, spacing: StoatSpacing.medium) {
            if showsHeader {
                AvatarView(title: authorName, size: StoatSize.avatar, isOnline: author?.online)
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
                    Text(system.content ?? "System event")
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
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
                    Text(content)
                        .font(StoatTypography.messageBody)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let attachments = message.attachments, !attachments.isEmpty {
                    ForEach(attachments) { attachment in
                        AttachmentPreviewPlaceholder(title: attachment.filename)
                    }
                }
                if let embeds = message.embeds, !embeds.isEmpty {
                    ForEach(Array(embeds.enumerated()), id: \.offset) { _, embed in
                        EmbedPreviewPlaceholder(title: embed.title ?? "Embed", subtitle: embed.description)
                    }
                }
                if !message.reactions.isEmpty {
                    HStack(spacing: StoatSpacing.small) {
                        ForEach(message.reactions.keys.sorted(), id: \.self) { key in
                            Text("\(key) \(message.reactions[key]?.count ?? 0)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, StoatSpacing.small)
                                .padding(.vertical, StoatSpacing.xSmall)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                                .accessibilityLabel(StoatAccessibility.reactionLabel(emoji: key, count: message.reactions[key]?.count ?? 0, hasReacted: false))
                        }
                    }
                    .padding(.top, StoatSpacing.xSmall)
                }
            }
        }
        .padding(.vertical, showsHeader ? StoatSpacing.small : StoatSpacing.xxSmall)
        .background(isSelected || isFocused ? Color.accentColor.opacity(isFocused ? 0.16 : 0.10) : Color.clear, in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StoatAccessibility.messageLabel(author: authorName, timestamp: timestampText, content: message.content ?? message.system?.content ?? "", isEdited: message.isEdited, isPinned: message.isPinned, reactionCount: message.reactions.values.reduce(0) { $0 + $1.count }, status: statusText, isSelected: isSelected, isFocused: isFocused, replyPreview: replyPreview))
    }

    private var authorName: String {
        message.masquerade?.name ?? author?.displayName ?? author?.username ?? message.authorID.rawValue
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
    private let title: String
    public init(title: String) { self.title = title }
    public var body: some View {
        Label(title, systemImage: "doc")
            .font(.caption)
            .padding(StoatSpacing.medium)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
    }
}

public struct EmbedPreviewPlaceholder: View {
    private let title: String
    private let subtitle: String?
    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Text(title).font(.caption.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(StoatSpacing.medium)
        .frame(maxWidth: 340, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.accentColor).frame(width: 3)
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
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
            .frame(minHeight: StoatSize.minimumRowHeight)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
        .contextMenu {
            Button("Channel settings unavailable in Phase 3") {}
                .disabled(true)
        }
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
    private let action: () -> Void

    public init(title: String, systemImage: String? = nil, isSelected: Bool = false, unreadCount: Int = 0, mentionCount: Int = 0, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
        self.isDisabled = isDisabled
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
            ServerIconView(name: title, isSelected: isSelected)
        }
    }
}

public struct MemberRow: View {
    private let user: User
    private let subtitle: String?

    public init(user: User, subtitle: String? = nil) {
        self.user = user
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: StoatSpacing.medium) {
            AvatarView(title: user.displayName ?? user.username, size: StoatSize.compactAvatar, isOnline: user.online)
            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                Text(user.displayName ?? user.username)
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
