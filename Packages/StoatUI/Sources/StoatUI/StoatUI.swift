import StoatDesignSystem
import StoatModels
import SwiftUI

public struct StoatUISnapshot: Equatable, Sendable {
    public var currentUser: User?
    public var users: [User]
    public var servers: [Server]
    public var channels: [Channel]
    public var messages: [Message]

    public init(
        currentUser: User? = nil,
        users: [User] = [],
        servers: [Server] = [],
        channels: [Channel] = [],
        messages: [Message] = []
    ) {
        self.currentUser = currentUser
        self.users = users
        self.servers = servers
        self.channels = channels
        self.messages = messages
    }

    public static let placeholder = StoatUISnapshot(
        currentUser: User(id: "phase-one-user", username: "liquidbagel", displayName: "Liquid Bagel"),
        users: [
            User(id: "phase-one-user", username: "liquidbagel", displayName: "Liquid Bagel"),
            User(id: "phase-one-system", username: "stoat-system", displayName: "Stoat System")
        ],
        servers: [
            Server(id: "phase-one-server", ownerID: "phase-one-user", name: "Bagel Lab", channelIDs: ["phase-one-general"], defaultPermissions: [.viewChannel, .readMessageHistory])
        ],
        channels: [
            Channel(id: "phase-one-general", kind: .textChannel, serverID: "phase-one-server", name: "general")
        ],
        messages: [
            Message(
                id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
                channelID: "phase-one-general",
                authorID: "phase-one-user",
                content: "Welcome to Liquid Bagel. Phase 1 is loading mock Stoat data through the API protocol."
            ),
            Message(
                id: "01ARZ3NDEKTSV4RRFFQ69G5FAW",
                channelID: "phase-one-general",
                authorID: "phase-one-system",
                content: "No live token is required; this shell is still intentionally offline."
            )
        ]
    )
}

public struct PhaseZeroShellView: View {
    private let snapshot: StoatUISnapshot

    public init(snapshot: StoatUISnapshot = .placeholder) {
        self.snapshot = snapshot
    }

    public var body: some View {
        NavigationSplitView {
            ServerRailPlaceholder(servers: snapshot.servers)
                .frame(minWidth: 72, idealWidth: 84, maxWidth: 96)
        } content: {
            ChannelListPlaceholder(
                server: snapshot.servers.first,
                channels: snapshot.channels
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
        } detail: {
            ChatPlaceholderView(snapshot: snapshot)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ServerRailPlaceholder: View {
    let servers: [Server]

    var body: some View {
        VStack(spacing: StoatSpacing.medium) {
            ForEach(servers) { server in
                ZStack {
                    RoundedRectangle(cornerRadius: StoatRadius.avatar, style: .continuous)
                        .fill(server.id == servers.first?.id ? Color.accentColor.opacity(0.92) : Color.secondary.opacity(0.16))
                    Text(initials(for: server.name))
                        .font(.headline.weight(.semibold))
                }
                .frame(width: 44, height: 44)
                .help(server.name)
            }

            Spacer()

            Button {
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(GlassButtonStyle())
            .help("Settings")
        }
        .padding(.vertical, StoatSpacing.large)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "S" : String(letters).uppercased()
    }
}

private struct ChannelListPlaceholder: View {
    let server: Server?
    let channels: [Channel]

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                Text(server?.name ?? "Stoat")
                    .font(.title3.weight(.semibold))
                Text("Phase 1 mock data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, StoatSpacing.large)

            List(channels) { channel in
                Label(channel.displayName, systemImage: channel.kind == .directMessage ? "person.2" : "number")
                    .tag(channel.id)
            }
            .listStyle(.sidebar)
        }
        .padding(.top, StoatSpacing.large)
        .background(.thinMaterial)
    }
}

private struct ChatPlaceholderView: View {
    let snapshot: StoatUISnapshot

    private var currentChannel: Channel? {
        snapshot.channels.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ChatHeaderPlaceholder(channel: currentChannel)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StoatSpacing.large) {
                        ForEach(snapshot.messages) { message in
                            MessageRowPlaceholder(message: message, author: author(for: message.authorID))
                        }
                    }
                    .padding(StoatSpacing.xLarge)
                }

                GlassPanel {
                    HStack(spacing: StoatSpacing.medium) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                        Text("Message #\(currentChannel?.displayName ?? "general")")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .frame(height: 28)
                }
                .padding([.horizontal, .bottom], StoatSpacing.large)
            }
            .frame(minWidth: 520)

            Divider()

            MemberPanelPlaceholder(users: snapshot.users)
                .frame(width: 240)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func author(for id: UserID) -> User? {
        snapshot.users.first { $0.id == id }
    }
}

private struct ChatHeaderPlaceholder: View {
    let channel: Channel?

    var body: some View {
        HStack(spacing: StoatSpacing.medium) {
            Label(channel?.displayName ?? "general", systemImage: channel?.kind == .directMessage ? "person.2" : "number")
                .font(.headline)

            Spacer()

            Button {
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Search")

            Button {
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless)
            .help("Toggle Member List")
        }
        .padding(.horizontal, StoatSpacing.large)
        .frame(height: 52)
        .background(.bar)
    }
}

private struct MessageRowPlaceholder: View {
    let message: Message
    let author: User?

    var body: some View {
        HStack(alignment: .top, spacing: StoatSpacing.medium) {
            RoundedRectangle(cornerRadius: StoatRadius.avatar, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(initial)
                        .font(.headline.weight(.semibold))
                }

            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                HStack {
                    Text(author?.displayName ?? author?.username ?? message.authorID.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text(timestampText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(message.content ?? "")
                    .textSelection(.enabled)

                if !message.reactions.isEmpty {
                    HStack(spacing: StoatSpacing.small) {
                        ForEach(message.reactions.keys.sorted(), id: \.self) { key in
                            Text("\(key) \(message.reactions[key]?.count ?? 0)")
                                .font(.caption)
                                .padding(.horizontal, StoatSpacing.small)
                                .padding(.vertical, StoatSpacing.xSmall)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var initial: String {
        String((author?.displayName ?? author?.username ?? "?").prefix(1)).uppercased()
    }

    private var timestampText: String {
        guard let createdAt = message.createdAt else {
            return "now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

private struct MemberPanelPlaceholder: View {
    let users: [User]

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            Text("Members")
                .font(.headline)

            ForEach(users) { user in
                HStack(spacing: StoatSpacing.medium) {
                    Circle()
                        .fill(user.online ? Color.green.opacity(0.8) : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(user.displayName ?? user.username)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(StoatSpacing.large)
        .background(.thinMaterial)
    }
}
