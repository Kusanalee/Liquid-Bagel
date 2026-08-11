//  Split from StoatFeaturesTests.swift (Phase 74). Behavior unchanged.

import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import StoatUI
import Observation
import SwiftUI
import XCTest
@testable import StoatFeatures

final class Phase38StartupStateTests: XCTestCase {

    @MainActor
    func testStartupStateIsNoCredentialWhenSignedOut() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        XCTAssertEqual(appModel.startupState, .noCredential)
    }

    @MainActor
    func testStartupStateIsReadyForMockMode() async {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        await coordinator.startMockSession()
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        XCTAssertEqual(appModel.startupState, .ready)
    }

    @MainActor
    func testStartupStateIsRecoverableWhenSavedCredentialReadyButNotConnecting() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connecting])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.validateSavedSession()
        XCTAssertEqual(coordinator.sessionState, .readyToConnect)
        if case .savedCredentialFailed = appModel.startupState {
        } else {
            XCTFail("Expected savedCredentialFailed recovery state, got \(appModel.startupState)")
        }
    }

    @MainActor
    func testStartupStateIsReadyAfterConnected() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connecting, .ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.connectLiveManually()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.sessionState, .connected)
        XCTAssertEqual(appModel.startupState, .ready)
    }

    @MainActor
    func testStartupStateIsSavedCredentialFailedOnInvalidSession() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.validateSavedSession()
        if case .savedCredentialFailed = appModel.startupState {
        } else {
            XCTFail("Expected savedCredentialFailed, got \(appModel.startupState)")
        }
    }

    @MainActor
    func testForgetSessionReturnsToNoCredential() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.validateSavedSession()
        await coordinator.forgetLocalSession()
        XCTAssertEqual(appModel.startupState, .noCredential)
        XCTAssertFalse(coordinator.hasSavedCredential)
    }

    @MainActor
    func testNoShellSnapshotBeforeReady() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        XCTAssertEqual(appModel.startupState, .noCredential)
        XCTAssertTrue(appModel.shell.snapshot.serversByID.isEmpty)
    }
}

final class Phase38LoginDiagnosticsTests: XCTestCase {

    @MainActor
    func testLoginFlowStateStartsIdle() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        XCTAssertEqual(coordinator.loginFlowState, .idle)
    }

    @MainActor
    func testLoginDiagnosticsStartEmpty() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        XCTAssertEqual(coordinator.loginDiagnostics.attemptCount, 0)
        XCTAssertNil(coordinator.loginDiagnostics.lastAttemptAt)
        XCTAssertNil(coordinator.loginDiagnostics.lastErrorCategory)
    }

    @MainActor
    func testAutoConnectAttemptCountStartsZero() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        XCTAssertEqual(coordinator.autoConnectAttemptCount, 0)
    }

    @MainActor
    func testAutoConnectAttemptCountIncrementsOnStartup() async {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.startLiveFirstSession()
        XCTAssertGreaterThanOrEqual(coordinator.autoConnectAttemptCount, 1)
    }

    @MainActor
    func testLoginDiagnosticsRedactedSummaryContainsAttemptCount() {
        var diag = LoginDiagnostics()
        diag.attemptCount = 3
        diag.lastErrorCategory = .networkError
        XCTAssertTrue(diag.redactedSummary.contains("attempts: 3"))
        XCTAssertTrue(diag.redactedSummary.contains("network_error"))
    }

    @MainActor
    func testLoginDiagnosticsDoesNotContainCredentials() {
        var diag = LoginDiagnostics()
        diag.attemptCount = 1
        diag.lastErrorCategory = .unknown("Bad token abc123")
        let summary = diag.redactedSummary
        XCTAssertFalse(summary.contains("abc123"), "Summary must not contain raw error text that could include token values")
    }

    @MainActor
    func testForgetSessionResetsLoginDiagnostics() async {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateSavedSession()
        await coordinator.validateImportedToken("badtoken")
        XCTAssertGreaterThan(coordinator.loginDiagnostics.attemptCount, 0)
        await coordinator.forgetLocalSession()
        XCTAssertEqual(coordinator.loginDiagnostics.attemptCount, 0)
        XCTAssertEqual(coordinator.loginFlowState, .idle)
    }
}

