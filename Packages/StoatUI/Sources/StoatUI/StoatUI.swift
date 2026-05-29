import StoatDesignSystem
import StoatModels
import SwiftUI

public struct PhaseZeroShellView: View {
    public init() {}

    public var body: some View {
        NavigationSplitView {
            ServerRailPlaceholder()
                .frame(minWidth: 72, idealWidth: 84, maxWidth: 96)
        } content: {
            ChannelListPlaceholder()
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
        } detail: {
            ChatPlaceholderView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ServerRailPlaceholder: View {
    private let entries = ["Home", "Stoat", "Design", "Labs"]

    var body: some View {
        VStack(spacing: StoatSpacing.medium) {
            ForEach(entries, id: \.self) { entry in
                ZStack {
                    RoundedRectangle(cornerRadius: StoatRadius.avatar, style: .continuous)
                        .fill(entry == "Stoat" ? Color.accentColor.opacity(0.92) : Color.secondary.opacity(0.16))
                    Text(String(entry.prefix(1)))
                        .font(.headline.weight(.semibold))
                }
                .frame(width: 44, height: 44)
                .help(entry)
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
}

private struct ChannelListPlaceholder: View {
    private let channels = ["announcements", "general", "macos-native", "design-system", "api-research"]

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                Text("Stoat")
                    .font(.title3.weight(.semibold))
                Text("Phase 0 skeleton")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, StoatSpacing.large)

            List(channels, id: \.self) { channel in
                Label(channel, systemImage: channel == "general" ? "number.circle.fill" : "number")
                    .tag(channel)
            }
            .listStyle(.sidebar)
        }
        .padding(.top, StoatSpacing.large)
        .background(.thinMaterial)
    }
}

private struct ChatPlaceholderView: View {
    private let messages = [
        Message(
            id: MessageID(rawValue: "m1"),
            channelID: ChannelID(rawValue: "general"),
            authorID: UserID(rawValue: "u1"),
            content: "Welcome to Liquid Bagel. This is the native macOS shell; live Stoat data starts in Phase 1."
        ),
        Message(
            id: MessageID(rawValue: "m2"),
            channelID: ChannelID(rawValue: "general"),
            authorID: UserID(rawValue: "u2"),
            content: "Packages are wired, the app target is thin, and every network edge is still intentionally inert."
        )
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ChatHeaderPlaceholder()

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StoatSpacing.large) {
                        ForEach(messages) { message in
                            MessageRowPlaceholder(message: message)
                        }
                    }
                    .padding(StoatSpacing.xLarge)
                }

                GlassPanel {
                    HStack(spacing: StoatSpacing.medium) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                        Text("Message #general")
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

            MemberPanelPlaceholder()
                .frame(width: 240)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ChatHeaderPlaceholder: View {
    var body: some View {
        HStack(spacing: StoatSpacing.medium) {
            Label("general", systemImage: "number")
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

    var body: some View {
        HStack(alignment: .top, spacing: StoatSpacing.medium) {
            RoundedRectangle(cornerRadius: StoatRadius.avatar, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(message.authorID.rawValue == "u1" ? "L" : "S")
                        .font(.headline.weight(.semibold))
                }

            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                HStack {
                    Text(message.authorID.rawValue == "u1" ? "Liquid Bagel" : "Stoat System")
                        .font(.subheadline.weight(.semibold))
                    Text("now")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(message.content)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct MemberPanelPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            Text("Members")
                .font(.headline)

            ForEach(["Liquid Bagel", "Stoat System"], id: \.self) { member in
                HStack(spacing: StoatSpacing.medium) {
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 8, height: 8)
                    Text(member)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(StoatSpacing.large)
        .background(.thinMaterial)
    }
}
