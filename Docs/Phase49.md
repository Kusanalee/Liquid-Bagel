# Phase 49 - Account/Profile Live Parity Proof

Phase 49 is an evidence-led account and profile parity pass. It focuses on real official-client comparison for authentication, saved-session startup, session management, profile viewing/editing, avatar and background propagation, status changes, and visible identity propagation through account/profile surfaces.

This repository implementation pass did not capture live dogfood evidence. No runtime defect was proven locally, no new routes were added, and all live-sensitive rows remain conservative until the checklist below is completed with real accounts.

## Scope And Route Boundaries

- Use the existing Phase 38/39 `AppSessionCoordinator` login, MFA, token import, saved credential, startup, retry, forget, and current-session revoke paths.
- Use the existing Phase 6 `AccountSessionViewModel` session list, rename, revoke, revoke-other, and logout paths.
- Use the existing Phase 41 profile editor for display name, profile content, avatar upload/remove, and profile background upload/remove.
- Use the existing Phase 36 status PATCH path for current-user presence changes.
- Use the existing Phase 43 identity/profile resolution path when account/profile changes need to appear in chat, DMs, member rows, or profile popovers.
- Do not add username, email, password, account deletion, server deletion, APNs, background sync, persistent profile/media/message caches, hidden profile fetching, or unverified routes.
- Keep diagnostics developer-only and redacted. Do not record tokens, passwords, MFA payloads, raw server bodies, full session IDs, local paths, private URLs, or profile content text in evidence.

## Live Evidence Ledger

| Surface | Official-client comparison | Liquid Bagel result | Fix needed | Verification | Final parity status |
| --- | --- | --- | --- | --- | --- |
| Login | Pending live email/password sign-in against production | Phase 39 mock/source coverage validates, saves scoped credential, and starts live connection through `AppSessionCoordinator` | Unknown until live QA | Focused tests required; live checklist pending | `partial` |
| MFA | Pending real MFA challenge and continuation | Phase 39 MFA continuation uses the shared validated save-and-connect path | Unknown until MFA account QA | Focused tests required; live checklist pending when an MFA account is available | `partial` |
| Token/session import | Pending real token import from first-run and Settings surfaces | Token import validates, saves to the selected environment scope, and connects; failed validation leaves Keychain untouched | Unknown until live QA | Focused tests required; live checklist pending | `partial` |
| Live-default startup | Pending quit/relaunch dogfood with saved credential, failed credential, retry, forget, and environment switch | Startup auto-connect is idempotent once per selected environment and keeps failures recoverable | Unknown until live QA | Focused tests required; live checklist pending | `partial` |
| Session list | Pending official-client comparison for current and other sessions | Account session surface uses verified session routes through `AccountSessionViewModel` | Unknown until live QA | Session tests required; live checklist pending | `partial` |
| Revoke sessions | Pending revoke-other and current-session revoke comparison | Revoke flows use verified session routes and clear local state when the current session is revoked | Unknown until live QA | Session/auth tests required; live checklist pending | `partial` |
| Logout | Pending Phase 49 regression pass | Existing explicit logout/disconnect row remains stable | No new fix proven | Auth tests required; live checklist pending | `done` unchanged |
| Account profile view | Pending official-client comparison for banner, bio, roles, mutuals, bot owner, actions, and open sources | Profile popover opens from account/chat/member/DM/Home/system-event sources with local data immediately and bounded fetch/media loading | Unknown until live QA | Profile tests required; live checklist pending | `partial` |
| Profile edit | Pending display name and profile content propagation proof | Phase 41 editor patches source-verified fields and merges returned user/profile overlay after success | Unknown until live QA | Phase 41 tests required; live checklist pending | `partial` |
| Avatar edit | Pending upload/remove propagation proof across account menu, profile, messages, DMs, and second account | Phase 41 uploads through verified `avatars` tag, patches avatar file ID, and invalidates targeted image caches | Unknown until live QA | Phase 41 tests required; live checklist pending | `partial` |
| Profile banner/background edit | Pending upload/remove propagation proof in profile card and after reconnect | Phase 41 uploads through verified `backgrounds` tag, patches `profile.background`, and invalidates targeted background cache | Unknown until live QA | Phase 41 tests required; live checklist pending | `partial` |
| Status/custom status | Pending live status PATCH and second-account visibility comparison | Current-user status menu patches `status.presence` with optimistic rollback; Busy displays as Do Not Disturb | Unknown until live QA; richer custom-status editing still not claimed | Phase 36/37 status tests required; live checklist pending | `partial` |
| User/avatar hydration through profile/chat surfaces | Pending account/profile mutation visibility in chat, member rows, DMs, profile opens, and second-account views | Phase 43 snapshot/resolver preserves readable names and avatar metadata and avoids full raw IDs in normal surfaces | Unknown until live QA | Identity/profile tests required; live checklist pending | `partial` |
| Diagnostics redaction | Pending copied Developer Verification review after account/profile audit actions | Existing auth, startup, profile edit, identity, and diagnostics redaction paths are source/mock covered | Add only categorical evidence if live gaps require it | Redaction tests required; live copy review pending | diagnostics row remains `done` |

