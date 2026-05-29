import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> StoatHTTPResponse
}

public struct URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> StoatHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StoatAPIError.invalidResponseTransport
            }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String {
                    result[key] = String(describing: pair.value)
                }
            }
            return StoatHTTPResponse(statusCode: httpResponse.statusCode, headers: headers, data: data)
        } catch let error as StoatAPIError {
            throw error
        } catch {
            throw StoatAPIError.transport(error.localizedDescription)
        }
    }
}

private extension StoatAPIError {
    static var invalidResponseTransport: StoatAPIError {
        .transport("Response was not an HTTP response")
    }
}

