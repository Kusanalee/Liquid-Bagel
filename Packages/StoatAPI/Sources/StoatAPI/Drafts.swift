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

public struct MessageEditDraft: Codable, Hashable, Sendable {
    public var content: String?
    public var embeds: [SendableEmbed]?

    public init(content: String? = nil, embeds: [SendableEmbed]? = nil) {
        self.content = content
        self.embeds = embeds
    }
}

