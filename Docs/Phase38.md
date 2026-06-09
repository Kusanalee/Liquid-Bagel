# Phase 38: First-Run Login Window and Onboarding

## Summary

Phase 38 gates root content on auth state, adds a native first-run login card, and unifies all app-wide state under one shared model. Before this phase, `MainShellView` rendered even with no saved credential and `RootScene` created an independent `AppSessionCoordinator` for the Settings scene that could race with the main window coordinator.

---

## Startup State Machine

| State | Trigger | Root view shown |
|---|---|---|
| `loadingPreferences` | App launch, preferences not yet loaded | `StartupProgressView` |
| `validatingCredential` | Saved credential found, validating | `StartupProgressView` |
| `connectingLive` | Credential valid, connecting to realtime | `StartupProgressView` |
| `noCredential` | No saved credential in scoped Keychain | `FirstRunLoginView` |
| `savedCredentialFailed(msg)` | Saved credential rejected (401/network) | `SavedCredentialFailureView` |
| `startupFailed(.keychainUnavailable)` | Keychain access denied by OS | `StartupFailureView` |
| `startupFailed(.unknown)` | Unrecoverable launch error | `StartupFailureView` |
| `ready` | Realtime Ready received | `MainShellView` |

`AppStartupState` is a derived property of `LiquidBagelAppModel`, computed from `AppSessionCoordinator.sessionState` and `hasSavedCredential`. It is never stored.

---

## New Public Types

### `LiquidBagelAppModel`
Owns one `AppSessionCoordinator`, one `MainShellViewModel`, and one `FirstRunLoginViewModel`. Instantiated once in `RootScene` via `@State`. Shared between the main `WindowGroup` and the `Settings` scene.

### `AppStartupState` / `AppStartupFailure`
Enums derived from coordinator state. Drive the root content switch.

### `LoginFlowState`
`.idle` → `.submitting` → `.mfaRequired` or `.succeeded`. Set on coordinator during login, MFA, and token flows.

### `LoginErrorDisplay`
Safe error categories: `.invalidCredentials`, `.accountDisabled`, `.mfaFailed`, `.rateLimited`, `.networkError`, `.serverError`, `.keychainError`, `.environmentError`, `.unknown(String)`. Never contains tokens, passwords, raw bodies, or paths.

### `LoginDiagnostics`
Tracks attempt count, last attempt timestamp, and last error category. `redactedSummary` uses category names only — no credentials leak.

### `FirstRunLoginViewModel`
Owns form fields (`email`, `password`, `sessionName`, `mfaResponse`, `manualToken`, `tokenLabel`, `isAdvancedExpanded`, `loginError`). Delegates all coordinator calls. Exposes `flowState`, `mfaChallenge`, `isLoading`, `canSubmitLogin`, `canSubmitMFA`, `canSubmitToken`.

### `FirstRunLoginView`
Centered Liquid Glass onboarding card. App icon, environment row, credentials form, MFA section (hidden until challenge present), Advanced disclosure group (token import, environment picker), safe error label, Sign In button with loading state. `@FocusState` tab order; Return on password field submits.

---

## Login Flow

```
User submits email+password
  └─ coordinator.login(email:password:friendlyName:)
       ├─ success → pendingValidatedSession set
       │    └─ finishValidatedSessionAndConnect()
       │         ├─ savePendingValidatedSession() → scoped Keychain
       │         └─ connectLive(source: .userInitiated) → Ready → shell
       ├─ mfaRequired → loginFlowState = .mfaRequired → MFA section shown
       │    └─ coordinator.continueLoginMFA(response:friendlyName:)
       │         └─ same success path
       └─ error → loginErrorCategory(for:) → LoginErrorDisplay → UI label
```

---

## Token Import Flow (Advanced)

```
User pastes token + optional label, taps Import Token
  └─ coordinator.validateImportedToken(_:localLabel:)
       ├─ fetchCurrentUser() succeeds → pendingValidatedSession set
       │    └─ finishValidatedSessionAndConnect() → save → connect → Ready → shell
       └─ fetchCurrentUser() fails → error shown, nothing saved to Keychain
```

---

## Environment Profiles

- Default: Production (immutable).
- Custom profiles selectable under Advanced in `FirstRunLoginView`.
- Scoped Keychain: each environment profile stores its credential separately. No token movement across environments.
- `coordinator.selectEnvironmentProfile(id:)` resets session state and clears the current scoped credential.

---

## Settings / Command Routing

- `Cmd-,` opens `AccountConnectionSettingsView` using `appModel.shell` (backed by the shared coordinator).
- `CredentialSetupView` remains in Developer Verification settings; not used as first-run UI.
- `CurrentSettingsSceneView` removed — it created a duplicate coordinator.

---

## Developer Diagnostics

`LoginDiagnosticsSection` in `DeveloperVerificationTab` (Phase 6 settings, Developer tab):
- Visible only when `preferences.showDeveloperRuntimeControls == true`.
- Shows `coordinator.loginDiagnostics.redactedSummary` in monospaced text.
- "Copy Redacted Diagnostics" button copies the summary to the pasteboard.
- `redactedSummary` includes: attempt count, last attempt timestamp (or "never"), last error category name. No tokens, passwords, or raw server responses.

---

## Security Notes

