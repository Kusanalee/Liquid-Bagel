# Phase 6 Summary

## What Was Implemented

Phase 6 adds safe non-token preference persistence, persistent environment profiles, account/session management view models, a focused Account & Connection settings surface, session listing/rename/revoke actions, and mock-only tests.

The app remains mock-safe. Launch loads preferences and selected environment metadata, checks scoped Keychain credential presence, and does not validate saved credentials or connect REST/WebSocket until the user explicitly acts.

## Preferences Storage Strategy

`StoatPersistence` now owns `AppPreferencesStore`, `AppPreferences`, `EnvironmentProfile`, `PreferredLaunchMode`, and `MessageDensityPreference`.

The default `UserDefaultsAppPreferencesStore` stores one Codable JSON blob for non-token preferences. This includes selected environment ID, environment profiles, safe UI preferences, and last selected server/channel IDs. It does not store raw session tokens or credential payloads.

`PreferredLaunchMode` defaults to `.mock`. The alternate `.rememberLastButDoNotConnect` restores UI environment selection only; it never opens network connections.

## Environment Profile Behavior

The production profile always exists and cannot be deleted. Custom profiles can be added, edited, selected, and deleted.

Custom profile URL validation reuses `StoatAPIEnvironment.validate()`: remote API URLs require HTTPS, remote events URLs require WSS, and localhost HTTP/WS is allowed for development. Editing URLs creates a new stable environment ID unless the URLs are unchanged.

Deleting a profile does not delete its Keychain credential by default. The UI exposes a separate confirmed delete-and-forget path for custom profiles with scoped credentials.

## Keychain And Credential Scoping

Session tokens remain in `KeychainTokenStore` only. Credentials are scoped by environment ID through `CredentialScope`, so production and custom environment credentials do not collide.

The coordinator and settings UI can show whether a credential exists for an environment, but never expose token values.

## Account Summary Behavior

The Account tab shows the currently validated user when available, username/display name, user ID copy control, selected environment, validation status, last validation time, and credential presence.

Actions remain explicit: validate saved session, connect manually, disconnect, forget local session, revoke current session, and reset to mock.

## Session Management Behavior

`SessionManaging` wraps the verified API calls using any `StoatAPIClient`. `AccountSessionViewModel` manages loading, empty, error, rename, revoke-one, revoke-all-other, and current-session logout states.

The sessions list displays friendly name, shortened session ID, derived created time when the ID is a ULID, and a current marker when the local credential includes a matching session ID.

Because the API returns only `_id` and `name`, updated time is not shown and manually imported tokens without session IDs cannot identify the current session with certainty.

## Revoke And Logout Behavior

Individual session revoke uses `DELETE /auth/session/{id}` and requires confirmation. Revoking the current session warns that it may disconnect this client.

Log out other sessions uses `DELETE /auth/session/all?revoke_self=false`. Current-session logout uses `POST /auth/session/logout`, then clears the local scoped Keychain credential after the server accepts the request.

## Runtime Startup Behavior

Startup calls `startMockSession()`, loads preferences, restores selected environment metadata, checks whether a scoped credential exists, and remains in mock mode. A saved credential can move session state to ready-to-connect, but no REST validation or WebSocket connection occurs automatically.

Environment switching disconnects any live realtime session, clears live state, updates selected environment preferences, checks credential availability for the new scope, and never reuses a credential from another environment.

## Security And Redaction Rules

- Raw tokens are not stored in preferences, docs, logs, diagnostics, or UI.
- Token entry remains a `SecureField`.
- Session list UI never shows token values.
- Full session IDs are avoided in broad diagnostics; the UI uses shortened IDs.
- Destructive local forget, profile credential deletion, current-session revoke, and session revoke actions require confirmation.
- Remote non-HTTPS/non-WSS custom environments remain rejected except localhost development URLs.

## Tests Added

New mock-only coverage includes:

- preference defaults, round-trip, reset, token-like serialization checks, selected environment persistence, profile update/delete behavior, and unsafe/local URL validation
- session endpoint request construction for list, rename, revoke one, revoke all, and logout current session
- coordinator preference startup, saved credential ready-without-connect behavior, scoped credential switching, selected environment persistence, and preference save failures
- account/session view-model loading, empty/error states, rename validation, revoke-one, and revoke-all-other behavior
- connection settings view-model save/validation behavior and safe UI helper formatting/redaction

## Deferred

Still deferred:

- uploads/media UI
- notifications
- persistent message cache
- friends/DM/discover APIs
- voice
- server/channel settings
- full account profile editing
- live tests requiring real credentials
- background validation on launch

## Known Risks And API Uncertainties

- `SessionInfo` has no explicit `current`, created, or updated fields. Current-session marking depends on the locally saved session ID.
- Manually imported tokens may not include a session ID, so current-session marking may be unavailable until login-created credentials are used.
- Self-hosted/custom environments are assumed to support the same auth/session API shape.

## How To Run

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatDesignSystem
swift test --package-path Packages/StoatPersistence
Scripts/check.sh
```

Run the app from the `LiquidBagel` Xcode scheme. It opens in mock mode. Use the runtime chip or Settings command to open Account & Connection settings.

## Recommended Phase 7 Next Step

Phase 7 should focus on making the connected manual workflow more useful after explicit connection: safer channel/server navigation from realtime Ready state, clearer reconnect controls, and selected-channel restoration without adding background auto-connect behavior.
