//  Phase 74 -- getting back online.
//
//  The property worth protecting is that two retry loops never race. The realtime client owns
//  exponential backoff for its own socket failures; the supervisor owns wake and network-path
//  recovery. Whenever the client is mid-backoff, the supervisor must stand down.

import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import XCTest
@testable import StoatFeatures

extension StoatFeaturesTests {

    // MARK: - Policy

    func testPhase74SupervisorStandsDownWhileClientBackoffIsRunning() {
        // The whole point. `.reconnecting` is the client counting down its own retry; starting a
        // second attempt on top of it is what this policy exists to prevent.
        let decision = ConnectivityPolicy.decide(
            trigger: .networkPath,
            connectionState: .reconnecting(attempt: 2, nextDelay: .seconds(4)),
            pathStatus: .satisfied,
            lastAttemptAt: nil,
            now: Date()
        )
        XCTAssertEqual(decision, .suppressedBackoffActive)
    }

    func testPhase74SupervisorStandsDownWhileAlreadyConnectedOrConnecting() {
        for state: RealtimeConnectionState in [.connecting, .connected, .authenticating, .authenticated, .ready] {
            XCTAssertEqual(
                ConnectivityPolicy.decide(trigger: .wake, connectionState: state, pathStatus: .satisfied, lastAttemptAt: nil, now: Date()),
                .suppressedBackoffActive,
                "\(state) should not be interrupted"
            )
        }
    }

    func testPhase74SupervisorConnectsFromTerminalStates() {
        for state: RealtimeConnectionState in [.idle, .disconnected(reason: .requested), .failed(.missingCredential)] {
            XCTAssertEqual(
                ConnectivityPolicy.decide(trigger: .wake, connectionState: state, pathStatus: .satisfied, lastAttemptAt: nil, now: Date()),
                .connect,
                "\(state) is terminal and should be recoverable"
            )
        }
    }

    func testPhase74UnknownPathIsNotTreatedAsOffline() {
        // At launch no path update has arrived yet. Refusing to connect on `.unknown` would
        // strand a session that never receives one.
        XCTAssertEqual(
            ConnectivityPolicy.decide(trigger: .foreground, connectionState: .idle, pathStatus: .unknown, lastAttemptAt: nil, now: Date()),
            .connect
        )
        XCTAssertEqual(
            ConnectivityPolicy.decide(trigger: .foreground, connectionState: .idle, pathStatus: .unsatisfied, lastAttemptAt: nil, now: Date()),
            .suppressedOffline
        )
    }

    func testPhase74CooldownsScaleWithHowStrongTheSignalIs() {
        let now = Date()
        // A wake is rare and decisive; activating the app is neither.
        XCTAssertLessThan(ConnectivityPolicy.cooldown(for: .wake), ConnectivityPolicy.cooldown(for: .networkPath))
        XCTAssertLessThan(ConnectivityPolicy.cooldown(for: .networkPath), ConnectivityPolicy.cooldown(for: .foreground))

        // Path flap: several transitions inside the cooldown collapse to nothing after the first.
        let justTried = now.addingTimeInterval(-1)
        XCTAssertEqual(
            ConnectivityPolicy.decide(trigger: .networkPath, connectionState: .idle, pathStatus: .satisfied, lastAttemptAt: justTried, now: now),
            .suppressedCooldown
        )
        let longAgo = now.addingTimeInterval(-60)
        XCTAssertEqual(
            ConnectivityPolicy.decide(trigger: .networkPath, connectionState: .idle, pathStatus: .satisfied, lastAttemptAt: longAgo, now: now),
            .connect
        )
    }

    // MARK: - Supervisor

    @MainActor
    func testPhase74LosingTheNetworkDoesNotTearDownTheConnection() async throws {
        // The socket fails on its own. Tearing it down here would race the client's own error
        // handling; what the path status buys is accurate wording, not intervention.
        let monitor = StaticNetworkPathMonitor(initial: .satisfied)
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(user: User(id: "u", username: "u")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.connected, .ready]) },
            networkPathMonitor: monitor
        )
        await coordinator.startConnectivitySupervision()
        await coordinator.startLiveFirstSession()
        for _ in 0..<30 where coordinator.sessionState != .connected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(coordinator.sessionState, .connected)

        await monitor.send(.unsatisfied)
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(coordinator.sessionState, .connected)
        XCTAssertEqual(coordinator.networkPathStatus, .unsatisfied)
    }

    @MainActor
    func testPhase74SleepDisconnectsAndWakeReconnects() async throws {
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connected, .ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(user: User(id: "u", username: "u")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime },
            networkPathMonitor: StaticNetworkPathMonitor(initial: .satisfied)
        )
        await coordinator.startConnectivitySupervision()
        await coordinator.startLiveFirstSession()
        for _ in 0..<30 where coordinator.sessionState != .connected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let connectsBeforeSleep = await realtime.connectCallCount

        await coordinator.handleSystemPowerEvent(.willSleep)
        XCTAssertEqual(coordinator.connectionState, .disconnected(reason: .requested))
        XCTAssertEqual(coordinator.connectivityDiagnostics.sleepSuspensionCount, 1)

        await coordinator.handleSystemPowerEvent(.didWake)
        // The wake attempt waits for the network to settle before trying.
        try await Task.sleep(for: ConnectivityPolicy.wakeSettleDelay + .milliseconds(400))

        XCTAssertEqual(coordinator.connectivityDiagnostics.wakeTriggeredConnectCount, 1)
        let connectsAfterWake = await realtime.connectCallCount
        XCTAssertGreaterThan(connectsAfterWake, connectsBeforeSleep)
    }

    @MainActor
    func testPhase74WakeWithoutASleepDoesNothing() async throws {
        // A stray didWake -- or one delivered before this process was watching -- must not
        // trigger a connection the app did not otherwise want.
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(user: User(id: "u", username: "u")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.connected, .ready]) },
            networkPathMonitor: StaticNetworkPathMonitor(initial: .satisfied)
        )
        await coordinator.startConnectivitySupervision()

        await coordinator.handleSystemPowerEvent(.didWake)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(coordinator.connectivityDiagnostics.wakeTriggeredConnectCount, 0)
    }

    @MainActor
    func testPhase74SupervisionDoesNothingWithoutASavedCredential() async throws {
        // Signed out is not a connectivity problem, and retrying it forever would be noise.
        let monitor = StaticNetworkPathMonitor(initial: .unsatisfied)
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connected, .ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(user: User(id: "u", username: "u")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime },
            networkPathMonitor: monitor
        )
        await coordinator.startConnectivitySupervision()

        await monitor.send(.satisfied)
        try await Task.sleep(for: ConnectivityPolicy.pathSettleDelay + .milliseconds(300))

        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 0)
    }
}
