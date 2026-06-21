# Phase 46 - Member Panel Moderation Prewarm Freeze Fix

Phase 46 fixes a large-server freeze where the member panel could trigger moderation cache prewarm while SwiftUI was evaluating `MemberPanelView.body`. The sample showed the view path entering moderation base-context construction and sorting role/channel permission signatures on the main thread.

## Implemented Behavior

- Removed member-panel body-driven calls to moderation prewarm.
- Added `Phase46Runtime.swift` with cheap revision-keyed prewarm state and freeze-prevention diagnostics.
- Replaced moderation base-context and permission cache keys that sorted/stringified server roles, channel permission overrides, member roles, and ban IDs with `Phase46ModerationPrewarmKey` revision counters.
- Added a cache-only moderation menu-state reader for SwiftUI member rows, profile popovers, and moderation settings rows.
- Added lifecycle-triggered, deduped prewarm hooks for the member panel, profile popover, and Server Settings moderation section.
- Kept explicit moderation actions on the full resolver path so confirmation requests still revalidate current permissions before any destructive route is staged.

## Freeze Prevention Rules

SwiftUI view construction now reads cached menu state only. If the cache has not been prepared for the current revision key, moderation actions render disabled with a short preparing message instead of computing permissions during layout.

The lifecycle hooks may prepare menu states for the selected server's currently known members and loaded bans, but they do not perform network requests and dedupe on the revision key.

## Diagnostics

Developer Verification and copied moderation diagnostics now include Phase 46 prewarm counters:

- last prewarm trigger
- last prewarm result
- lifecycle prewarm attempts
- lifecycle prewarm dedupes
- last prepared member count

The diagnostics stay developer-only and go through the existing redaction pipeline.

## Verification

- `swift test --package-path Packages/StoatFeatures --filter 'StoatFeaturesTests/testPhase4(2|6)'`

## Manual QA Checklist

- [ ] Open a large role-heavy server and confirm the member panel appears without a main-thread stall.
- [ ] Open several member context menus after the panel appears and confirm moderation actions use cached state.
- [ ] Open a member profile popover from a server context and confirm moderation actions refresh after prewarm.
- [ ] Open Server Settings -> Moderation and confirm member, timeout, and ban rows do not trigger layout stalls.
- [ ] Copy moderation diagnostics and confirm Phase 46 prewarm counters are present and redacted.