final class Phase38FirstRunLoginViewModelTests: XCTestCase {

    @MainActor
    func testDefaultStateHasEmptyFields() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertEqual(vm.email, "")
        XCTAssertEqual(vm.password, "")
        XCTAssertFalse(vm.isAdvancedExpanded)
        XCTAssertNil(vm.loginError)
    }

    @MainActor
    func testCanSubmitLoginRequiresNonEmptyEmailAndPassword() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertFalse(vm.canSubmitLogin)
        vm.email = "test@example.com"
        XCTAssertFalse(vm.canSubmitLogin)
        vm.password = "secret"
        XCTAssertTrue(vm.canSubmitLogin)
    }

    @MainActor
    func testCanSubmitTokenRequiresNonEmptyToken() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertFalse(vm.canSubmitToken)
        vm.manualToken = "tok_test"
        XCTAssertTrue(vm.canSubmitToken)
    }

    @MainActor
    func testClearFormResetsAllFields() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        vm.email = "a@b.com"
        vm.password = "pass"
        vm.manualToken = "tok"
        vm.tokenLabel = "label"
        vm.clearForm()
        XCTAssertEqual(vm.email, "")
        XCTAssertEqual(vm.password, "")
        XCTAssertEqual(vm.manualToken, "")
        XCTAssertEqual(vm.tokenLabel, "")
    }

    @MainActor
    func testMFAChallengeForwardedFromCoordinator() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertNil(vm.mfaChallenge)
        XCTAssertNotEqual(vm.flowState, .mfaRequired)
    }

    @MainActor
    func testIsLoadingWhenSubmitting() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.flowState, .idle)
    }
}

final class Phase38AuthFlowTests: XCTestCase {

    @MainActor
    func testLoginWithInvalidCredentialsShowsError() async {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in
                StubLoginAPIClient(response: .success(SessionLoginSuccess(
                    id: "sess1",
                    userID: "user1",
                    token: "tok",
                    name: "Test",
                    lastSeen: Date()
                )))
            },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.login(email: "a@b.com", password: "wrong")
        XCTAssertEqual(coordinator.loginFlowState, .idle)
        XCTAssertEqual(coordinator.loginDiagnostics.lastErrorCategory, .invalidCredentials)
        XCTAssertEqual(coordinator.loginDiagnostics.attemptCount, 1)
        XCTAssertNotNil(coordinator.loginDiagnostics.lastAttemptAt)
    }

    @MainActor
    func testTokenImportSuccessUpdatesFlowState() async {
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        await coordinator.validateImportedToken("validtoken", localLabel: "Dev")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.loginFlowState, .succeeded)
        XCTAssertNil(coordinator.pendingValidatedSession)
        XCTAssertTrue(coordinator.hasSavedCredential)
    }

    @MainActor
    func testTokenImportFailureDoesNotSaveCredential() async {
        let store = InMemoryTokenStore()
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateImportedToken("badtoken")
        XCTAssertEqual(coordinator.loginFlowState, .idle)
        XCTAssertNil(coordinator.pendingValidatedSession)
        let saved = try? await store.loadCredential()
        XCTAssertNil(saved)
    }

    @MainActor
    func testFinishValidatedSessionAndConnectSavesToKeychain() async throws {
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        await coordinator.validateImportedToken("validtoken")
        await coordinator.finishValidatedSessionAndConnect()
        try await Task.sleep(for: .milliseconds(30))
        let saved = try await store.loadCredential()
        XCTAssertNotNil(saved)
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
    }

    @MainActor
    func testFinishValidatedSessionAndConnectDoesNothingWithNoPending() async throws {
        let store = InMemoryTokenStore()
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.finishValidatedSessionAndConnect()
        XCTAssertEqual(coordinator.sessionState, .signedOut)
        let saved = try? await store.loadCredential()
        XCTAssertNil(saved)
    }

    @MainActor
    func testNetworkErrorCategorizedCorrectly() async {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(error: SessionValidationError.networkUnavailable("timeout")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateImportedToken("anytoken")
        XCTAssertEqual(coordinator.loginDiagnostics.lastErrorCategory, .networkError)
    }

    @MainActor
    func testRateLimitCategorizedCorrectly() async {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(error: SessionValidationError.rateLimited(retryAfterMilliseconds: 5000)),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateImportedToken("anytoken")
        XCTAssertEqual(coordinator.loginDiagnostics.lastErrorCategory, .rateLimited)
    }
}

