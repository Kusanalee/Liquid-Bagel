import XCTest
import StoatAPI
import StoatModels
@testable import StoatPersistence

final class StoatPersistenceTests: XCTestCase {
    func testDefaultPreferencesIncludeProductionProfile() throws {
        let preferences = try AppPreferences.defaults.validated()

        XCTAssertEqual(preferences.selectedEnvironmentProfile.id, "production")
        XCTAssertTrue(preferences.environmentProfiles.contains { $0.isProduction && $0.environment == .production })
        XCTAssertEqual(preferences.liquidGlassTransparency, 1.0)
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

    func testLiquidGlassTransparencyClampsAndRoundTrips() async throws {
        let store = UserDefaultsAppPreferencesStore(suiteName: "LiquidBagelTests.\(UUID().uuidString)")
        var preferences = AppPreferences.defaults
        preferences.liquidGlassTransparency = 0.55

        try await store.savePreferences(preferences)
        let loaded = try await store.loadPreferences()

        XCTAssertEqual(loaded.liquidGlassTransparency, 0.55)
        XCTAssertEqual(AppPreferences(liquidGlassTransparency: -1).liquidGlassTransparency, 0.25)
        XCTAssertEqual(AppPreferences(liquidGlassTransparency: 2).liquidGlassTransparency, 1.0)
    }

    func testResetPreferencesRestoresDefaults() async throws {
        let store = UserDefaultsAppPreferencesStore(suiteName: "LiquidBagelTests.\(UUID().uuidString)")
        var preferences = AppPreferences.defaults
        preferences.memberPanelVisible = false
        try await store.savePreferences(preferences)

        try await store.resetPreferences()
        let loaded = try await store.loadPreferences()

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
        XCTAssertEqual(decoded.liquidGlassTransparency, 1.0)
    }

    func testPhase75VoicePreferencesDefaults() throws {
        let preferences = AppPreferences.defaults.voicePreferences

        XCTAssertNil(preferences.inputDeviceID)
        XCTAssertNil(preferences.outputDeviceID)
        XCTAssertNil(preferences.cameraDeviceID)
        XCTAssertTrue(preferences.echoCancellation)
        XCTAssertTrue(preferences.noiseSuppression)
        XCTAssertFalse(preferences.pushToTalkEnabled)
        XCTAssertNil(preferences.pushToTalkKeyCode)
        XCTAssertEqual(preferences.inputSensitivity, 0.15, accuracy: 0.0001)
    }

    func testPhase75VoicePreferencesValidatedClampsSensitivity() throws {
        let tooHigh = VoicePreferences(inputSensitivity: 4.2).validated()
        let tooLow = VoicePreferences(inputSensitivity: -1.5).validated()

        XCTAssertEqual(tooHigh.inputSensitivity, 1.0, accuracy: 0.0001)
        XCTAssertEqual(tooLow.inputSensitivity, 0.0, accuracy: 0.0001)
    }

    func testPhase75VoicePreferencesDecodeOlderPayloadMissingVoiceKey() throws {
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
          "showDeveloperRuntimeControls": true,
          "memberPanelVisible": true,
          "messageDensity": "comfortable",
          "reduceGlassIntensity": false
        }
        """

        let decoded = try JSONDecoder.stoat.decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.voicePreferences, .defaults)
    }

    func testPhase75VoicePreferencesRoundTripThroughUserDefaultsStore() async throws {
        let store = UserDefaultsAppPreferencesStore(suiteName: "LiquidBagelTests.\(UUID().uuidString)")
        var preferences = AppPreferences.defaults
        preferences.voicePreferences = VoicePreferences(
            inputDeviceID: "mic-1",
            outputDeviceID: "speaker-1",
            cameraDeviceID: "camera-1",
            echoCancellation: false,
            noiseSuppression: false,
            pushToTalkEnabled: true,
            pushToTalkKeyCode: 49,
            inputSensitivity: 0.4
        )

        try await store.savePreferences(preferences)
        let loaded = try await store.loadPreferences()

        XCTAssertEqual(loaded.voicePreferences.inputDeviceID, "mic-1")
        XCTAssertEqual(loaded.voicePreferences.outputDeviceID, "speaker-1")
        XCTAssertEqual(loaded.voicePreferences.cameraDeviceID, "camera-1")
        XCTAssertFalse(loaded.voicePreferences.echoCancellation)
        XCTAssertFalse(loaded.voicePreferences.noiseSuppression)
        XCTAssertTrue(loaded.voicePreferences.pushToTalkEnabled)
        XCTAssertEqual(loaded.voicePreferences.pushToTalkKeyCode, 49)
        XCTAssertEqual(loaded.voicePreferences.inputSensitivity, 0.4, accuracy: 0.0001)
    }

    func testLegacyReducedGlassPreferenceMigratesToLowTransparency() throws {
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
          "reduceGlassIntensity": true
        }
        """

        let decoded = try JSONDecoder.stoat.decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.reduceGlassIntensity)
        XCTAssertEqual(decoded.liquidGlassTransparency, 0.35)
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
