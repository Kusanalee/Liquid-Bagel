# Phase 74 - Release Polish

Phase 74 is the 1.1 pass: it removes the parts of the app that read as an engineering build rather than a product, and adds the two features 1.0 explicitly deferred — offline access and automatic settings sync — without touching voice, video, screen share, or background push, all of which stay out of scope.

## Continuous timeline pagination

The "Load Older Messages" button is gone. Older history loads automatically as the user scrolls toward the start of a channel, roughly 1.5 viewports ahead of the top via `.onScrollGeometryChange`, with a row-index backstop in `flushTimelineVisibility` for when the geometry trigger cannot re-arm after an imprecise restoration.

`ChannelMessageState.loadingOlder` is gone — it was a derived, unstored case that made the whole timeline enter a separate top-level state mid-scroll. Pagination is now a detail of a fixed 32pt header slot (`OlderHistoryHeaderState`), not a mode switch. `.olderLoadFailed` no longer sets `errorMessage`, the initial-load error channel; a background prefetch failing must not repaint the messages someone is reading as an error.

The fetch decision is gated in one place (`requestOlderMessagesIfNeeded`): not re-entrant, never during initial load or unread recovery, never past `hasMoreBefore`, a 5s cooldown after a failure, and a 3-page budget for consecutive automatic pages that only refills when the user scrolls away — the guard against a channel shorter than the viewport paging itself to the beginning.

`.defaultScrollAnchor(_:for: .sizeChanges)` was considered and rejected: one anchor cannot serve both edges of a chat timeline (holding position on prepend vs. staying pinned to new messages on append).

## Offline mode

**Persistence** (`Packages/StoatPersistence/Sources/StoatPersistence/SessionCache.swift`). A connected session is sharded by volatility, not by entity — core/graph/users/unreads/read-state/members — so message and typing traffic, the dominant event stream, dirties zero session shards. Every shard is a versioned envelope; a version this build does not recognize is deleted, not migrated, because the cache is disposable by definition. A scope-fingerprint mismatch purges the entire scope rather than one file, since it means a directory held another identity's data. Payloads are AES-GCM encrypted with a key held in the Keychain alongside the credential — not `NSFileProtectionComplete`, which is a no-op on macOS.

**Startup** (`AppStartupState.readyOffline`, `LiquidBagelRootView`). The shell paints from disk before the network is touched, on every launch, not only offline ones. `.ready` and `.readyOffline` are not two arms of one switch — that would build a `_ConditionalContent` and tear down `MainShellView` on every online/offline transition. `showsMainShell` keeps it one branch. A rejected session (`.invalidSession`, a non-network validation failure, a Keychain failure) never shows cached content.

Two traps, each with a regression test: restoring the cache leaves `hydrationStatus.readyReceived` false and never bumps `liveConnectionGeneration`, which is what keeps the notification pipeline shut — restoring is not new activity. And `restoreCachedSession` sets `currentUser` from disk, which is what makes the later promotion to live a load-scope change rather than an identity-scope one; without it, `ChannelMessageController.configure` would treat the first successful connect as a different user and wipe every loaded history.

**Chrome** (`ConnectionChrome`, `writeBlockReason`). Produces `nil` when healthy — the sidebar no longer carries a permanent "Connected" line. Every write action gets one reason from one place, so the composer and a context menu cannot drift into describing the same offline state differently.

Read-only by design: writes are disabled with a reason while offline, not queued.

## Automatic settings sync

Four triggers replace the two manual buttons: fetch on connect, fetch on the gateway's `UserSettingsUpdate` event (previously received and ignored for preference purposes), a debounced push 3s after a local edit, and a cooldown-gated fetch on foreground. Change detection compares only the four-field `SyncedClientPreferences`, not all of `AppPreferences` — comparing the whole struct would push on every channel selection. The first sync after attaching a coordinator establishes the baseline rather than treating loaded preferences as a change, or every launch would push once unconditionally.

## Developer options

`showDeveloperRuntimeControls` now defaults to `false` (was `true`), gating the Developer tab, the timeline validation harness, notification diagnostics, the connection counter grid, raw user/channel/message ID actions, and the calibration commands that were sitting in the Quick Switcher. The toggle moved to Settings > Connection > Advanced as "Enable Developer Options."

## Errors and status

`UserFacingError` maps any error to one sentence with no status code, decoder path, diagnostic category, or URL — the full detail stays in redacted diagnostics behind Developer Options. Errors already written for a person (`AttachmentValidationError`) keep their own words via a `UserPresentableError` marker rather than being flattened into a generic apology.

`TransientAppNoticePolicy` gains `.success`/`.info` severities; it previously only recognized failure substrings, so every confirmation in the app ("Attachment saved", "Message pinned") matched nothing and was silently dropped. `composerError` and `messageActionStatus` had no render site at all before this phase — attachment failures were set and thrown away.

The member panel is silent when healthy, a bare spinner while refreshing, and one sentence with a Retry button on failure — it previously narrated "Members refreshed from Stoat" / "Showing Ready members" and, on failure, interpolated a raw `StoatAPIError` description plus an internal diagnostic category.

## Sign-in screen

Two fields instead of three (device name moved to Advanced), the raw API host hidden on production, a "Create an account" link, and a picker when an MFA challenge allows more than one method. `submitMFA()` previously always used `allowedMethods.first` with no way to change it, so a recovery code on a TOTP-first account was submitted as the wrong kind and rejected regardless of correctness.

## What stayed out

Voice, video, screen share: unchanged, deferred. Background/APNs push: cut by decision — the app is ad-hoc signed with no provisioning profile for the Push capability, and Stoat's push mechanism is web push/VAPID, not APNs, with no verified subscribe route. iCloud settings sync: blocked on the same signing gap (`ubiquity-kvstore-identifier` needs real provisioning); automatic Stoat-backed sync covers the same need today. Offline pagination through cached history: explicitly not built — `hasMoreBefore: false` on a cached hydration means the existing pagination guard blocks it with no extra code, and the disk cost of deeper history didn't justify re-scrolling messages already read.

## Automated proof

471 StoatFeatures tests (up from 410), 36 StoatPersistence tests (up from 15), the doubles gate, and the signed macOS build all pass.
