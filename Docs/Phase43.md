# Phase 43 - Identity Hydration Recovery and Clickable System Event Users

Phase 43 introduced the identity snapshot layer that lets Liquid Bagel keep readable names and avatar metadata after member churn while avoiding raw full IDs in normal chat surfaces. This phase is implemented in code but remains live-sensitive and partial until real server QA is complete.

## Identity Snapshot Source Of Truth

- `Phase43IdentitySnapshotStore` is the local source of truth for hydrated identity facts.
- Snapshots merge Ready users/members, message-embedded users/members, member REST users, relationship/profile data, ban-list data, moderation-action preservation, realtime user/member updates, and verified `fetchUser(userID:)` hydration results.
- Per-server overlays preserve member nicknames, member avatars, roles, and current/historical membership state.
- Historical snapshots are kept after member removal so system events, ban/kick flows, and older messages do not collapse to full raw IDs.

## Display Precedence

Display resolution uses `Phase43IdentitySnapshotStore.resolvedDisplay` through the view model resolver.

Precedence is:

1. Server member nickname when a server context exists.
2. User display name.
3. Username.
4. Historical snapshot values from prior member/user data.
5. Shortened fallback only when no readable identity exists.

Full raw user IDs must not be used as ordinary display names. Fallbacks should remain shortened and clearly non-profile identity.

## Hydration Queue Policy

- Visible unresolved identities enqueue through `enqueuePhase43IdentityHydrationIfNeeded`.
- The only verified visible-user hydration route is `fetchUser(userID:)`.
- The queue is bounded by `Phase43HydrationPolicy.maxBatchEnqueue`.
- In-flight requests are deduped by user ID.
- Failures apply cooldowns using `firstFailureCooldown`, `repeatedFailureCooldown`, and `repeatedFailureThreshold`.
- Hydration is not performed from SwiftUI row body or context menu construction.

## Clickable System Event Participants

- System events render through `Phase27SystemEventPresenter` plus Phase 43 participant resolution.
- Resolved participants become native clickable tokens in `Phase43SystemEventRow`.
- Clickable tokens open the profile popover with `.systemEventParticipant` source.
- Unresolved participants remain safe human-readable fallback text rather than raw IDs.
- Visible system events enqueue identity hydration for unresolved actors/participants.

## Profile Open Sources

Phase 43 feeds the shared profile surface from messages, member rows, DMs, friends, home, search-visible identities, and system-event participants. Profile open enqueues identity hydration if local data is incomplete and then uses the existing bounded profile fetch/media paths.

## Avatar Metadata Preservation

- User and member avatar file metadata is merged into snapshots.
- Member removal preserves identity/avatar metadata before the realtime member disappears.
- Avatar load failures are counted diagnostically but do not clear stored identity or avatar metadata.
- Avatar cache invalidation happens only when file identity changes.

## Diagnostics And Redaction

Developer Verification exposes Phase 43 identity diagnostics through the visible identity diagnostics copy path.

Counters include:

- known snapshots
- historical-only snapshots
- unresolved visible user IDs
- clickable and fallback system-event participants
- hydration queued/in-flight/success/failure/dedupe/cooldown counts
- avatar metadata preservation and avatar load failures
- profile opens from system events
- current-user edit snapshot merges
- member-removal identity preservation

Copied diagnostics use the existing redaction pipeline and redact raw payloads, URLs, local paths, emails, token/session/password/MFA-like values, moderation reason text, and long full IDs.

## Blocked Or Deferred Scope

- Live QA is still required before marking Phase 43 identity rows done.
- No unverified identity/member routes were added.
- No persistent offline profile/message database was added.
- Full official profile/action parity remains outside Phase 43.

## Manual QA Checklist

- [ ] Open a large server with missing/offline members and confirm names do not show full raw IDs.
- [ ] Kick or ban a test member and confirm old messages/system events keep readable historical identity.
- [ ] Open profiles from message author names, member rows, DM rows, search results, and system-event participant tokens.
- [ ] Confirm unresolved system-event users remain safe fallback text and hydrate when visible.
- [ ] Cause an avatar/media load failure and confirm identity/avatar metadata is not cleared.
- [ ] Copy Developer Verification diagnostics and confirm redaction removes tokens, full IDs, URLs, paths, emails, passwords, MFA values, raw payloads, and moderation reason text.
