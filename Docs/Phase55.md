# Phase 55 - Remaining Code Parity And Live-QA Enablement

Phase 55 closes the code gaps that live QA cannot close and equips the Phase 54 audit lanes with runnable checklists. It adds custom status text editing, group DM creation, and explicit user-settings cloud sync through source-verified routes, and documents the previously unlisted friends/relationships surface in the parity matrix.

## Implemented Behavior

- **Custom status text**: the current-user status context menu gains Set/Edit and Clear Custom Status actions backed by a `CustomStatusEditorView` sheet. Setting patches `status.text` (presence preserved) through the verified `PATCH /users/{currentUserID}` route; clearing uses `remove: ["StatusText"]`. Text is trimmed, bounded at 128 characters, no-op when unchanged, and applied optimistically with rollback.
- **Group DM creation**: `POST /channels/create` with `DataCreateGroup` was verified against the generated schema/routes and recorded in `Docs/Research.md`. `GroupChannelCreateDraft` validates a 1-32 character name; `createGroupChannel` exists on the live and mock API clients. A `CreateGroupChannelView` flow (Cmd-Shift-N, the New DM picker header, and the `.openNewGroup` app command) selects friends, creates the group, and opens it through the existing DM merge/select path. Group member add/remove remains deferred.
- **User settings cloud sync**: `POST /sync/settings/fetch` and `POST /sync/settings/set?timestamp=` were verified against the generated API, the backend source, and the official web client, and recorded in `Docs/Research.md`. `SyncedSettingValue` models the `[timestamp, value]` wire tuple. An allowlisted `SyncedClientPreferences` subset (message density, Liquid Glass transparency, inline image policy, notification preferences) syncs under the namespaced `liquidbagel:preferences` key. Fetch and push are explicit buttons in Appearance settings; a persisted `lastSettingsSyncTimestamp` provides last-write-wins stale-remote protection with an explicit Apply Older override. Nothing syncs automatically.
- **Pending-send message states**: audited and found already complete. `TimelineMessageStatus` (pending/failed/retrying/deleting), nonce-keyed optimistic rows, realtime-echo dedupe in the timeline merge, and the Sending/Retry/Edit-and-Retry/Discard row UI all predate this phase with reducer and retry test coverage. No code change was needed.
- **Parity matrix**: a `friends and relationships` row now documents the fully implemented Phase 22 friends surface; the status, settings-sync, group DM, and keyboard-shortcut rows reflect Phase 55. `Phase30ParityMatrixBuilder` mirrors all 80 documented rows and the Phase 54 drift test still passes. No live-sensitive row was promoted.
- **Live-QA checklists**: `Docs/QA/1-FreezeGate.md` through `Docs/QA/7-NativeMacOSGate.md` turn the Phase 54 lanes into runnable scripts with per-step evidence slots and explicit matrix-row promotion conditions. The freeze gate runs first and gates the rest.

## Safety Boundaries

- No new routes beyond the three verified above; no background sync loops, hidden fetches, or automatic pushes.
- Synced preferences exclude environment profiles, launch mode, developer flags, last-selected IDs, and anything credential-adjacent.
- Group creation only sends friend user IDs the user explicitly selected; failures keep the draft and report `Phase23Safety` redacted errors.
- Custom status and sync failures report safe copy without status codes or response bodies.

## Verification

Focused coverage (all passing):

```sh
swift test --package-path Packages/StoatModels --filter Phase55
swift test --package-path Packages/StoatAPI --filter Phase55
swift test --package-path Packages/StoatFeatures --filter Phase55
swift test --package-path Packages/StoatFeatures --filter Phase54
swift test --package-path Packages/StoatPersistence
```

- `StoatModels` Phase 55: 2 tests (group draft validation/encoding, sync tuple wire format).
- `StoatAPI` Phase 55: 2 tests (group create request/validation, sync fetch/set requests).
- `StoatFeatures` Phase 55: 10 tests (status set/clear/rollback/limit, group create success/failure, sync apply/stale/push/redaction).
- Phase 54 matrix drift: 80 matching `(section, item, status)` rows.
- `StoatPersistence`: 15 tests including the new `lastSettingsSyncTimestamp` field.

The full repository gate (`git diff --check` and `Scripts/check.sh`) is required before Phase 55 is implementation-complete.

## Live QA Still Required

1. Run `Docs/QA/1-FreezeGate.md` before all other lanes.
2. Set, edit, and clear custom status text; confirm second-account and official-client visibility (QA Lane 5, step 17).
3. Create a group with a real friend account, send messages, reconnect, and compare with the official client.
4. Push preferences from one device, fetch on another, and confirm the applied values plus the stale-remote guard.
5. Complete the remaining Phase 54 lanes via the `Docs/QA/` checklists.

All Phase 55 rows stay `partial` until this evidence is recorded.
