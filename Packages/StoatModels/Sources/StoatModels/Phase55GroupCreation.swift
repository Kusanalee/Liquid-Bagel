import Foundation

/// Body for the verified `POST /channels/create` group-channel route (`DataCreateGroup`).
/// `users` must be friends of the current user per the generated API schema.
public struct GroupChannelCreateDraft: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var users: [UserID]
    public var nsfw: Bool?

    public init(name: String, description: String? = nil, users: [UserID] = [], nsfw: Bool? = nil) {
        self.name = name
        self.description = description
        self.users = users
        self.nsfw = nsfw
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validatedForCreate: GroupChannelCreateDraft? {
        let trimmed = trimmedName
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return nil }
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GroupChannelCreateDraft(
            name: trimmed,
            description: trimmedDescription?.isEmpty == true ? nil : trimmedDescription,
            users: users,
            nsfw: nsfw
        )
    }
}
