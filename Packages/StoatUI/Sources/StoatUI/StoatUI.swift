import StoatDesignSystem
import StoatModels
import SwiftUI

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
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(.thinMaterial)
    }
}

public struct GlassToolbar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(height: 52)
            .padding(.horizontal, StoatSpacing.large)
            .background(.bar)
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
    private let onFocus: () -> Void

    public init(text: Binding<String>, placeholder: String, isEnabled: Bool = true, onFocus: @escaping () -> Void = {}) {
        self._text = text
        self.placeholder = placeholder
        self.isEnabled = isEnabled
        self.onFocus = onFocus
    }

    public var body: some View {
        GlassPanel(material: .composer, padding: StoatSpacing.medium) {
            HStack(alignment: .bottom, spacing: StoatSpacing.medium) {
                GlassIconButton("Attach file unavailable in Phase 3", systemImage: "paperclip", isDisabled: true) {}
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 34, maxHeight: 92)
                        .scrollContentBackground(.hidden)
                        .disabled(!isEnabled)
                        .onTapGesture(perform: onFocus)
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                GlassIconButton("Emoji unavailable in Phase 3", systemImage: "face.smiling", isDisabled: true) {}
                GlassIconButton("Sending unavailable in Phase 3", systemImage: "arrow.up.circle.fill", isDisabled: true) {}
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message composer placeholder")
    }
}

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

    public init(message: Message, author: User?, showsHeader: Bool = true) {
        self.message = message
        self.author = author
        self.showsHeader = showsHeader
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
                    }
                }
                if let system = message.system {
                    Text(system.content ?? "System event")
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
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
                        }
                    }
                    .padding(.top, StoatSpacing.xSmall)
                }
            }
        }
        .padding(.vertical, showsHeader ? StoatSpacing.small : StoatSpacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(authorName), \(message.content ?? "message")")
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
        .accessibilityLabel(StoatAccessibility.selectedLabel(channel.displayName, isSelected: isSelected))
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
