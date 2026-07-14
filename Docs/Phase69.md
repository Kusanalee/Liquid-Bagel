# Phase 69 - Deterministic Member Identity Refresh

Phase 69 fixes an intermittent live regression exposed during the Phase 68 Release retest: member rows could remain cached as `Unknown member`, with missing nicknames or avatars, until a later launch even though the late identity had already reached the app. The second attached Release recording ran for 123.6 seconds and kept the earlier Phase 68 performance checks green; the remaining failure was presentation correctness.

## Root Cause

- Phase 68 correctly replaced the global identity generation in the member-list cache key with a per-server presentation revision.
- That revision dictionary is intentionally `@ObservationIgnored`. Late embedded message users and members changed the selected server's token value internally, but did not notify SwiftUI to re-evaluate the `.task(id:)` that prepares member groups.
- If the first preparation won the startup race, its fallback `MemberListItem.display` values could therefore remain cached. A later launch could appear healthy simply because identity delivery won the race before the first preparation.
- The late-snapshot fallback also preferred a username before an available display name, weakening name continuity after the row finally refreshed.

## Fix

- All relevant server identity changes and REST member hydration now advance through one revision helper.
- The per-server revision remains observation-ignored and server-scoped, preserving Phase 68's no-churn rule.
- A selected-server-only observable publication revision wakes the existing member-list `.task(id:)`. Other-server, profile-only, and semantic no-op identity delivery do not publish a selected-server refresh.
- Snapshot-backed display names now precede snapshot usernames when the immediate `User` wrapper is partial or absent. Nickname and server-avatar precedence remains unchanged.
- Developer Verification reports a redacted `phase69SelectedMemberPublications` counter alongside the existing relevant-invalidation count.

No Stoat route, payload, response schema, cache budget, hydration bound, or member-list structure changed.

## Automated Proof

- The Phase 69 race test prepares an unresolved member, observes the presentation token, delivers late user and member identities, and proves one publication plus a rebuilt display name, nickname, global avatar, and server avatar.
- The same test proves identical delivery and another server's identity do not change the selected token, publication count, or cached-group revision.
- The member REST hydration regression asserts one selected publication and the existing single snapshot, member-hydration, and identity-batch commits.
- Focused Phase 43/52/68/69 coverage, complete StoatUI and StoatFeatures suites, `git diff --check`, and `Scripts/check.sh` remain the repository acceptance gate.

Completed validation for this implementation:

- focused Phase 35/43/52/68/69 member/identity lane: 12 tests passed;
- complete StoatUI suite: 41 tests passed;
- complete StoatFeatures suite: 400 tests passed;
- `git diff --check`: passed;
- `Scripts/check.sh`: all package suites passed and the signed macOS app build succeeded.

## Focused Live Retest

1. Perform three cold launches. Open the affected server member panel immediately while channel history and identities are still arriving.
2. Any temporary fallback must resolve in place without closing the panel, manually refreshing, or relaunching.
3. Verify display names, usernames, nicknames, global/server avatars, roles, presence grouping, bot badges, and profile opening.
4. Switch between two servers while identities arrive. Only the currently selected server may regroup.
5. After 30 seconds settled, CPU must remain below 10% and member grouping/publication counters must stop advancing.
6. If an unresolved row persists, copy Timeline and Identity Diagnostics before refresh or relaunch.

Large-server/member completeness remains `partial` until this repeated live pass succeeds. The previously accepted Phase 68 interaction checks do not need a broad rerun.
