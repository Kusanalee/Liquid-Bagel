# Phase 13 Summary

## What Was Implemented

Phase 13 turns the Phase 12 validation harness into a more practical Live Manual calibration and selected-channel search workflow. Liquid Bagel remains mock-safe: it does not auto-connect on launch, does not auto-validate saved credentials, and does not add persistent message storage or background search.

Implemented:

- in-memory timeline calibration runs and observations
- conservative timeline tuning presets and reset-to-default
- advisory calibration recommendations
- clearer route capability display
- user-facing selected-channel search panel
- distinct loaded-message find, Live Manual channel search, and pinned-message search modes
- route-aware search result navigation and explicit load-around-result flow
- search/calibration accessibility labels
- mock-only tests for calibration, presets, search state, route gating, and accessibility helpers

## Live Manual Calibration Workflow

The Developer tab now has a Timeline Calibration section. A developer can explicitly start a calibration run, add checkpoint notes, stop the run, copy redacted output, and apply advisory recommendations.

Calibration runs are memory-only. They are not saved to preferences, disk, or a message database. Checkpoints record current `TimelineDiagnostics` and validation warnings. Timeline actions such as load older, jump newest, jump unread, search jump, load-around, and ack can add observations while a run is active.

Copied calibration output uses the existing diagnostic redaction path and short IDs.

## Tuning Presets And Recommendations

`TimelineTuningPreset` adds four safe presets:

- Conservative
- Balanced
- Responsive
- Debug Strict

The default remains conservative. Presets map to validated `TimelineTuningConfiguration` values, and reset restores `.defaults`.

Recommendations are advisory only. The app never mutates tuning automatically; the user must click Apply Recommendation.

## Selected-Channel Search Behavior

The channel header search button and `Command+F` open a narrow “Search this channel” panel. The panel has explicit modes:

- Find in loaded messages
- Live channel search
- Pinned in this channel

Search runs only when the user presses Enter or Search. There is no background indexing or search while typing.

Live and pinned search require connected Live Manual state and use the verified selected-channel route only after explicit action. Mock mode can still use loaded-message find.

## Local Find Behavior

Find in loaded messages searches only the current in-memory timeline. It never calls the network and works in mock and live loaded data. Results can jump immediately because they are already loaded.

## Pinned Search Behavior

Pinned search is selected-channel only and uses the verified `POST /channels/{target}/search` shape with `pinned: true`. Results are non-persistent and use normal search result navigation.

## Search Result Navigation

Loaded results create a timeline selection and scroll intent.

Unloaded results show “Result outside loaded range.” If the around-message route is source-verified, the user can explicitly choose “Load around result.” That flow uses the existing `nearby` fetch through `ChannelMessageController`, merges/dedupes in memory, marks `loadedAroundMessageID`, and scrolls to the target when returned.

## Route Capability Display

The Developer tab now lists capability status for:

- single-message fetch
- around-message fetch
- selected-channel search
- pinned search

The status is labeled as source-verified/not live-probed. There is no automatic route probing.

## Command Routing Changes

Added commands for selected-channel search, loaded find, Live Manual search, pinned search, next/previous search result, jump to selected result, load around selected result, calibration start/checkpoint, and diagnostics copy.

Commands no-op safely with disabled reasons when the selected channel, Live Manual connection, route verification, or search result state is missing.

## Accessibility Improvements

Search panels, result rows, pinned/unloaded result state, route capability rows, calibration controls, presets, recommendations, and result counts now have explicit helper labels. Labels use safe display strings only.

## Security And Redaction

Phase 13 keeps the existing security model:

- no tokens in preferences
- no token/session values in diagnostics or calibration copy
- no raw server responses in user-facing errors
- no hidden live network behavior
- no background search loops
- no persistent search result state

## Tests Added

Added mock-only tests for:

- calibration lifecycle and redacted copy
- tuning preset validation and reset
- loaded search state and jump intent
- Live Manual search connection gating
- route-gated load-around search result navigation
- search accessibility helper text
- persistence preset safety

## Mocked Vs Live

Mock mode remains local. Live behavior is limited to explicit Live Manual actions using existing verified routes. Automated tests do not require live credentials or real network access.

## Deferred

Still deferred: persistent message cache/database, background sync, notifications, uploads/media UI, global search, full friends/discover APIs, voice, server/channel settings, full permission resolver, moderation tools, and live automated tests requiring credentials.

## Known Risks

SwiftUI row visibility remains approximate. Route capability display is source-verified rather than live-probed. Live search and nearby fetch still depend on server permissions and rate limits in real sessions.

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

## Recommended Phase 14 Next Step

Use real Live Manual calibration notes to decide whether default tuning should move from conservative to balanced, then consider modest result highlighting inside the loaded timeline without adding persistent indexing or global search.
