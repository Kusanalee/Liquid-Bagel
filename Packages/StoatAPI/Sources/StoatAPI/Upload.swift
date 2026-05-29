import Foundation
import StoatModels

public enum UploadTag: Codable, Hashable, Sendable {
    case attachments
    case avatars
    case backgrounds
    case icons
    case banners
    case emojis
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "attachments": self = .attachments
        case "avatars": self = .avatars
        case "backgrounds": self = .backgrounds
        case "icons": self = .icons
        case "banners": self = .banners
        case "emojis": self = .emojis
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .attachments: "attachments"
        case .avatars: "avatars"
        case .backgrounds: "backgrounds"
        case .icons: "icons"
        case .banners: "banners"
        case .emojis: "emojis"
        case let .unknown(value): value
        }
    }
}

public struct UploadedFile: Codable, Hashable, Sendable, Identifiable {
    public var id: FileID

    public init(id: FileID) {
        self.id = id
    }
}

