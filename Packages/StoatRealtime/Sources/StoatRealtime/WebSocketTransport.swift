import Foundation

public enum WebSocketCloseCode: Int, Hashable, Sendable {
    case normalClosure = 1000
    case goingAway = 1001
    case protocolError = 1002
    case unsupportedData = 1003
    case invalidFramePayloadData = 1007
    case policyViolation = 1008
    case messageTooBig = 1009
    case mandatoryExtensionMissing = 1010
    case internalServerError = 1011
    case unknown = -1
}

public protocol WebSocketTransport: Sendable {
    func connect(url: URL) async throws
    func sendText(_ text: String) async throws
    func receiveText() async throws -> String
    func close(code: WebSocketCloseCode, reason: Data?) async
}

public protocol WebSocketTransportFactory: Sendable {
    func makeTransport() -> any WebSocketTransport
}

public struct URLSessionWebSocketTransportFactory: WebSocketTransportFactory {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func makeTransport() -> any WebSocketTransport {
        URLSessionWebSocketTransport(session: session)
    }
}

public actor URLSessionWebSocketTransport: WebSocketTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(url: URL) async throws {
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    public func sendText(_ text: String) async throws {
        guard let task else {
            throw RealtimeError.disconnected(.unknown)
        }
        try await task.send(.string(text))
    }

    public func receiveText() async throws -> String {
        guard let task else {
            throw RealtimeError.disconnected(.unknown)
        }
        let message = try await task.receive()
        switch message {
        case let .string(text):
            return text
        case .data:
            throw RealtimeError.transport("Binary WebSocket messages are not supported for JSON realtime")
        @unknown default:
            throw RealtimeError.transport("Unknown WebSocket message")
        }
    }

    public func close(code: WebSocketCloseCode = .normalClosure, reason: Data? = nil) async {
        task?.cancel(with: code.urlSessionCode, reason: reason)
        task = nil
    }
}

private extension WebSocketCloseCode {
    var urlSessionCode: URLSessionWebSocketTask.CloseCode {
        switch self {
        case .normalClosure:
            .normalClosure
        case .goingAway:
            .goingAway
        case .protocolError:
            .protocolError
        case .unsupportedData:
            .unsupportedData
        case .invalidFramePayloadData:
            .invalidFramePayloadData
        case .policyViolation:
            .policyViolation
        case .messageTooBig:
            .messageTooBig
        case .mandatoryExtensionMissing:
            .mandatoryExtensionMissing
        case .internalServerError:
            .internalServerError
        case .unknown:
            .invalid
        }
    }
}
