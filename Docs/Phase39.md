# Phase 39: Startup/Auth Stabilization and Live-Parity Dogfood Readiness

## Summary

Phase 39 fixes the Phase 38 first-run startup loop by moving startup idempotence into `AppSessionCoordinator` and moving successful auth completion into one coordinator-owned save-and-connect path.

The root cause was a split contract:

- `LiquidBagelRootView.task` can run more than once as the root content changes.
- `startLiveFirstSession()` always reset live-first state, so a repeated task could interrupt first-run login or reattempt a failed saved credential.
- Email/password and token import validated into `pendingValidatedSession`, then relied on the view to call `finishValidatedSessionAndConnect()`. MFA continuation and Settings paths could stop after validation instead of saving and connecting.
- `savedCredentialUnvalidated` and `readyToConnect` mapped to startup progress even when no validation or connection task was active.

## Startup Contract

- Normal launch loads preferences and attempts saved-credential auto-connect once for the selected environment.
- Repeated startup tasks for the same launch/environment are skipped and recorded in redacted diagnostics.
- Explicit retry still calls reconnect and is not blocked by startup idempotence.
- No credential shows first-run login.
- Saved credential failures, network failures, environment switches, and disconnected saved sessions land in a recoverable retry/sign-in/forget state instead of a spinner.
- Mock preview/dev paths still do not auto-connect.

## Auth Contract

Successful email/password login, MFA continuation, and token import now all:

1. Validate the returned/imported credential.
2. Save the validated credential to the scoped Keychain store for the selected environment.
3. Start live realtime connection through the shared coordinator.

Failed auth still leaves Keychain untouched. Token import in Settings is now a single `Import and Connect` action rather than a validate-then-save pair.

## Shared Model

`RootScene` continues to instantiate one `LiquidBagelAppModel` and pass its shell view model into Settings. Phase 39 adds regression coverage that the shell attaches the same `AppSessionCoordinator` instance used by the app model.

## Diagnostics

`StartupAuthDiagnostics` records startup invocation count, skipped startup count, auto-connect count, environment kind, categorical startup/auth action/result, and error category.

The redacted summary removes token/password/MFA-ticket/MFA-response shapes, raw JSON payload-like bodies, local/keychain paths, URLs, and long session-like IDs. Developer Settings now copies login and startup/auth diagnostics together.

## Tests

Added Phase 39 coverage:

- auto-connect idempotence per launch/environment
- email/password login saves and connects
- MFA continuation saves and connects
- token import saves to the selected environment and connects
- saved credential network failure does not loop
- explicit retry can recover after startup failure
- forget session returns to first-run state
- environment switch with a scoped credential lands in a recoverable retry state
- shared `LiquidBagelAppModel` / shell coordinator behavior
- startup/auth diagnostics redaction

Updated older token-import coverage to match the Phase 39 contract: successful import now validates, saves, and connects.

## Verification

Focused verification run:

```bash
swift test --package-path Packages/StoatFeatures
```

Result: passed, 232 tests.

Full repo verification remains `Scripts/check.sh`.

Final verification run:

```bash
Scripts/check.sh
```

Result: passed; all package tests completed and the macOS app build ended with `** BUILD SUCCEEDED **`.

## Manual QA Still Required

Live dogfood still needs real credentials:

1. Fresh install with no credential shows first-run login.
2. Email/password login reaches realtime Ready.
3. MFA challenge and continuation reach realtime Ready.
4. Token import reaches realtime Ready.
5. Quit/relaunch with saved credential auto-connects once.
6. Saved credential network failure shows retry/sign-in/forget without looping.
7. Environment switch does not borrow credentials across scopes.
8. Developer diagnostics copy contains no tokens, passwords, MFA responses, raw server bodies, full session IDs, or keychain paths.

## Out of Scope

Phase 39 does not add voice, video, screen share, APNs, persistent message/media cache, server deletion, hidden fetches, background sync, or unrelated parity features.
