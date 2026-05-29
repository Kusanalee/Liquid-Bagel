import Foundation

public struct StoatAPIEnvironment: Codable, Hashable, Sendable {
    public var apiBaseURL: URL
    public var eventsURL: URL
    public var mediaBaseURL: URL?
    public var proxyBaseURL: URL?
    public var appBaseURL: URL?

    public var eventsWebSocketURL: URL {
        get { eventsURL }
        set { eventsURL = newValue }
    }

    public init(
        apiBaseURL: URL,
        eventsURL: URL,
        mediaBaseURL: URL? = nil,
        proxyBaseURL: URL? = nil,
        appBaseURL: URL? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.eventsURL = eventsURL
        self.mediaBaseURL = mediaBaseURL
        self.proxyBaseURL = proxyBaseURL
        self.appBaseURL = appBaseURL
    }

    public static let production = StoatAPIEnvironment(
        apiBaseURL: URL(string: "https://api.stoat.chat")!,
        eventsURL: URL(string: "wss://events.stoat.chat")!,
        mediaBaseURL: URL(string: "https://cdn.stoatusercontent.com")!,
        proxyBaseURL: URL(string: "https://proxy.stoatusercontent.com")!,
        appBaseURL: URL(string: "https://stoat.chat")!
    )

    public static let official = production

    public static func custom(
        apiBaseURL: URL,
        eventsURL: URL,
        mediaBaseURL: URL? = nil,
        proxyBaseURL: URL? = nil,
        appBaseURL: URL? = nil
    ) throws -> StoatAPIEnvironment {
        let environment = StoatAPIEnvironment(
            apiBaseURL: apiBaseURL,
            eventsURL: eventsURL,
            mediaBaseURL: mediaBaseURL,
            proxyBaseURL: proxyBaseURL,
            appBaseURL: appBaseURL
        )
        try environment.validate()
        return environment
    }

    public func validate() throws {
        try validateHTTPURL(apiBaseURL, name: "apiBaseURL")
        try validateWebSocketURL(eventsURL, name: "eventsURL")
        try mediaBaseURL.map { try validateHTTPURL($0, name: "mediaBaseURL") }
        try proxyBaseURL.map { try validateHTTPURL($0, name: "proxyBaseURL") }
        try appBaseURL.map { try validateHTTPURL($0, name: "appBaseURL") }
    }

    private func validateHTTPURL(_ url: URL, name: String) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            throw StoatAPIError.invalidEnvironment("\(name) must include a scheme and host")
        }
        if scheme == "https" || isLocalhost(host) && scheme == "http" {
            return
        }
        throw StoatAPIError.invalidEnvironment("\(name) must use HTTPS unless it points to localhost")
    }

    private func validateWebSocketURL(_ url: URL, name: String) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            throw StoatAPIError.invalidEnvironment("\(name) must include a scheme and host")
        }
        if scheme == "wss" || isLocalhost(host) && scheme == "ws" {
            return
        }
        throw StoatAPIError.invalidEnvironment("\(name) must use WSS unless it points to localhost")
    }

    private func isLocalhost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

