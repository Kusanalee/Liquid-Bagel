import Foundation

public struct StoatConfig: Codable, Hashable, Sendable {
    public var revolt: String
    public var features: StoatFeatures
    public var ws: String
    public var app: String
    public var vapid: String
    public var build: BuildInformation

    public init(revolt: String, features: StoatFeatures, ws: String, app: String, vapid: String, build: BuildInformation) {
        self.revolt = revolt
        self.features = features
        self.ws = ws
        self.app = app
        self.vapid = vapid
        self.build = build
    }
}

public typealias RevoltConfig = StoatConfig

public struct StoatFeatures: Codable, Hashable, Sendable {
    public var captcha: CaptchaFeature
    public var email: Bool
    public var inviteOnly: Bool
    public var autumn: FeatureConfiguration
    public var january: FeatureConfiguration
    public var livekit: VoiceFeature
    public var limits: LimitsConfig
    public var legalLinks: LegalLinks

    public init(captcha: CaptchaFeature, email: Bool, inviteOnly: Bool, autumn: FeatureConfiguration, january: FeatureConfiguration, livekit: VoiceFeature, limits: LimitsConfig, legalLinks: LegalLinks) {
        self.captcha = captcha
        self.email = email
        self.inviteOnly = inviteOnly
        self.autumn = autumn
        self.january = january
        self.livekit = livekit
        self.limits = limits
        self.legalLinks = legalLinks
    }

    private enum CodingKeys: String, CodingKey {
        case captcha
        case email
        case inviteOnly = "invite_only"
        case autumn
        case january
        case livekit
        case limits
        case legalLinks = "legal_links"
    }
}

public struct CaptchaFeature: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var key: String

    public init(enabled: Bool, key: String) {
        self.enabled = enabled
        self.key = key
    }
}

public struct FeatureConfiguration: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var url: String

    public init(enabled: Bool, url: String) {
        self.enabled = enabled
        self.url = url
    }
}

public struct VoiceFeature: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var nodes: [VoiceNode]

    public init(enabled: Bool, nodes: [VoiceNode] = []) {
        self.enabled = enabled
        self.nodes = nodes
    }
}

public struct VoiceNode: Codable, Hashable, Sendable {
    public var name: String
    public var lat: Double
    public var lon: Double
    public var publicURL: String

    public init(name: String, lat: Double, lon: Double, publicURL: String) {
        self.name = name
        self.lat = lat
        self.lon = lon
        self.publicURL = publicURL
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case lat
        case lon
        case publicURL = "public_url"
    }
}

public struct LimitsConfig: Codable, Hashable, Sendable {
    public var global: GlobalLimits
    public var newUser: UserLimits
    public var `default`: UserLimits

    public init(global: GlobalLimits, newUser: UserLimits, default: UserLimits) {
        self.global = global
        self.newUser = newUser
        self.default = `default`
    }

    private enum CodingKeys: String, CodingKey {
        case global
        case newUser = "new_user"
        case `default`
    }
}

public struct GlobalLimits: Codable, Hashable, Sendable {
    public var groupSize: Int
    public var messageEmbeds: Int
    public var messageReplies: Int
    public var messageReactions: Int
    public var serverEmoji: Int
    public var serverRoles: Int
    public var serverChannels: Int
    public var bodyLimitSize: Int
    public var restrictServerCreation: [String]
    public var newUserHours: Int

    public init(groupSize: Int = 0, messageEmbeds: Int = 0, messageReplies: Int = 0, messageReactions: Int = 0, serverEmoji: Int = 0, serverRoles: Int = 0, serverChannels: Int = 0, bodyLimitSize: Int = 0, restrictServerCreation: [String] = [], newUserHours: Int = 0) {
        self.groupSize = groupSize
        self.messageEmbeds = messageEmbeds
        self.messageReplies = messageReplies
        self.messageReactions = messageReactions
        self.serverEmoji = serverEmoji
        self.serverRoles = serverRoles
        self.serverChannels = serverChannels
        self.bodyLimitSize = bodyLimitSize
        self.restrictServerCreation = restrictServerCreation
        self.newUserHours = newUserHours
    }

    private enum CodingKeys: String, CodingKey {
        case groupSize = "group_size"
        case messageEmbeds = "message_embeds"
        case messageReplies = "message_replies"
        case messageReactions = "message_reactions"
        case serverEmoji = "server_emoji"
        case serverRoles = "server_roles"
        case serverChannels = "server_channels"
        case bodyLimitSize = "body_limit_size"
        case restrictServerCreation = "restrict_server_creation"
        case newUserHours = "new_user_hours"
    }
}

public struct UserLimits: Codable, Hashable, Sendable {
    public var outgoingFriendRequests: Int
    public var bots: Int
    public var messageLength: Int
    public var messageAttachments: Int
    public var servers: Int
    public var voiceQuality: Int
    public var video: Bool
    public var videoResolution: [Int]
    public var videoAspectRatio: [Double]
    public var fileUploadSizeLimits: [String: Int]

    public init(outgoingFriendRequests: Int = 0, bots: Int = 0, messageLength: Int = 0, messageAttachments: Int = 0, servers: Int = 0, voiceQuality: Int = 0, video: Bool = false, videoResolution: [Int] = [], videoAspectRatio: [Double] = [], fileUploadSizeLimits: [String: Int] = [:]) {
        self.outgoingFriendRequests = outgoingFriendRequests
        self.bots = bots
        self.messageLength = messageLength
        self.messageAttachments = messageAttachments
        self.servers = servers
        self.voiceQuality = voiceQuality
        self.video = video
        self.videoResolution = videoResolution
        self.videoAspectRatio = videoAspectRatio
        self.fileUploadSizeLimits = fileUploadSizeLimits
    }

    private enum CodingKeys: String, CodingKey {
        case outgoingFriendRequests = "outgoing_friend_requests"
        case bots
        case messageLength = "message_length"
        case messageAttachments = "message_attachments"
        case servers
        case voiceQuality = "voice_quality"
        case video
        case videoResolution = "video_resolution"
        case videoAspectRatio = "video_aspect_ratio"
        case fileUploadSizeLimits = "file_upload_size_limits"
    }
}

public struct LegalLinks: Codable, Hashable, Sendable {
    public var termsOfService: String
    public var privacyPolicy: String
    public var guidelines: String

    public init(termsOfService: String = "", privacyPolicy: String = "", guidelines: String = "") {
        self.termsOfService = termsOfService
        self.privacyPolicy = privacyPolicy
        self.guidelines = guidelines
    }

    private enum CodingKeys: String, CodingKey {
        case termsOfService = "terms_of_service"
        case privacyPolicy = "privacy_policy"
        case guidelines
    }
}

public struct BuildInformation: Codable, Hashable, Sendable {
    public var commitSHA: String
    public var commitTimestamp: String
    public var semver: String
    public var originURL: String
    public var timestamp: String

    public init(commitSHA: String = "", commitTimestamp: String = "", semver: String = "", originURL: String = "", timestamp: String = "") {
        self.commitSHA = commitSHA
        self.commitTimestamp = commitTimestamp
        self.semver = semver
        self.originURL = originURL
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case commitSHA = "commit_sha"
        case commitTimestamp = "commit_timestamp"
        case semver
        case originURL = "origin_url"
        case timestamp
    }
}

