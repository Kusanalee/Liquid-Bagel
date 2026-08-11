//  Moved out of the StoatRealtime library in Phase 73.
//  Test-only: zero production references, but it shipped in the library target.

import Foundation
import StoatModels
@testable import StoatRealtime

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

