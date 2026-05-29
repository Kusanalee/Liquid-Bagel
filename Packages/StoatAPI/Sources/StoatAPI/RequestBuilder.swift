import Foundation
import StoatModels

public enum HTTPMethod: String, Codable, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public enum StoatRequestBase: Codable, Hashable, Sendable {
    case api
    case media
}

public enum RequestBody: Hashable, Sendable {
    case json(Data)
    case multipart(data: Data, boundary: String)
    case raw(data: Data, contentType: String)

    public var data: Data {
        switch self {
        case let .json(data), let .multipart(data, _), let .raw(data, _):
            data
        }
    }

    public var contentType: String {
        switch self {
        case .json:
            "application/json"
        case let .multipart(_, boundary):
            "multipart/form-data; boundary=\(boundary)"
        case let .raw(_, contentType):
            contentType
        }
    }
}

public struct StoatRequest<Response: Decodable & Sendable>: Sendable {
    public var base: StoatRequestBase
    public var method: HTTPMethod
    public var path: String
    public var queryItems: [URLQueryItem]
    public var body: RequestBody?
    public var headers: [String: String]
    public var requiresAuthentication: Bool

    public init(
        base: StoatRequestBase = .api,
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: RequestBody? = nil,
        headers: [String: String] = [:],
        requiresAuthentication: Bool = true
    ) {
        self.base = base
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.headers = headers
        self.requiresAuthentication = requiresAuthentication
    }
}

public struct StoatRequestBuilder: Sendable {
    public var environment: StoatAPIEnvironment
    public var userAgent: String

    public init(environment: StoatAPIEnvironment, userAgent: String = "LiquidBagel/0.1 macOS") {
        self.environment = environment
        self.userAgent = userAgent
    }

    public func build<Response: Decodable & Sendable>(
        _ request: StoatRequest<Response>,
        credential: StoatAuthCredential?
    ) throws -> URLRequest {
        let baseURL: URL
        switch request.base {
        case .api:
            baseURL = environment.apiBaseURL
        case .media:
            guard let mediaBaseURL = environment.mediaBaseURL else {
                throw StoatAPIError.invalidEnvironment("mediaBaseURL is required for upload requests")
            }
            baseURL = mediaBaseURL
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw StoatAPIError.invalidURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/")
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }

        guard let url = components.url else {
            throw StoatAPIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        if request.requiresAuthentication {
            guard let credential else {
                throw StoatAPIError.missingAuthentication
            }
            urlRequest.setValue(credential.token, forHTTPHeaderField: credential.headerName)
        }

        if let body = request.body {
            urlRequest.httpBody = body.data
            urlRequest.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        }

        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        return urlRequest
    }
}

public enum MultipartFormData {
    public static func fileBody(
        fieldName: String = "file",
        data: Data,
        filename: String,
        mimeType: String,
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) -> RequestBody {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return .multipart(data: body, boundary: boundary)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

extension String {
    var stoatPathComponentEscaped: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

