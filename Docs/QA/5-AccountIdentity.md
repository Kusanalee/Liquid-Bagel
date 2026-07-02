# QA Lane 5 - Account and Identity

Covers login, saved startup, sessions, profile view/edit, avatar/banner propagation, status, and identity hydration. Follows the Phase 49 ledger.

## Prerequisites

- Two real accounts; MFA checks only if an MFA-enabled account exists (row may stay `partial` otherwise, per Phase 54).
- Clean scoped Keychain state available for the first-run checks (or a disposable environment profile).

## Evidence Rules

Never record tokens, passwords, MFA values, session IDs, raw profile content, private URLs, or local paths.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | Clean state → launch | First-run login card appears instead of the shell | | |
| 2 | Sign in with email/password | Validates, saves scoped credential, connects; shell appears after Ready | | |
| 3 | Bad password (and bad MFA response if available) | Safe error copy; no Keychain write | | |
| 4 | MFA challenge/continuation (if account available) | Shared save-and-connect path completes to Ready | | |
| 5 | Import a real session token from first-run Advanced and from Settings | Validation, save, connect; failure leaves Keychain untouched | | |
| 6 | Quit and relaunch with a saved credential | Auto-connect exactly once for the selected environment | | |
| 7 | Force a saved-credential failure; use retry, sign-in, forget, environment switch | All recovery paths work without loops; credentials never cross environment scopes | | |
| 8 | Refresh session list; rename a noncritical session; revoke another session; compare with official client | List/rename/revoke match | | |
| 9 | Revoke/logout the current session | Local state returns to first-run/sign-in recovery | | |
| 10 | Open own profile from account menu; open others from message author, member row, DM row, Home, and system-event tokens | Banner, bio, roles, mutuals, bot owner, actions render; role-colored names in server context | | |
| 11 | Edit display name; clear it; check both accounts | Propagates to menu/profile/messages; fallback shows no full raw IDs | | |
| 12 | Edit and clear profile bio | Popover renders safe Markdown, then clears | | |
| 13 | Upload avatar, verify all surfaces plus second account, then remove | Propagates and cache-invalidates both ways | | |
| 14 | Upload profile background, verify after reconnect, then remove | Propagates and survives reconnect | | |
| 15 | Try oversized/unsupported avatar/background files | Safe rejection before any mutation | | |
| 16 | Cycle status Online/Idle/Focus/Do Not Disturb/Invisible; check second-account visibility | PATCH succeeds with optimistic rollback on failure; Busy shows as Do Not Disturb | | |
| 17 | Set and clear custom status text (Phase 55 feature) from both this and the official client | Text propagates both directions | | |
| 18 | Copy Developer Verification diagnostics after this lane | Auth/startup/profile diagnostics stay redacted | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| Account and session / login | Steps 1-3 pass |
| Account and session / MFA | Step 4 passes (stays `partial` if no MFA account) |
| Account and session / token/session import | Step 5 passes |
| Account and session / live-default startup | Steps 6-7 pass |
| Account and session / session list + revoke sessions | Steps 8-9 pass |
| Account and session / account profile view | Step 10 passes |
| Account and session / account profile edit | Steps 11-12 pass |
| Account and session / avatar edit + banner/background edit | Steps 13-15 pass |
| Account and session / status/custom status | Steps 16-17 pass |
| Core chat / user/avatar hydration | Steps 10-13 show mutations propagating through chat surfaces without raw IDs |
