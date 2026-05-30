# Phase 12 Summary

## What Was Implemented

Phase 12 adds real-session timeline validation and tuning while preserving Liquid Bagel’s mock-safe launch behavior. The app still does not auto-connect to Stoat, does not validate saved credentials on launch, and does not add persistent message storage or background sync.

Implemented:

- Developer timeline validation harness in Account & Connection settings
- persisted timeline tuning configuration for developer thresholds
- visible-range validation warnings and redacted diagnostics copy
- source-verified single-message, around-message, selected-channel search, and pinned-search route support
- live reference resolver backed by verified single-message fetch
- explicit around-message fetch support through verified `nearby`
- local “Find in loaded messages”
- selected-channel Live Manual search with non-persistent results
- improved unread/reference/search/diagnostics copy
- mock-only tests for tuning, validation, route shape, find, and redaction

## Live Connected Validation Harness

The Developer tab now shows environment, current user, runtime connection state, Ready state, selected channel, loaded and visible ranges, at-newest status, unread state, pagination boundaries, reference/retry counts, ack result, route verification result, tuning values, and validation warnings.

Harness actions are explicit: validate timeline state, refresh selected channel, load older, load to unread, jump newest, jump first unread, verify routes, reset diagnostics, copy redacted diagnostics, find loaded messages, and selected-channel search.

## Timeline Tuning

`TimelineTuningConfiguration` stores safe non-secret developer thresholds in preferences:

- near-newest message threshold
- visible-range update debounce milliseconds
- load-to-unread max attempts
- reference fetch max attempts
- reference fetch cooldown seconds
- ack debounce milliseconds

Values clamp to conservative ranges. Changing tuning updates local behavior and diagnostics but does not trigger live network fetches by itself.

## Visible Range Validation

`TimelineVisibleRangeValidator` reports non-crashing warnings for missing visible IDs, channel mismatch, first/last ordering problems, and at-newest contradictions. Warnings are surfaced in diagnostics and the Developer tab.

## Route Verification

Phase 12 verified:

- `GET /channels/{target}/messages/{msg}` for single-message fetch
- `GET /channels/{target}/messages?nearby={msg}` for around-message fetch
- `POST /channels/{target}/search` for selected-channel search
- pinned-only search through `POST /channels/{target}/search` with `pinned: true`

Findings are recorded in `Docs/Research.md`.

## Reference Fetching

Live reference fetching uses the verified single-message route only after Live Manual connection and visible/explicit timeline need. Results are cached in memory only. Forbidden, not-found, rate-limited, unavailable, and unsupported states map to short safe copy. Mock previews and tests use in-memory resolvers only.

## Around Fetch And Search

Around-message fetch uses verified `nearby` only for explicit recovery actions and merges results into the existing in-memory channel history. Selected-channel search is Live Manual only, explicit, non-persistent, and scoped to the active channel.

## Find In Loaded Messages

Local find searches only currently loaded messages in memory, works in mock and live loaded data, never calls the network, and creates a jump intent when selecting a result.

## Security And Redaction

No tokens, raw credentials, session tokens, or raw server responses are displayed in diagnostics. Diagnostic copy uses existing redaction plus token-like pattern scrubbing. No live fetches run on app launch or as hidden background loops.

## Tests

Added mock-only/API-transport tests for:

- verified single-message, nearby, and channel-search request shapes
- tuning clamping and threshold behavior
- visible-range validation warnings
- loaded-message find and jump intent
- token-free diagnostics copy

Run:

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

## Deferred

Still deferred: persistent message cache/database, background sync, notifications, uploads/media UI, global search, friends/discover expansion, voice, server/channel settings, full permission resolver, moderation tools, and live automated tests requiring credentials.

## Known Risks

SwiftUI visibility remains an approximation rather than a custom virtualized timeline. The route verification result is based on official/current source and schema, not an automatic live probe. Search and around-message fetch still depend on real server permissions and rate limits in Live Manual sessions.

## Recommended Phase 13 Next Step

Phase 13 should use the new validation harness during real Live Manual sessions, tune default thresholds from observed behavior, and decide whether selected-channel search deserves a richer dedicated UI or should remain developer-focused.
