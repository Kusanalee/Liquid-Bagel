import Foundation
import StoatAPI
import StoatModels

public protocol StoatRealtimeClient: Sendable {
    var connectionState: AsyncStream<RealtimeConnectionState> { get }
    var events: AsyncStream<StoatGatewayEvent> { get }
    var diagnosticsStream: AsyncStream<RealtimeDiagnostics> { get }

    func connect(
        credential: StoatAuthCredential,
        environment: StoatAPIEnvironment,
        readyFields: Set<ReadyField>
    ) async throws

    func disconnect() async
    func send(_ event: ClientGatewayEvent) async throws
}

public struct RealtimeClientConfiguration: Hashable, Sendable {
    public var pingInterval: Duration
    public var authenticationTimeout: Duration
    public var reconnectPolicy: ReconnectPolicy
    public var includeTokenInURL: Bool

    public init(
        pingInterval: Duration = .seconds(20),
        authenticationTimeout: Duration = .seconds(10),
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        includeTokenInURL: Bool = false
    ) {
        self.pingInterval = pingInterval
        self.authenticationTimeout = authenticationTimeout
        self.reconnectPolicy = reconnectPolicy
        self.includeTokenInURL = includeTokenInURL
    }
}

public actor LiveStoatRealtimeClient: StoatRealtimeClient {
    private let transportFactory: any WebSocketTransportFactory
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: RealtimeLogger
    private let configuration: RealtimeClientConfiguration
    private let stateHub = StreamHub<RealtimeConnectionState>()
    private let eventHub = StreamHub<StoatGatewayEvent>()
    private let diagnosticsHub = StreamHub<RealtimeDiagnostics>()

    private var transport: (any WebSocketTransport)?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var desiredConnection: DesiredConnection?
    private var explicitDisconnect = false
    private var reconnectAttempt = 0
    private var diagnostics = RealtimeDiagnostics()
    private var pendingPings: [Int64: Date] = [:]

    public nonisolated var connectionState: AsyncStream<RealtimeConnectionState> {
        stateHub.stream()
    }

    public nonisolated var events: AsyncStream<StoatGatewayEvent> {
        eventHub.stream()
    }

    public nonisolated var diagnosticsStream: AsyncStream<RealtimeDiagnostics> {
        diagnosticsHub.stream()
    }

    public init(
        transportFactory: any WebSocketTransportFactory = URLSessionWebSocketTransportFactory(),
        decoder: JSONDecoder = .stoat,
        encoder: JSONEncoder = .stoat,
        configuration: RealtimeClientConfiguration = RealtimeClientConfiguration(),
        logger: RealtimeLogger = .noop
    ) {
        self.transportFactory = transportFactory
        self.decoder = decoder
        self.encoder = encoder
        self.configuration = configuration
        self.logger = logger
    }

    deinit {
        receiveTask?.cancel()
        pingTask?.cancel()
        reconnectTask?.cancel()
        stateHub.finish()
        eventHub.finish()
        diagnosticsHub.finish()
    }

    public func connect(
        credential: StoatAuthCredential,
        environment: StoatAPIEnvironment,
        readyFields: Set<ReadyField> = Set(ReadyField.allCases)
    ) async throws {
        guard !credential.token.isEmpty else {
            throw RealtimeError.missingCredential
        }

        explicitDisconnect = false
        reconnectAttempt = 0
        desiredConnection = DesiredConnection(credential: credential, environment: environment, readyFields: readyFields)
        try await openCurrentDesiredConnection(isReconnect: false)
    }

    public func disconnect() async {
        explicitDisconnect = true
        desiredConnection = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        await closeActiveTransport(reason: .requested)
        publishState(.disconnected(reason: .requested))
    }

    public func send(_ event: ClientGatewayEvent) async throws {
        guard let transport else {
            throw RealtimeError.disconnected(.unknown)
        }
        logger.debug("[C->S] \(event.debugDescription)")
        do {
            let data = try encoder.encode(event)
            guard let text = String(data: data, encoding: .utf8) else {
                throw RealtimeError.encodeFailed("Encoded event was not UTF-8")
            }
            try await transport.sendText(text)
        } catch let error as RealtimeError {
            throw error
        } catch {
            throw RealtimeError.encodeFailed(error.localizedDescription)
        }
    }

    public static func makeWebSocketURL(
        environment: StoatAPIEnvironment,
        readyFields: Set<ReadyField>,
        token: String? = nil
    ) throws -> URL {
        guard var components = URLComponents(url: environment.eventsURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "wss" || scheme == "ws"
        else {
            throw RealtimeError.invalidEventsURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { ["version", "format", "ready", "token"].contains($0.name) }
        queryItems.append(URLQueryItem(name: "version", value: "1"))
        queryItems.append(URLQueryItem(name: "format", value: "json"))
        for field in readyFields.sorted(by: { $0.rawValue < $1.rawValue }) {
            queryItems.append(URLQueryItem(name: "ready", value: field.rawValue))
        }
        if let token {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw RealtimeError.invalidEventsURL
        }
        return url
    }

    public static func redactedURLDescription(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid-url>"
        }
        components.queryItems = components.queryItems?.map { item in
            item.name == "token" ? URLQueryItem(name: item.name, value: "<redacted>") : item
        }
        return components.url?.absoluteString ?? "<invalid-url>"
    }

    private func openCurrentDesiredConnection(isReconnect: Bool) async throws {
        guard let desiredConnection else {
            throw RealtimeError.disconnected(.requested)
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        await closeActiveTransport(reason: nil)

        let tokenForURL = configuration.includeTokenInURL ? desiredConnection.credential.token : nil
        let url = try Self.makeWebSocketURL(environment: desiredConnection.environment, readyFields: desiredConnection.readyFields, token: tokenForURL)

        if isReconnect {
            diagnostics.reconnectAttempt = reconnectAttempt
            publishState(.reconnecting(attempt: reconnectAttempt, nextDelay: .zero))
        } else {
            publishState(.connecting)
        }

        let transport = transportFactory.makeTransport()
        self.transport = transport
        do {
            try await transport.connect(url: url)
            diagnostics.connectedAt = Date()
            publishDiagnostics()
            publishState(.connected)

            if !configuration.includeTokenInURL {
                publishState(.authenticating)
                try await send(.authenticate(token: desiredConnection.credential.token))
            } else {
                publishState(.authenticating)
            }

            receiveTask = Task { [weak self] in
                await self?.receiveLoop()
            }
            startPingLoop()
        } catch {
            publishState(.failed(.transport(error.localizedDescription)))
            await scheduleReconnectIfNeeded(after: .network)
            throw error
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let transport else { return }
            do {
                let text = try await transport.receiveText()
                let event = try decodeEvent(text)
                await handle(event)
            } catch is CancellationError {
                return
            } catch {
                logger.warning("Realtime receive loop ended: \(error.localizedDescription)")
                if !explicitDisconnect {
                    await scheduleReconnectIfNeeded(after: .network)
                }
                return
            }
        }
    }

    private func decodeEvent(_ text: String) throws -> StoatGatewayEvent {
        guard let data = text.data(using: .utf8) else {
            throw RealtimeError.decodeFailed("Received non-UTF8 text")
        }
        do {
            return try decoder.decode(StoatGatewayEvent.self, from: data)
        } catch {
            throw RealtimeError.decodeFailed(error.localizedDescription)
        }
    }

    private func handle(_ event: StoatGatewayEvent) async {
        diagnostics.lastReceivedEventAt = Date()
        publishDiagnostics()

        switch event {
        case let .bulk(events):
            for event in events {
                await handle(event)
            }
        case let .error(code):
            await handleGatewayError(code)
        case .authenticated:
            diagnostics.authenticatedAt = Date()
            publishDiagnostics()
            publishState(.authenticated)
            eventHub.yield(event)
        case let .pong(data):
            diagnostics.lastPongAt = Date()
            if let data, let sentAt = pendingPings.removeValue(forKey: data) {
                diagnostics.lastLatencyMilliseconds = Int(Date().timeIntervalSince(sentAt) * 1000)
            }
            publishDiagnostics()
            eventHub.yield(event)
        case .ready:
            diagnostics.readyAt = Date()
            diagnostics.lastNonControlEventAt = Date()
            publishDiagnostics()
            reconnectAttempt = 0
            publishState(.ready)
            eventHub.yield(event)
        case .logout:
            diagnostics.lastNonControlEventAt = Date()
            publishDiagnostics()
            eventHub.yield(event)
            await closeActiveTransport(reason: .loggedOut)
            publishState(.disconnected(reason: .loggedOut))
        default:
            diagnostics.lastNonControlEventAt = Date()
            publishDiagnostics()
            eventHub.yield(event)
        }
    }

    private func handleGatewayError(_ code: GatewayErrorCode) async {
        eventHub.yield(.error(code))
        switch code {
        case .invalidSession:
            await closeActiveTransport(reason: .invalidSession)
            publishState(.failed(.authenticationFailed(code)))
        case .onboardingNotFinished:
            await closeActiveTransport(reason: .unknown)
            publishState(.failed(.onboardingNotFinished))
        case .alreadyAuthenticated:
            publishState(.authenticated)
        default:
            await closeActiveTransport(reason: .network)
            publishState(.failed(.authenticationFailed(code)))
            await scheduleReconnectIfNeeded(after: .network)
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        let interval = configuration.pingInterval
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.sendPing()
            }
        }
    }

    private func sendPing() async {
        let data = Int64(Date().timeIntervalSince1970 * 1000)
        pendingPings[data] = Date()
        do {
            try await send(.ping(data: data))
        } catch {
            logger.warning("Failed to send realtime ping: \(error.localizedDescription)")
        }
    }

    private func scheduleReconnectIfNeeded(after reason: RealtimeDisconnectReason) async {
        guard !explicitDisconnect, desiredConnection != nil else {
            publishState(.disconnected(reason: reason))
            return
        }
        reconnectAttempt += 1
        if let maximumAttempts = configuration.reconnectPolicy.maximumAttempts, reconnectAttempt > maximumAttempts {
            publishState(.failed(.disconnected(reason)))
            return
        }
        let delay = configuration.reconnectPolicy.delay(forAttempt: reconnectAttempt)
        diagnostics.reconnectAttempt = reconnectAttempt
        publishDiagnostics()
        publishState(.reconnecting(attempt: reconnectAttempt, nextDelay: delay))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            do {
                try await self?.openCurrentDesiredConnection(isReconnect: true)
            } catch {
                await self?.scheduleReconnectIfNeeded(after: .network)
            }
        }
    }

    private func closeActiveTransport(reason: RealtimeDisconnectReason?) async {
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        pendingPings.removeAll()
        if let transport {
            await transport.close(code: .normalClosure, reason: nil)
        }
        transport = nil
        if let reason {
            publishState(.disconnected(reason: reason))
        }
    }

    private func publishState(_ state: RealtimeConnectionState) {
        stateHub.yield(state)
    }

    private func publishDiagnostics() {
        diagnosticsHub.yield(diagnostics)
    }
}

private struct DesiredConnection: Sendable {
    var credential: StoatAuthCredential
    var environment: StoatAPIEnvironment
    var readyFields: Set<ReadyField>
}