## Manual Dogfood Checklist

Use two real accounts and one safe test server. Keep the official client open beside Liquid Bagel for visual and behavior comparison.

1. Fresh install or clean scoped Keychain state, then confirm the first-run login surface appears instead of the shell.
2. Sign in with email/password and confirm realtime Ready and normal shell access.
3. If an MFA-enabled account is available, trigger MFA, submit a valid challenge response, and confirm Ready.
4. Try a bad password and, if available, a bad MFA response; confirm safe user-facing errors and no Keychain write.
5. Import a real session token from first-run Advanced and from Settings; confirm validation, save, and connect.
6. Quit and relaunch with a saved credential; confirm auto-connect happens once for the selected environment.
7. Simulate or observe saved credential failure; confirm retry, sign-in, forget, and environment-switch recovery do not loop.
8. Create or select a custom environment profile and confirm credentials do not move across environment scopes.
9. Open Account and Connection Settings, refresh sessions, and compare current/other sessions with the official client.
10. Rename a noncritical session if safe, revoke another session, then confirm the list updates.
11. Revoke/logout the current session and confirm local credential state returns to first-run/sign-in recovery.
12. Open the current-user profile from the account menu/profile popover and compare banner, avatar, display name, username, bio, roles, mutual sections, bot owner, and actions where data exists.
13. Open profiles from message author, member row, DM row, Home current user, search/result contexts if available, and system-event participant tokens.
14. Change display name, confirm current-user menu/profile/message rows update, and confirm the second account sees the change after refresh/reconnect.
15. Clear display name and confirm fallback behavior matches the official client closely enough without showing full raw IDs.
16. Edit profile bio/content, confirm the profile popover renders it, then clear it.
17. Upload avatar, confirm account/profile/message/DM surfaces update locally and for the second account, then remove it.
18. Upload profile background/banner, confirm profile card update locally and after reconnect, then remove it.
19. Try oversized or unsupported avatar/background files and confirm safe rejection before mutation.
20. Change status through Online, Idle, Focus, Do Not Disturb, and Invisible; confirm rollback on failure if possible and compare second-account visibility.
21. Copy Developer Verification diagnostics after the audit and confirm no tokens, passwords, MFA values, raw server bodies, full session IDs, raw profile content, local paths, or private URLs leak.

## Promotion Rules

- Promote a row to `done` only when this ledger has live pass evidence for that row and no live-sensitive gap remains.
- Keep a row `partial` when behavior is implemented and tested only with source verification, mocks, or incomplete dogfood.
- Keep MFA `partial` if no MFA-enabled real account is available.
- If live QA exposes a concrete bug, fix it in the existing owner seam, add a focused regression test, and rerun focused tests plus the full repo gate before updating the matrix.

## Repository Verification

This implementation pass added the Phase 49 ledger and conservative matrix pointers only. The preflight commands passed before closing the pass:

```sh
swift test --package-path Packages/StoatFeatures --filter 'Phase3(8|9)|Phase41'
swift test --package-path Packages/StoatAPI --filter Phase41
swift test --package-path Packages/StoatModels --filter Phase41
git diff --check
Scripts/check.sh
```

Results:

- `StoatFeatures` Phase 38/39/41 slice: 42 selected tests passed.
- `StoatAPI` Phase 41 slice: 2 selected tests passed.
- `StoatModels` Phase 41 slice: 3 selected tests passed.
- `git diff --check`: passed.
- `Scripts/check.sh`: passed; all package tests completed and the macOS app build ended with `** BUILD SUCCEEDED **`.
