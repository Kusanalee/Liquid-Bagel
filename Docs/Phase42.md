# Phase 42 Moderation Tooling

Phase 42 expands the verified Phase 26 moderation routes into a native, confirmed moderation experience. It adds central permission and hierarchy resolution, one confirmation path for destructive actions, a Server Settings moderation dashboard, safe post-action state merges, redacted diagnostics, and tests. Parity rows remain `partial` until the live checklist below is completed on a real test server.

## Route and Schema Verification

Verified generated API source:

- `javascript-client-api` commit `366e0882d50d61c977883deb30fe6aa6eec71a73`
- `routes.ts`, `schema.ts`, and `OpenAPI.json`

Verified backend source:

- `stoatchat` commit `c70459b10ce107611b9d478add26db372361baf2`
- `member_edit.rs`, `member_remove.rs`, `ban_create.rs`, `ban_list.rs`, and `ban_remove.rs`

Liquid Bagel implements only these verified moderation routes:

- `GET /users/{target}` through `fetchUser(userID:) -> User`, used only for bounded identity hydration fallback.
- `GET /servers/{target}/bans` through `fetchServerBans(serverID:) -> BanListResult`.
- `PUT /servers/{server}/bans/{target}` through `banMember(serverID:userID:draft:) -> ServerBan`.
- `DELETE /servers/{server}/bans/{target}` through `unbanMember(serverID:userID:)`.
- `DELETE /servers/{server_id}/members/{member_id}` through `kickMember(serverID:userID:)`.
- `PATCH /servers/{server_id}/members/{member_id}` through `editMember(serverID:userID:draft:)`.

Timeout apply uses `DataMemberEdit.timeout` as an absolute timestamp. Timeout clear uses `remove: ["Timeout"]`. `BanCreateDraft.deleteMessageSeconds` remains modeled for compatibility, but the Phase 42 UI always sends `nil` because message purges are out of scope.

## Implemented Behavior

- Added `Server Settings -> Moderation` with members, bans, and timeouts sections.
- Added a central `ModerationActionResolver` for allowed actions, disabled reasons, hierarchy checks, route availability, and confirmation requirements.
- Routed kick, ban, unban, timeout, and remove-timeout through one native confirmation sheet.
- Kept member-list row context menus, profile popover actions, server settings member rows, ban rows, and timeout rows on the same coordinator path.
- Ban confirmation supports the verified optional reason field. Kick, timeout, remove-timeout, and unban do not expose reason fields.
- Timeout presets are 5 minutes, 10 minutes, 1 hour, 6 hours, 24 hours, 7 days, and custom date/time.
- The timeouts dashboard is backed by hydrated selected-server member state. No separate timeout-list route is used because none is verified.
- Ban-list refresh is explicit and selected-server scoped. Missing ban identities are hydrated through verified `GET /users/{target}` with a bounded fallback.

## State Updates

- Kick removes only the selected-server member entry and preserves cached user identity.
- Ban removes the member, patches or refreshes the ban list when loaded, and preserves cached user identity.
- Unban removes only the ban entry and does not re-add a member.
- Timeout and remove-timeout merge the returned `ServerMember` from the verified member edit route.
- Failures leave previous member and ban state intact and surface a safe error category.

## Permissions and Safety

The resolver blocks:

- No selected server.
- Disconnected live actions.
- Unverified or unavailable routes.
- Missing permission.
- Permission or member data that is not hydrated enough to decide safely.
- Self moderation.
- Server owner as target.
- Equal-or-higher target role.
- Unknown hierarchy.
- Kick or timeout for nonmembers.
- Ban for already banned users.
- Unban for users not in the current ban list.
- Remove-timeout for members not currently timed out.
- Timeout targets that can themselves time out members when the current user is not the server owner.

The server owner can moderate other users, but the owner can never be moderated as a target.

## Diagnostics

Developer Verification includes Phase 42 Moderation Diagnostics with:

- Last action category.
- Selected-server presence category.
- Target category.
- Permission result category.
- Route category.
- Request result category.
- Response shape category.
- Safe error category.
- Timeout duration bucket, not exact arbitrary text.
- Member cache mutation category.
- Ban and timeout known/rendered/pending counts.
- Elapsed duration bucket.
- Reason-redaction flag.

Copied diagnostics redact session tokens, raw payloads, full IDs, local paths, URLs, emails, password-like strings, MFA strings, and user-entered moderation reason text.

## Blocked and Deferred

These remain intentionally out of scope or blocked by unverified API:

- Server deletion.
- Account deletion.
- Audit logs.
- Reports.
- Warnings.
- Mod notes.
- Message purges.
- Channel lockdowns.
- Softbans.
- Bulk destructive moderation.
- Any route or field not verified from the generated API or backend source.
- A full timeout-list endpoint. Active timeout management currently uses selected-server member state only.

## Manual QA Checklist

- [ ] Connect with a real account on a test server.
- [ ] Confirm moderation dashboard appears only where relevant.
- [ ] Confirm non-moderator sees disabled/permission-denied states, not working destructive actions.
- [ ] Kick a normal test member.
- [ ] Confirm kicked member disappears from member list after refresh/realtime.
- [ ] Confirm kicked user's old messages still show a readable name/avatar fallback.
- [ ] Ban a normal test member.
- [ ] Confirm banned member disappears from member list.
- [ ] Confirm ban appears in ban list.
- [ ] Confirm system event row names the affected user.
- [ ] Unban the user.
- [ ] Confirm ban list updates and user is not incorrectly re-added as a member.
- [ ] Apply timeout to a normal member with a preset duration.
- [ ] Confirm timeout displays in dashboard/profile/member row if data is available.
- [ ] Remove timeout.
- [ ] Confirm timeout state clears after refresh/realtime.
- [ ] Try to moderate self.
- [ ] Try to moderate server owner.
- [ ] Try to moderate equal/higher role.
- [ ] Try moderation without permission.
- [ ] Try action during network failure and confirm no local corruption.
- [ ] Copy moderation diagnostics and confirm no tokens, raw JSON, full IDs, URLs, paths, emails, or reason text leak.
- [ ] Test on a larger/role-heavy server for member list performance.
- [ ] Confirm member panel does not freeze when opening context menus.
- [ ] Confirm Phase 41 profile editor still works after moderation changes.