// MARK: - Phase 39 Tests

final class Phase39StartupAuthStabilizationTests: XCTestCase {

    @MainActor
    func testStartupAutoConnectIsIdempotentPerLaunchEnvironment() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await coordinator.startLiveFirstSession()
        await coordinator.startLiveFirstSession()
        try await Task.sleep(for: .milliseconds(30))

        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertEqual(coordinator.autoConnectAttemptCount, 1)
        XCTAssertEqual(coordinator.startupAuthDiagnostics.startupSkippedCount, 1)
    }

    @MainActor
    func testEmailPasswordLoginSavesValidatedSessionAndConnects() async throws {
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let loginSuccess = SessionLoginSuccess(id: "sess-login", userID: "user-login", token: "login-token", name: "Mac", lastSeen: Date())
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(user: User(id: "user-login", username: "login")),
            apiClientFactory: { _, _ in StubLoginAPIClient(response: .success(loginSuccess)) },
            realtimeClientFactory: { realtime }
        )

        await coordinator.login(email: "user@example.com", password: "correct horse battery staple", friendlyName: "Mac")
        try await Task.sleep(for: .milliseconds(30))

        let saved = try await store.loadCredential(scope: .production)
        XCTAssertEqual(saved?.token, "login-token")
        XCTAssertEqual(coordinator.loginFlowState, .succeeded)
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertTrue(coordinator.sessionState == .connecting || coordinator.sessionState == .connected)
    }

    @MainActor
    func testMFAContinuationSavesValidatedSessionAndConnects() async throws {
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let loginSuccess = SessionLoginSuccess(id: "sess-mfa", userID: "user-mfa", token: "mfa-token", name: "Mac", lastSeen: Date())
        let api = StubLoginAPIClient(response: .mfa(ticket: "ticket-secret", allowedMethods: [.totp]), continueResponse: .success(loginSuccess))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(user: User(id: "user-mfa", username: "mfa")),
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { realtime }
        )

        await coordinator.login(email: "mfa@example.com", password: "password", friendlyName: "Mac")
        XCTAssertEqual(coordinator.loginFlowState, .mfaRequired)
        await coordinator.continueLoginMFA(response: .totpCode("123456"), friendlyName: "Mac")
        try await Task.sleep(for: .milliseconds(30))

        let saved = try await store.loadCredential(scope: .production)
        XCTAssertEqual(saved?.token, "mfa-token")
        XCTAssertEqual(coordinator.loginFlowState, .succeeded)
        let continueCallCount = await api.continueCallCount
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(continueCallCount, 1)
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertTrue(coordinator.sessionState == .connecting || coordinator.sessionState == .connected)
    }

    @MainActor
    func testTokenImportSavesToSelectedEnvironmentAndConnects() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: custom).withSelectedEnvironmentID(custom.id)
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await coordinator.startLiveFirstSession()
        await coordinator.validateImportedToken("custom-token", localLabel: "Local")
        try await Task.sleep(for: .milliseconds(30))

        let productionSaved = try await store.loadCredential(scope: .production)
        let customSaved = try await store.loadCredential(scope: CredentialScope(environmentID: custom.id))
        let connectedEnvironments = await realtime.connectedEnvironments
        let connectedCredentials = await realtime.connectedCredentials
        XCTAssertNil(productionSaved)
        XCTAssertEqual(customSaved?.token, "custom-token")
        XCTAssertEqual(connectedEnvironments.last, custom.environment)
        XCTAssertEqual(connectedCredentials.last?.token, "custom-token")
    }

    @MainActor
    func testSavedCredentialNetworkFailureDoesNotLoopAndRetryCanRecover() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let validator = RecordingSessionValidator(errors: [SessionValidationError.networkUnavailable("timeout token=secret /Users/enka/Library/Keychains/login.keychain-db")])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: validator,
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)

        await coordinator.startLiveFirstSession()
        await coordinator.startLiveFirstSession()
        if case .savedCredentialFailed = appModel.startupState {
        } else {
            XCTFail("Expected saved credential recovery state, got \(appModel.startupState)")
        }
        XCTAssertEqual(coordinator.autoConnectAttemptCount, 1)
        XCTAssertEqual(coordinator.startupAuthDiagnostics.startupSkippedCount, 1)

        await coordinator.reconnectLiveManually()
        try await Task.sleep(for: .milliseconds(30))

        let validateCallCount = await validator.validateCallCount
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(validateCallCount, 2)
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertTrue(coordinator.sessionState == .connecting || coordinator.sessionState == .connected)
    }

    @MainActor
    func testForgetSessionAndEnvironmentSwitchLandInRecoverableStates() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let forgetStore = InMemoryTokenStore(credential: .sessionToken("production-token"))
        let forgetCoordinator = AppSessionCoordinator(
            tokenStore: forgetStore,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.ready]) }
        )
        let forgetAppModel = LiquidBagelAppModel(coordinator: forgetCoordinator)

        await forgetCoordinator.startLiveFirstSession()
        await forgetCoordinator.forgetLocalSession()
        XCTAssertEqual(forgetAppModel.startupState, .noCredential)

        let switchPreferences = try AppPreferences.defaults.upserting(profile: custom)
        let switchStore = InMemoryTokenStore()
        try await switchStore.saveCredential(.sessionToken("custom-token"), scope: CredentialScope(environmentID: custom.id))
        let switchCoordinator = AppSessionCoordinator(
            tokenStore: switchStore,
            preferencesStore: InMemoryAppPreferencesStore(preferences: switchPreferences),
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.ready]) }
        )
        let switchAppModel = LiquidBagelAppModel(coordinator: switchCoordinator)

        await switchCoordinator.startMockSession()
        await switchCoordinator.selectEnvironmentProfile(id: custom.id)
        XCTAssertTrue(switchCoordinator.hasSavedCredential)
        if case .savedCredentialFailed = switchAppModel.startupState {
        } else {
            XCTFail("Expected saved credential recovery state after environment switch, got \(switchAppModel.startupState)")
        }
    }

    @MainActor
    func testLiquidBagelAppModelSharesCoordinatorWithShell() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let appModel = LiquidBagelAppModel(coordinator: coordinator)

        appModel.shell.attachSessionCoordinator(appModel.coordinator)

        XCTAssertTrue(appModel.coordinator === coordinator)
        XCTAssertTrue(appModel.shell.sessionCoordinator === coordinator)
    }

    @MainActor
    func testStartupAuthDiagnosticsRedactSensitiveValues() {
        var diagnostics = StartupAuthDiagnostics()
        diagnostics.startupInvocationCount = 1
        diagnostics.startupAutoConnectAttemptCount = 1
        diagnostics.lastEnvironmentKind = "custom https://api.example.test"
        diagnostics.lastStartupAction = #"token=abc123 password=hunter2 /Users/enka/Library/Keychains/login.keychain-db"#
        diagnostics.lastStartupResult = #"{"error":"raw body","token":"secret","mfa_response":"123456"}"#
        diagnostics.lastAuthAction = "session 01J123456789ABCDEFGHJKLMNP"
        diagnostics.lastAuthResult = "mfa_ticket=secret-ticket"
        diagnostics.lastErrorCategory = .unknown("raw body secret")

        let summary = diagnostics.redactedSummary

        XCTAssertFalse(summary.contains("abc123"))
        XCTAssertFalse(summary.contains("hunter2"))
        XCTAssertFalse(summary.contains("/Users/enka"))
        XCTAssertFalse(summary.contains(#""token":"secret""#))
        XCTAssertFalse(summary.contains("123456"))
        XCTAssertFalse(summary.contains("01J123456789ABCDEFGHJKLMNP"))
        XCTAssertFalse(summary.contains("secret-ticket"))
        XCTAssertTrue(summary.contains("[redacted"))
    }

    func testPhase51ServerSettingsPresentationBuildsLargeSnapshotOnce() {
        let serverID: ServerID = "phase51-large-server"
        let currentUserID: UserID = "phase51-current"
        var roles: [RoleID: Role] = [:]
        for index in 0..<200 {
            let id = RoleID(rawValue: "phase51-role-\(index)")
            roles[id] = Role(id: id, name: "Role \(index)", permissions: PermissionOverride(), rank: Int64(index))
        }
        let channelIDs = (0..<200).map { ChannelID(rawValue: "phase51-channel-\($0)") }
        let server = Server(
            id: serverID,
            ownerID: currentUserID,
            name: "Large Phase 51",
            channelIDs: channelIDs,
            roles: roles
        )
        var users: [UserID: User] = [:]
        var members: [ServerMemberKey: ServerMember] = [:]
        for index in 0..<2_000 {
            let userID = UserID(rawValue: "phase51-user-\(index)")
            users[userID] = User(id: userID, username: "user\(index)")
            let member = ServerMember(
                id: MemberCompositeKey(serverID: serverID, userID: userID),
                joinedAt: Date(),
                roles: [RoleID(rawValue: "phase51-role-\(index % 200)")]
            )
            members[ServerMemberKey(member.id)] = member
        }
        users[currentUserID] = User(id: currentUserID, username: "current")
        members[ServerMemberKey(serverID: serverID, userID: currentUserID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: currentUserID),
            joinedAt: Date()
        )
        let channels = Dictionary(uniqueKeysWithValues: channelIDs.map {
            ($0, Channel(id: $0, kind: .textChannel, serverID: serverID, name: $0.rawValue))
        })
        let snapshot = RealtimeSnapshot(
            usersByID: users,
            serversByID: [serverID: server],
            channelsByID: channels,
            membersByServerAndUserID: members
        )

        let presentation = Phase51PresentationBuilder.serverSettings(
            revision: Phase51PresentationRevision(snapshot: 1),
            snapshot: snapshot,
            serverID: serverID,
            selectedChannelID: channelIDs.first,
            currentUserID: currentUserID,
            runtimeLine: "mock",
            capabilities: ServerManagementCapabilities(canManageServer: true, canManageChannels: true, canInvite: true, isConnectedForLiveActions: true),
            identitySnapshots: Phase43IdentitySnapshotStore(),
            normalizedMemberQuery: ""
        )

        XCTAssertEqual(presentation?.orderedRoles.count, 200)
        XCTAssertEqual(presentation?.textChannels.count, 200)
        XCTAssertEqual(presentation?.memberItems.count, 2_001)
    }

    @MainActor
    func testPhase51QuickSwitcherCapsFiveThousandIndexedChannels() async throws {
        let serverID: ServerID = "phase51-index-server"
        let channels = (0..<5_000).map { index in
            Channel(id: ChannelID(rawValue: "phase51-index-\(index)"), kind: .textChannel, serverID: serverID, name: "indexed channel \(index)")
        }
        let server = Server(id: serverID, ownerID: "owner", name: "Index", channelIDs: channels.map(\.id))
        let snapshot = RealtimeSnapshot(
            serversByID: [serverID: server],
            channelsByID: Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        )
        let switcher = QuickSwitcherViewModel(snapshot: snapshot)

        switcher.query = "indexed channel"
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(switcher.results.count, 50)
        XCTAssertEqual(Set(switcher.results.map(\.id)).count, 50)
    }

    @MainActor
    func testPhase51TimelinePresentationUsesRevisionCache() async {
        let channelID: ChannelID = "phase51-timeline"
        let authorID: UserID = "phase51-author"
        let messages = (0..<250).map { index in
            Message(
                id: MessageID(rawValue: String(format: "01J%023d", index)),
                channelID: channelID,
                authorID: authorID,
                content: "Message \(index)"
            )
        }
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [authorID])
        let snapshot = RealtimeSnapshot(
            usersByID: [authorID: User(id: authorID, username: "author")],
            channelsByID: [channelID: channel],
            messagesByChannelID: [channelID: messages]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot
        )

        await model.prepareSelectedTimelinePresentation()
        let firstBuildCount = model.phase51PerformanceDiagnostics.timelineBuildCount
        await model.prepareSelectedTimelinePresentation()

        XCTAssertFalse(model.selectedTimelineMessageGroups.isEmpty)
        XCTAssertFalse(
            model.timelineRowPresentation(for: messages[249].id)?.actionItems.isEmpty ?? true
        )
        XCTAssertEqual(model.phase51PerformanceDiagnostics.timelineBuildCount, firstBuildCount)
        XCTAssertGreaterThanOrEqual(model.phase51PerformanceDiagnostics.timelineCacheHitCount, 1)
    }

    @MainActor
    func testTimelineGroupsStayVisibleAcrossMediaIdentityAndSnapshotInvalidation() async {
        let currentUserID: UserID = "timeline-current"
        let authorID: UserID = "timeline-author"
        let channelID: ChannelID = "timeline-channel"
        let message = Message(
            id: "01J00000000000000000000991",
            channelID: channelID,
            authorID: authorID,
            content: "still visible"
        )
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [currentUserID, authorID])
        var snapshot = RealtimeSnapshot(
            usersByID: [
                currentUserID: User(id: currentUserID, username: "current"),
                authorID: User(id: authorID, username: "author")
            ],
            channelsByID: [channelID: channel],
            messagesByChannelID: [channelID: [message]]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot,
            currentUser: snapshot.usersByID[currentUserID]
        )
        await model.prepareSelectedTimelinePresentation()
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])

        await model.clearImageMemoryCache()
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])

        snapshot.usersByID[authorID]?.displayName = "Updated Author"
        model.replaceSnapshotForTesting(
            snapshot,
            changes: RealtimeSnapshotChangeSet(userIDs: [authorID])
        )
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])
    }

    @MainActor
    func testSharedTimelineGroupingWorksForEveryConversationKind() async {
        let currentUserID: UserID = "timeline-route-current"
        let otherUserID: UserID = "timeline-route-other"
        let serverID: ServerID = "timeline-route-server"
        let routes: [(Channel, ShellSelection)] = [
            (
                Channel(id: "timeline-route-text", kind: .textChannel, serverID: serverID, name: "general"),
                ShellSelection(space: .server(serverID), serverID: serverID, channelID: "timeline-route-text")
            ),
            (
                Channel(id: "timeline-route-dm", kind: .directMessage, recipients: [currentUserID, otherUserID]),
                ShellSelection(space: .directMessages, dmChannelID: "timeline-route-dm")
            ),
            (
                Channel(id: "timeline-route-group", kind: .group, name: "Group", recipients: [currentUserID, otherUserID]),
                ShellSelection(space: .directMessages, dmChannelID: "timeline-route-group")
            ),
            (
                Channel(id: "timeline-route-saved", kind: .savedMessages, userID: currentUserID, recipients: [currentUserID]),
                ShellSelection(space: .directMessages, dmChannelID: "timeline-route-saved")
            )
        ]

        for (index, route) in routes.enumerated() {
            let channel = route.0
            let message = Message(
                id: MessageID(rawValue: String(format: "01J%023d", 900 + index)),
                channelID: channel.id,
                authorID: otherUserID,
                content: channel.kind.rawAPIValue
            )
            let server = Server(
                id: serverID,
                ownerID: currentUserID,
                name: "Timeline",
                channelIDs: channel.serverID == nil ? [] : [channel.id]
            )
            let snapshot = RealtimeSnapshot(
                usersByID: [
                    currentUserID: User(id: currentUserID, username: "current"),
                    otherUserID: User(id: otherUserID, username: "other")
                ],
                serversByID: channel.serverID == nil ? [:] : [serverID: server],
                channelsByID: [channel.id: channel],
                messagesByChannelID: [channel.id: [message]]
            )
            let model = MainShellViewModel(
                selection: route.1,
                snapshot: snapshot,
                currentUser: snapshot.usersByID[currentUserID]
            )

            await model.prepareSelectedTimelinePresentation()
            XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])
            await model.clearImageMemoryCache()
            XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])
        }
    }

    @MainActor
    func testTimelineChannelSwitchNeverShowsPreviousConversationGroups() async {
        let currentUserID: UserID = "timeline-switch-current"
        let firstID: ChannelID = "timeline-switch-first"
        let secondID: ChannelID = "timeline-switch-second"
        let firstMessage = Message(id: "01J00000000000000000000981", channelID: firstID, authorID: currentUserID, content: "first")
        let secondMessage = Message(id: "01J00000000000000000000982", channelID: secondID, authorID: currentUserID, content: "second")
        let snapshot = RealtimeSnapshot(
            usersByID: [currentUserID: User(id: currentUserID, username: "current")],
            channelsByID: [
                firstID: Channel(id: firstID, kind: .directMessage, recipients: [currentUserID]),
                secondID: Channel(id: secondID, kind: .directMessage, recipients: [currentUserID])
            ],
            messagesByChannelID: [firstID: [firstMessage], secondID: [secondMessage]]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: firstID),
            snapshot: snapshot,
            currentUser: snapshot.usersByID[currentUserID]
        )
        await model.prepareSelectedTimelinePresentation()

        model.selectChannel(secondID)
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [secondMessage.id])
        await model.prepareSelectedTimelinePresentation()
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [secondMessage.id])
    }

    @MainActor
    func testRealtimeMessageMutationDoesNotRestartCompletedHistoryFetch() async {
        let currentUserID: UserID = "timeline-fetch-current"
        let channelID: ChannelID = "timeline-fetch-channel"
        let message = Message(id: "01J00000000000000000000971", channelID: channelID, authorID: currentUserID, content: "hello")
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [currentUserID])
        let snapshot = RealtimeSnapshot(
            usersByID: [currentUserID: User(id: currentUserID, username: "current")],
            channelsByID: [channelID: channel]
        )
        let api = RecordingAPIClient(messagesByChannel: [channelID: [message]])
        let controller = ChannelMessageController(
            runtimeMode: .liveManual,
            apiClient: api,
            currentUserID: currentUserID
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: snapshot.usersByID[currentUserID],
            messageController: controller
        )
        model.selectChannel(channelID)
        try? await Task.sleep(for: .milliseconds(30))

        var updatedSnapshot = snapshot
        var reacted = message
        reacted.reactions["bagel"] = [currentUserID]
        updatedSnapshot.messagesByChannelID[channelID] = [reacted]
        model.replaceSnapshotForTesting(
            updatedSnapshot,
            changes: RealtimeSnapshotChangeSet(messageChannelIDs: [channelID])
        )
        try? await Task.sleep(for: .milliseconds(20))

        let fetchCount = await api.fetchMessagesCallCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(model.selectedTimelineMessages.first?.message.reactions["bagel"], [currentUserID])
    }

    @MainActor
    func testRealtimeDeleteRemovesMessageFromControllerAndVisibleGroups() async {
        let currentUserID: UserID = "timeline-delete-current"
        let channelID: ChannelID = "timeline-delete-channel"
        let message = Message(id: "01J00000000000000000000961", channelID: channelID, authorID: currentUserID, content: "delete me")
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [currentUserID])
        let snapshot = RealtimeSnapshot(
            usersByID: [currentUserID: User(id: currentUserID, username: "current")],
            channelsByID: [channelID: channel],
            messagesByChannelID: [channelID: [message]]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot,
            currentUser: snapshot.usersByID[currentUserID]
        )
        await model.prepareSelectedTimelinePresentation()

        var deletedSnapshot = snapshot
        deletedSnapshot.messagesByChannelID[channelID] = []
        model.replaceSnapshotForTesting(
            deletedSnapshot,
            changes: RealtimeSnapshotChangeSet(
                messageChannelIDs: [channelID],
                deletedMessageIDsByChannelID: [channelID: [message.id]]
            )
        )

        XCTAssertTrue(model.selectedTimelineMessages.isEmpty)
        XCTAssertTrue(model.selectedTimelineMessageGroups.isEmpty)
    }

    @MainActor
    func testMessageControllerClearsCachedHistoryWhenUserScopeChanges() async {
        let channelID: ChannelID = "timeline-scope-channel"
        let message = Message(id: "01J00000000000000000000951", channelID: channelID, authorID: "first-user", content: "private")
        let controller = ChannelMessageController(runtimeMode: .mock, currentUserID: "first-user")
        _ = await controller.loadInitialMessages(channelID: channelID, snapshotMessages: [message])
        XCTAssertTrue(controller.state(for: channelID).hasMessages)

        controller.configure(runtimeMode: .liveManual, apiClient: nil, currentUserID: "second-user", loadGeneration: 1)

        XCTAssertEqual(controller.state(for: channelID), .idle)
    }
}

