import XCTest
import StoatAPI
import StoatModels
@testable import StoatPersistence

final class StoatPersistenceTests: XCTestCase {
    func testEmptyRepositoryReturnsNoCurrentUser() async throws {
        let repository = EmptyStoatCacheRepository()
        let user = try await repository.cachedCurrentUser()

        XCTAssertNil(user)
    }

    func testDefaultPreferencesIncludeProductionProfile() throws {
        let preferences = try AppPreferences.defaults.validated()

        XCTAssertEqual(preferences.preferredLaunchMode, .mock)
        XCTAssertEqual(preferences.selectedEnvironmentProfile.id, "production")
        XCTAssertTrue(preferences.environmentProfiles.contains { $0.isProduction && $0.environment == .production })
    }

    func testPreferencesRoundTripThroughUserDefaultsStore() async throws {
        let store = UserDefaultsAppPreferencesStore(suiteName: "LiquidBagelTests.\(UUID().uuidString)")
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let preferences = try AppPreferences.defaults
            .upserting(profile: custom)
            .withSelectedEnvironmentID(custom.id)

        try await store.savePreferences(preferences)
        let loaded = try await store.loadPreferences()

        XCTAssertEqual(loaded.lastSelectedEnvironmentID, custom.id)
        XCTAssertEqual(loaded.environmentProfiles.first { $0.id == custom.id }?.name, "Local")
    }

    func testResetPreferencesRestoresDefaults() async throws {
        let store = UserDefaultsAppPreferencesStore(suiteName: "LiquidBagelTests.\(UUID().uuidString)")
        var preferences = AppPreferences.defaults
        preferences.memberPanelVisible = false
        try await store.savePreferences(preferences)

        try await store.resetPreferences()
        let loaded = try await store.loadPreferences()

        XCTAssertEqual(loaded.preferredLaunchMode, .mock)
        XCTAssertTrue(loaded.memberPanelVisible)
        XCTAssertEqual(loaded.environmentProfiles.map(\.id), ["production"])
    }

    func testSerializedPreferencesDoNotContainTokenLikeFields() async throws {
        let store = UserDefaultsAppPreferencesStore(suiteName: "LiquidBagelTests.\(UUID().uuidString)")
        try await store.savePreferences(.defaults)

        let encoded = await store.encodedPreferencesData()
        let data = try XCTUnwrap(encoded)
        let string = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(string.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(string.localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(string.localizedCaseInsensitiveContains("credential"))
    }

    func testLastSelectedEnvironmentPersists() throws {
        let custom = try EnvironmentProfile.custom(
            name: "Dev",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:3000")!, eventsURL: URL(string: "ws://localhost:3001")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: custom).withSelectedEnvironmentID(custom.id)

        XCTAssertEqual(preferences.selectedEnvironmentProfile.id, custom.id)
        XCTAssertEqual(preferences.selectedEnvironment.apiBaseURL.host(), "localhost")
    }

    func testCustomProfileAddUpdateDeleteRules() throws {
        let first = try EnvironmentProfile.custom(
            name: "Dev",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:3000")!, eventsURL: URL(string: "ws://localhost:3001")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: first)
        let renamed = try first.updating(name: "Dev Renamed", environment: first.environment)

        XCTAssertEqual(renamed.id, first.id)
        XCTAssertEqual(renamed.name, "Dev Renamed")

        let changed = try first.updating(
            name: "Other",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:4000")!, eventsURL: URL(string: "ws://localhost:4001")!)
        )
        XCTAssertNotEqual(changed.id, first.id)

        let deleted = try preferences.deletingProfile(id: first.id)
        XCTAssertNil(deleted.environmentProfiles.first { $0.id == first.id })
        XCTAssertTrue(deleted.environmentProfiles.contains { $0.isProduction })
    }

    func testProductionProfileCannotBeDeleted() {
        XCTAssertThrowsError(try AppPreferences.defaults.deletingProfile(id: "production")) { error in
            XCTAssertEqual(error as? PersistenceError, .productionProfileCannotBeDeleted)
        }
    }

    func testUnsafeRemoteURLValidationFailsAndLocalhostPasses() throws {
        XCTAssertThrowsError(try StoatAPIEnvironment.custom(
            apiBaseURL: URL(string: "http://example.com")!,
            eventsURL: URL(string: "wss://events.example.com")!
        ))

        XCTAssertNoThrow(try StoatAPIEnvironment.custom(
            apiBaseURL: URL(string: "http://localhost:14702")!,
            eventsURL: URL(string: "ws://localhost:14703")!
        ))
    }

    func testTimelineTuningPresetsUseValidatedSafeValues() {
        for preset in TimelineTuningPreset.allCases {
            XCTAssertEqual(preset.configuration, preset.configuration.validated())
        }
        XCTAssertEqual(TimelineTuningPreset.conservative.configuration, .defaults)
        XCTAssertEqual(TimelineTuningPreset.debugStrict.configuration.nearNewestMessageThreshold, 0)
    }

    func testPhase18NotificationPreferencesDefaultConservative() throws {
        let preferences = try AppPreferences.defaults.validated().notificationPreferences

        XCTAssertFalse(preferences.nativeNotificationsEnabled)
        XCTAssertTrue(preferences.inAppBannersEnabled)
        XCTAssertEqual(preferences.contentVisibility, .privateMode)
        XCTAssertTrue(preferences.suppressActiveChannel)
        XCTAssertEqual(preferences.deliveryScope, .mentionsAndDirectMessages)
        XCTAssertEqual(preferences.dockBadge, .unreadChannelsAndMentions)
    }

    func testPhase18NotificationPreferencesDecodeOlderPayload() throws {
        let json = """
        {
          "environmentProfiles": [
            {
              "id": "production",
              "name": "Stoat Production",
              "environment": {
                "apiBaseURL": "https://api.stoat.chat",
                "eventsURL": "wss://events.stoat.chat"
              },
              "isProduction": true,
              "createdAt": "2026-01-01T00:00:00.000Z",
              "updatedAt": "2026-01-01T00:00:00.000Z"
            }
          ],
          "preferredLaunchMode": "mock",
          "showDeveloperRuntimeControls": true,
          "memberPanelVisible": true,
          "messageDensity": "comfortable",
          "reduceGlassIntensity": false
        }
        """

        let decoded = try JSONDecoder.stoat.decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.notificationPreferences, .defaults)
    }

    func testPhase18ChannelNotificationOverridesValidateAndRoundTrip() async throws {
        let store = UserDefaultsAppPreferencesStore(suiteName: "LiquidBagelTests.\(UUID().uuidString)")
        var preferences = AppPreferences.defaults
        preferences.notificationPreferences.channelPreferences["muted"] = ChannelNotificationPreference(isMuted: true)
        preferences.notificationPreferences.channelPreferences["empty"] = ChannelNotificationPreference()

        try await store.savePreferences(preferences)
        let loaded = try await store.loadPreferences()

        XCTAssertEqual(loaded.notificationPreferences.channelPreferences["muted"]?.isMuted, true)
        XCTAssertNil(loaded.notificationPreferences.channelPreferences["empty"])
    }
}
