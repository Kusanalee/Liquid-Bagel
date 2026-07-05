# Phase 59 - Idle CPU, Avatar Startup, And Reaction Reliability

Phase 59 responds to the fifth live-QA report. Interaction freezes are now confirmed fixed, repeated sends work, and signed notifications deliver. The remaining reported failures were sustained 89-98% idle CPU, slow initial avatar presentation, and reactions that did not appear after activation. Two-account and native-macOS lanes remain deferred by the tester.

## Sampled Root Cause

- A five-second sample of the live debug process captured it at 136% CPU.
- App-owned background work repeatedly rebuilt `Phase51PresentationBuilder.shell`, where `Phase22Derivations.friendItems` mapped and locale-sorted every hydrated server user. A 2,324-member server therefore entered the Friends derivation even though almost none of those users had relationships.
- After removing that loop, a second live sample exposed a scene-lifecycle loop: each `RootScene` reconstruction evaluated a new `LiquidBagelAppModel`, including a complete shell and quick-switcher index, before SwiftUI restored the existing `@State` value. Model ownership now lives in stable app state and is passed into the scene.
- Native Liquid Glass remains enabled. The post-fix sample did not identify the backdrop as dominant, so the static material fallback was not warranted.

## Implemented Behavior

- **Change-driven shell presentation:** raw snapshot assignment no longer rebuilds the shell. Selection, local-read, session, and relevant realtime changes advance a shell-specific revision. Member-only and unrelated message/media changes do not.
- **Single-flight/latest-only builds:** one shell builder runs at a time. Identical requests are skipped, newer requests coalesce, and a stale result is discarded before the latest state is built. Developer diagnostics expose request/build/skip/coalesce/discard counts, relationship candidate count, and the last safe invalidation reason.
- **Relationship-only Friends derivation:** the Friends builder considers only users named by current-account relationships or explicit non-none relationship state. Sort keys are normalized once before sorting.
- **Stable app-model ownership:** `LiquidBagelApp` owns the observable model once and injects it into `RootScene`; scene graph reevaluation no longer constructs and discards full runtime graphs.
- **Bounded avatar first paint:** the image queue is stable and priority ordered: visible timeline avatars, visible member avatars, shell-critical identity media, other identity media, message media, then backgrounds. Launch/selection warming is capped at 32 unique current-user, selected-server, and recent-conversation assets; member rows remain visibility-driven.
- **Off-main avatar decode:** cached or fetched avatar bytes are decoded into the existing bounded decoded-image pipeline before presentation. Avatar completion no longer invalidates prepared Markdown/actions/reactions for the whole timeline.
- **Optimistic reactions:** confirmed-message reactions update locally before the verified API request. One mutation per message/emoji may be in flight; duplicates are ignored. Failure rolls back and shows a transient safe error, while realtime echoes remain idempotent through set-based reaction state.

## Automated Verification

Targeted Phase 59 coverage proves:

- a 2,324-member member-only update does not request or build shell presentation, and only the real relationship user enters Friends;
- visible avatar work promotes ahead of queued identity/background work;
- avatar completion does not invalidate prepared timeline rows;
- reaction add is immediately optimistic and duplicate in-flight activation is deduped;
- reaction failure rolls back and exposes a transient error.

Completed acceptance:

```sh
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatFeatures
git diff --check
Scripts/check.sh
```

- `Scripts/check.sh` passed all package suites and the macOS app build.
- The rebuilt live app was observed every five seconds for 40 seconds after launch and remained at `0.0%` CPU, accumulating about `0.54` CPU-seconds total.
- A final five-second sample showed the process sleeping in `mach_msg2_trap`; it contained no repeating shell-presentation, Friends-sort, image/decode, app-model-construction, or glass-backdrop stack.

## Live QA Still Required

1. Confirm cached visible avatars appear within one second and uncached visible avatars begin progressively without bulk member fetching.
2. Add and remove a Unicode reaction from the single account; confirm immediate count changes, survival through realtime/reload, and safe rollback on a testable failure.
3. Reconfirm repeated sends, signed notifications, and interaction-freeze behavior remain green.

Performance remains `partial` conservatively until the tester confirms the same result during the interaction repeat. Avatar hydration and reaction rows remain `partial` until their live checks are recorded. Two-account group/mention/cross-account notification checks and the native macOS lane remain deferred, not failed.
