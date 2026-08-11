# Phase 73 - Live-Only Runtime

Phase 73 removes the mock infrastructure from the shipping product. Every test double is out of `Sources/`, production no longer constructs or defaults into mock behavior, and a build-time gate keeps the pattern from returning.

## What Was Actually There

The doubles were not test-target helpers. All 15 lived in `Sources/`, were `public`, and were wired in as **default parameter values on production initializers**:

- `MockStoatAPIClient` (946 lines) shipped inside StoatAPI.
- `MainShellViewModel.init` constructed `MockAttachmentUploadHandler`, `MockRemoteAttachmentLoader`, `MockImageResourceLoader`, `MockMessageActionHandler`, and `MockStoatAPIClient` on every construction that did not override them.
- `runtimeMode` and `sessionState` both defaulted to `.mock`, so anything built without an explicit mode started in mock mode.
- `ScriptedWebSocketTransport` shipped in StoatRealtime with zero production references.

## Changes

- Doubles moved to the test targets, renamed `Mock*` -> `Stub*` and `MockShellData` -> `TestShellData`. Test-target files get `@testable` access and cannot ship, which is a stronger guarantee than a separate library target would give: a support *target* only sees `public` API, and these doubles conform to internal protocols.
- Production defaults become real null objects - `UnavailableAttachmentUploadHandler`, `UnavailableRemoteAttachmentLoader`, `UnavailableImageResourceLoader` - following the existing `UnavailableMessageActionHandler` / `NoopChannelAckSender` convention. They fail closed with safe copy rather than reporting success.
- `runtimeMode` / `sessionState` defaults are now `.liveManual` / `.signedOut`.
- The message-edit path no longer fabricates an author from a synthetic ULID; it refuses the edit and asks the user to reconnect.
- The coordinator's mock session API (`startMockSession`, `resetToMock`, `mockSnapshot`, `mockCurrentUserID`) is gone. It had zero production call sites.
- All 44 `#Preview` blocks and their two helpers are deleted.
- `Scripts/check.sh` fails if any `Packages/*/Sources` or `App` file declares a `Mock`/`Stub`/`Fake` type. Verified in both directions.

## Two Corrections to the Plan

**The `MockShellData.currentUserID` fallback was not a shipped user-visible bug.** The plan led with it as a proven defect. Tests written specifically to catch it red **passed immediately**: `MainShellViewModel.init` looked the synthetic ULID up in the *snapshot*, and a real snapshot never contains `01HX0000000000000000000001`, so the lookup simply missed and `currentUser` stayed nil. `currentUserID`'s other fallback was gated on `.mock`, which production never entered.

What it actually was: a **test convenience that 195 call sites silently depended on** for their current user. Those now pass it explicitly. The regression guard is kept.

The genuinely live-reachable problem was different and smaller: at `StoatFeatures.swift:6805` the mock upload handler was the fallback whenever no live API client existed, and `apiClient` is `Optional`, so in `.liveManual` *before connect* an attachment could appear to upload and go nowhere. That one is fixed.

**`AppRuntimeMode` deletion is larger than the plan estimated and is not done.** The plan scoped it as 34 branches plus 70 test functions. The real surface also includes `AppSessionState.mock` and `DMRefreshSource.mock` - three separate enums - and 82 explicit `runtimeMode:` test arguments. More importantly, flipping the production defaults to live made **51 tests fail**, because they were asserting mock-mode semantics (can-send gating, preview-data copy, snapshot-backed message loading). Those need genuine per-test rework against live paths, not a mechanical pass.

The intermediate step landed instead: production defaults to live, and every test that wants mock semantics says so explicitly. That converts an invisible default into a visible dependency, which is the precondition for removing the enum in a reviewable diff.

## Remaining

- Collapse the 39 `.mock` branches in `Sources/` and delete `AppRuntimeMode`, `AppSessionState.mock`, and `DMRefreshSource.mock`.
- Rewrite the ~82 tests that assert mock-mode semantics against live paths, or delete the ones that only ever tested mock behavior.
- User-facing strings that disappear with the branches: `"Preview data cannot send messages."` and `"Preview Data"`.

## Automated Proof

410 StoatFeatures tests (up from 408), 59 StoatUI, every other package suite, the new doubles gate, and the signed macOS build all pass.
