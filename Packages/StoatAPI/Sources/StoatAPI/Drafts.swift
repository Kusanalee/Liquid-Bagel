import Foundation
import StoatModels

public struct MessageDraft: Codable, Hashable, Sendable {
    public var content: String?
    public var nonce: String?
    public var attachments: [FileID]?
    public var replies: [MessageReply]?
    public var embeds: [SendableEmbed]?
    public var masquerade: Masquerade?
    public var interactions: MessageInteractions?
    public var flags: MessageFlags?

    public init(
        content: String? = nil,
        nonce: String? = nil,
        attachments: [FileID]? = nil,
        replies: [MessageReply]? = nil,
        embeds: [SendableEmbed]? = nil,
        masquerade: Masquerade? = nil,
        interactions: MessageInteractions? = nil,
        flags: MessageFlags? = nil
    ) {
        self.content = content
        self.nonce = nonce
        self.attachments = attachments
        self.replies = replies
        self.embeds = embeds
        self.masquerade = masquerade
        self.interactions = interactions
        self.flags = flags
    }
}

struct MessageSendWireDraft: Codable, Hashable, Sendable {
    var content: String?
    var attachments: [FileID]?
    var replies: [MessageReply]?
    var embeds: [SendableEmbed]?
    var masquerade: Masquerade?
    var interactions: MessageInteractions?
    var flags: MessageFlags?

    init(_ draft: MessageDraft) {
        self.content = draft.content
        self.attachments = draft.attachments
        self.replies = draft.replies
        self.embeds = draft.embeds
        self.masquerade = draft.masquerade
        self.interactions = draft.interactions
        self.flags = draft.flags
    }
}

public struct MessageEditDraft: Codable, Hashable, Sendable {
    public var content: String?
    public var embeds: [SendableEmbed]?

    public init(content: String? = nil, embeds: [SendableEmbed]? = nil) {
        self.content = content
        self.embeds = embeds
    }
}