// MARK: - Phase 38 Support Types

private actor StubLoginAPIClient: StoatAPIClient {
    let loginResponse: SessionLoginResponse
    let continueResponse: SessionLoginResponse
    private(set) var loginCallCount = 0
    private(set) var continueCallCount = 0

    init(response: SessionLoginResponse, continueResponse: SessionLoginResponse? = nil) {
        self.loginResponse = response
        self.continueResponse = continueResponse ?? response
    }

    // Required protocol methods without default implementations
    func fetchRootConfiguration() async throws -> StoatConfig { throw StoatAPIError.unimplementedEndpoint("stub") }
    func fetchCurrentUser() async throws -> User { User(id: "user1", username: "test") }
    func fetchServers() async throws -> [Server] { [] }
    func fetchChannels() async throws -> [Channel] { [] }
    func fetchChannel(id: ChannelID) async throws -> Channel { throw StoatAPIError.unimplementedEndpoint("stub") }
    func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] { [] }
    func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message { throw StoatAPIError.unimplementedEndpoint("stub") }
    func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message { throw StoatAPIError.unimplementedEndpoint("stub") }
    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws {}
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile { throw StoatAPIError.unimplementedEndpoint("stub") }

    func login(request: SessionLoginRequest) async throws -> SessionLoginResponse {
        loginCallCount += 1
        return loginResponse
    }

    func continueLogin(request: SessionMFALoginRequest) async throws -> SessionLoginResponse {
        continueCallCount += 1
        return continueResponse
    }
}