- Keychain write happens only after a validated session (`pendingValidatedSession` non-nil). Failed logins never touch Keychain.
- `LoginDiagnostics.redactedSummary` is safe to copy and share. It uses category names, not raw error text.
- MFA response strings (`mfaResponse`) are never logged, never stored in diagnostics, and never appear in error messages.
- `loginErrorCategory(for:)` maps `SessionValidationError` to `LoginErrorDisplay` without retaining error detail strings.
- Token strings in `manualToken` field are cleared after `submitToken()` returns (success or failure).

---

## Files Changed

| File | Change |
|---|---|
| `App/RootScene.swift` | Rewritten: one shared `LiquidBagelAppModel`; removed `CurrentSettingsSceneView` |
| `Packages/StoatFeatures/Sources/StoatFeatures/StoatFeatures.swift` | Added `AppStartupState`, `AppStartupFailure`, `LiquidBagelAppModel`, `FirstRunLoginViewModel`, `FirstRunLoginView`, `SavedCredentialFailureView`, `StartupFailureView`, `StartupProgressView`, updated `LiquidBagelRootView` |
| `Packages/StoatFeatures/Sources/StoatFeatures/Phase4Runtime.swift` | Added `LoginFlowState`, `LoginErrorDisplay`, `LoginDiagnostics`; new coordinator properties `loginFlowState`, `loginDiagnostics`, `autoConnectAttemptCount`; `finishValidatedSessionAndConnect()`; `loginErrorCategory()` helper; updated `login()`, `continueLoginMFA()`, `validateImportedToken()`, `disconnectLive()`, `forgetLocalSession()` |
| `Packages/StoatFeatures/Sources/StoatFeatures/Phase6SettingsView.swift` | Added `LoginDiagnosticsSection` to `DeveloperVerificationTab` |
| `Packages/StoatFeatures/Tests/StoatFeaturesTests/StoatFeaturesTests.swift` | Added 27 Phase 38 tests across 4 test classes |

---

## Tests

### `Phase38StartupStateTests` (7 tests)
- `testStartupStateNoCredential` — no-credential coordinator → `.noCredential`
- `testStartupStateMockReady` — mock coordinator → `.ready`
- `testStartupStateConnectingLive` — connecting coordinator → `.connectingLive`
- `testStartupStateReadyAfterConnected` — connected coordinator → `.ready`
- `testStartupStateSavedCredentialFailed` — validationFailed coordinator + hasSavedCredential → `.savedCredentialFailed`
- `testForgetReturnsToNoCredential` — after `forgetLocalSession()` → `.noCredential`
- `testNoShellBeforeReady` — non-ready coordinator → startup state not `.ready`

### `Phase38LoginDiagnosticsTests` (7 tests)
- `testLoginFlowStateStartsIdle`
- `testLoginDiagnosticsStartEmpty`
- `testAutoConnectCountStartsZero`
- `testAutoConnectIncrements`
- `testRedactedSummaryHasAttemptCount`
- `testDiagnosticsDoNotLeakCredentials`
- `testForgetResetsDiagnostics`

### `Phase38FirstRunLoginViewModelTests` (6 tests)
- `testDefaultEmptyFields`
- `testCanSubmitLoginRequiresFields`
- `testCanSubmitTokenRequiresToken`
- `testClearFormResetsFields`
- `testMFAChallengeForwarded`
- `testIsLoadingWhenSubmitting`

### `Phase38AuthFlowTests` (7 tests)
- `testInvalidCredentialsShowsError`
- `testTokenImportSuccess`
- `testTokenImportFailureDoesNotSave`
- `testFinishValidatedSavesToKeychain`
- `testFinishValidatedNoopWithoutPending`
- `testNetworkErrorCategorized`
- `testRateLimitCategorized`

**Total: 224 tests, 0 failures** (197 pre-Phase-38 + 27 new).

---

## Deferrals

- Live email/password login: credential setup tested via mock API; live QA against production blocked until real credentials available.
- MFA: mock flow tested; full live MFA challenge/response needs real MFA-enabled account.
- Environment switching live QA: custom profiles testable in developer settings; live multi-environment credential scoping needs live QA.
- APNs, background sync, persistent message/media cache, voice/video remain out of scope.

---

## Run Commands

```bash
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatDesignSystem
swift test --package-path Packages/StoatPersistence
Scripts/check.sh
```

---

## Manual QA Checklist

1. Fresh install (no Keychain entry) → `FirstRunLoginView` shown, not shell chrome.
2. Enter credentials → sign in → shell appears after Ready.
3. Quit and relaunch → auto-connect; shell appears without login card.
4. `Cmd-,` → Settings opens connected to same coordinator as main window.
5. Forget session → returns to `FirstRunLoginView`.
6. Token import under Advanced → validates, saves, connects.
7. Invalid password → safe error label shown; no token/password text in error.
8. MFA flow → challenge section appears; correct code accepted; wrong code shows `.mfaFailed`.
9. Enable Developer Mode in settings → Login Diagnostics section visible in Developer Verification tab; Copy Redacted Diagnostics copies safe summary.
10. Disable Developer Mode → diagnostics section hidden.
11. Dark mode, high contrast, Reduce Transparency → login card renders correctly with no layout breaks.
12. `savedCredentialFailed` → retry/re-login/forget actions all work as expected.

---

## Recommended Phase 39

Live dogfood pass: test fresh install, MFA, environment switching, session revoke, and re-login against a real Stoat instance. Mark parity matrix items from `partial` to `done` only after this pass.
