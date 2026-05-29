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

public final class ScriptedWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var connectedURL: URL?
    public private(set) var sentTexts: [String] = []
    public private(set) var closeCalls: [(WebSocketCloseCode, Data?)] = []
    private var receiveQueue: [Result<String, Error>]
    private var receiveContinuations: [CheckedContinuation<String, Error>] = []

    public init(receiveQueue: [Result<String, Error>] = []) {
        self.receiveQueue = receiveQueue
    }

    public func connect(url: URL) async throws {
        setConnectedURL(url)
    }

    private func setConnectedURL(_ url: URL) {
        lock.lock()
        connectedURL = url
        lock.unlock()
    }

    public func sendText(_ text: String) async throws {
        appendSentText(text)
    }

    private func appendSentText(_ text: String) {
        lock.lock()
        sentTexts.append(text)
        lock.unlock()
    }

    public func receiveText() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !receiveQueue.isEmpty {
                let result = receiveQueue.removeFirst()
                lock.unlock()
                continuation.resume(with: result)
            } else {
                receiveContinuations.append(continuation)
                lock.unlock()
            }
        }
    }

    public func close(code: WebSocketCloseCode, reason: Data?) async {
        let continuations = recordClose(code: code, reason: reason)
        for continuation in continuations {
            continuation.resume(throwing: RealtimeError.disconnected(.requested))
        }
    }

    private func recordClose(code: WebSocketCloseCode, reason: Data?) -> [CheckedContinuation<String, Error>] {
        lock.lock()
        closeCalls.append((code, reason))
        let continuations = receiveContinuations
        receiveContinuations.removeAll()
        lock.unlock()
        return continuations
    }

    public func enqueueText(_ text: String) {
        enqueue(.success(text))
    }

    public func enqueueFailure(_ error: Error) {
        enqueue(.failure(error))
    }

    private func enqueue(_ result: Result<String, Error>) {
        lock.lock()
        if !receiveContinuations.isEmpty {
            let continuation = receiveContinuations.removeFirst()
            lock.unlock()
            continuation.resume(with: result)
        } else {
            receiveQueue.append(result)
            lock.unlock()
        }
    }
}

public final class ScriptedWebSocketTransportFactory: WebSocketTransportFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [ScriptedWebSocketTransport]

    public init(transports: [ScriptedWebSocketTransport]) {
        self.transports = transports
    }

    public func makeTransport() -> any WebSocketTransport {
        lock.lock()
        defer { lock.unlock() }
        if transports.isEmpty {
            return ScriptedWebSocketTransport()
        }
        return transports.removeFirst()
    }
}

public typealias MockWebSocketTransport = ScriptedWebSocketTransport
