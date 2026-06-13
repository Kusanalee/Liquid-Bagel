# Phase 41: Profile and Account Editing Verification

## Summary

Phase 41 verifies and mock-tests current-user profile editing for display name, profile bio/content, avatar, and profile background/banner. The implementation uses only the verified user edit route and verified upload tags, keeps status editing on its existing path, and keeps parity conservative until live QA proves real propagation.

## Route and Schema Verification

- Generated API HEAD `366e0882d50d61c977883deb30fe6aa6eec71a73` confirms `PATCH /users/{target}` with `DataEditUser` request and `User` JSON response.
- Backend HEAD `c70459b10ce107611b9d478add26db372361baf2` confirms the route is authenticated, edits self by default, allows other-user edits only for bot-owner/privileged cases, validates payloads, and returns `user.into_self(false)`.
- `DataEditUser` includes `display_name`, `avatar`, `status`, `profile`, `badges`, `flags`, and `remove`. Liquid Bagel exposes only display/profile/avatar/background fields in Phase 41.
- `DataUserProfile` includes optional `content` and `background`; missing fields preserve existing values.
- Verified remove fields for this phase are `DisplayName`, `Avatar`, `ProfileContent`, and `ProfileBackground`.
- Avatar uploads use multipart field `file` at the `avatars` upload tag. Background/banner uploads use multipart field `file` at the `backgrounds` upload tag. Upload success returns `{ "id": "<file id>" }`.
- Backend limits verified from source: display name 2-32 chars, profile content up to 2000 chars, avatar/background file IDs 1-128 chars, avatar uploads 4 MB image-only, background uploads 6 MB image-only.

## Upload-Before-Mutation Flow

The editor stages selected files through the existing explicit user action path. Liquid Bagel validates image type and source-verified size limits locally, sanitizes filenames, uploads to `avatars` or `backgrounds`, then sends the returned file ID in `UserEditDraft`.

If upload fails, no profile mutation is sent. If mutation fails after upload, the editor remains open and the central snapshot/profile state is not changed. Profile saves use post-success merge rather than optimistic local edits.

## Profile Editor Behavior

The native SwiftUI editor lives in Account Settings and is also reachable from the current-user profile popover through `Edit Profile`. It shows current/staged avatar and banner previews, display name editing, profile bio editing, Markdown preview through the existing renderer, choose/remove controls for avatar and banner, Save/Cancel, progress, dirty-state save enablement, and safe error copy.

The editor does not expose account deletion, username, email, or password changes.

## Cache and Snapshot Merge Behavior

On a successful edit, Liquid Bagel merges the returned `User` with `upsertUser(_:)` so current-user menu, profile popover, timeline author resolution, DM participant rows, and other central user displays see the new user data. Because the route returns `User` rather than `UserProfile`, Phase 41 overlays the submitted profile content/background locally after success.

Only affected in-memory image keys are invalidated: old/new user avatar keys and old/new profile background keys. Phase 41 does not clear all media caches and does not add persistent media or message caching.

## Diagnostics

Developer Verification includes Profile Edit Diagnostics when developer runtime controls are enabled. It records last action, route category, edited field categories, upload tag category, upload result, mutation result, duration, cache invalidation count, safe error category, and returned data shape.

Copied diagnostics use redaction for tokens, raw response bodies, full user/file/session IDs, local paths, URLs, email addresses, passwords, MFA tickets/responses, and raw JSON payloads. Profile bio/content text is not included in copied diagnostics.

## Tests Added

- `StoatModels`: user/profile edit draft encoding, nil omission, and exact remove strings.
- `StoatAPI`: `PATCH /users/{id}` method/path/body/response checks and avatar/background upload tag multipart checks.
- `StoatFeatures`: upload failure prevents mutation, mutation failure preserves state, successful edit merges returned user/profile overlay, targeted cache invalidation, dirty-state/save enablement, safe error mapping, diagnostics redaction, and parity rows staying `partial`.
- Existing status editing and Phase 40 DM tests remain in scope for the verification run.

## Security Notes

- Current user auth remains `X-Session-Token`.
- Mutation payloads carry uploaded file IDs, not raw file data.
- Diagnostics do not include tokens, paths, full IDs, raw response bodies, raw JSON with user content, or profile bio text.
- No account deletion or account-danger-zone route is added.
- No hidden prefetch loop, network storm, or persistent media/message cache is added.

## Manual QA Checklist

- Connect with a real account.
- Open Account Settings profile editor.
- Change display name and confirm current-user menu/profile/message rows update.
- Clear display name and confirm fallback behavior.
- Edit profile bio/content and confirm profile popover renders it.
- Clear profile bio/content.
- Upload avatar and confirm profile/current-user/message rows update.
- Remove avatar and confirm fallback avatar appears.
- Upload profile background/banner and confirm profile card updates.
- Remove profile background/banner.
- Try oversized/unsupported file and confirm safe rejection before mutation.
- Simulate network failure and confirm no local corruption.
- Confirm profile changes propagate after app relaunch/reconnect.
- Copy profile edit diagnostics and confirm no secrets or user content leak.

## Deferrals

- Live QA is still required before `account profile edit`, `avatar edit`, or `profile banner/background edit` can become `done`.
- `account profile view` remains `partial` until live banner/bio/actions/mutual behavior is verified.
- `user/avatar hydration` remains `partial` until real chat and bot-heavy server behavior is verified.
- Username, email, password, MFA/account management, and account deletion are out of scope.

## Recommended Phase 42

Run live QA for Phase 41 propagation, then tighten any remaining profile-view gaps found in real accounts: reconnect persistence, banner/bio refresh behavior, profile action parity, and bot/member-heavy identity hydration.
