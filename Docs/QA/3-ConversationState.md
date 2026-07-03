# QA Lane 3 - Conversation State

Covers DMs, group DMs, Saved Notes, typing, acknowledgements, search, and jump-to-message.

## Prerequisites

- Two real accounts with an existing DM and, if possible, an existing group DM.
- One safe owned test server for the server-channel typing/ack/search checks.

## Evidence Rules

Categorical outcomes only. DM diagnostics stay redacted; no participant IDs or message content in evidence notes.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | Open Home/Direct Messages; refresh the DM list explicitly | List matches official client (order, names, icons); Saved Notes/direct/group rows stable | | |
| 2 | Open a DM from the list; load history; send a message; send an attachment | Timeline loads, send succeeds, second account receives | | |
| 3 | Open a DM by user (profile → Message) for a user with no cached DM channel | Verified `GET /users/{target}/dm` opens/merges the channel without duplicates | | |
| 4 | Open an existing group DM; load, send; verify name/icon/member count | Matches official client; participants correct | | |
| 5 | Open Saved Notes; send a note if the channel is exposed | Self-DM resolves; unavailable state stays recoverable | | |
| 6 | Type from the second account in a server channel, DM, and group DM | Indicator appears, coalesces one/two/many, excludes self, clears when stale and on channel switch/reconnect | | |
| 7 | Receive unread server and DM messages; open the channels | Unread/mention badges clear only after successful ack; official client agrees | | |
| 8 | Search loaded messages locally, then run selected-channel remote search for an unloaded message; open a result | Result opens via unified jump with highlight; remote authors resolve | | |
| 9 | Jump from reply, pin, search, and unread entry points in one session | All routes go through the unified coordinator; unloaded targets fetch around-message; failures degrade to channel | | |
| 10 | With history loaded, rapidly switch server channel → DM → group DM → Saved Notes while reactions and avatar/media loads arrive | Each route retains or prepares only its own groups, never shows the previous conversation, and does not restart completed history fetches for message mutations | | |
| 11 | In an existing group DM, use "Add Members" to add a friend not already in the group | Second account receives the group in their DM list (`ChannelCreate`); both accounts see the new participant (`ChannelGroupJoin`); a friends-only non-friend attempt fails with a safe error | | |
| 12 | As the group owner, right-click a non-self participant and choose "Remove from Group" | Confirmation appears; on confirm the participant disappears from both accounts' participant lists (`ChannelGroupLeave`) | | |
| 13 | From a non-owner account in the same group, check the participant context menu | No "Remove from Group" option is offered for other members | | |
| 14 | Copy Developer Verification diagnostics after this lane | DM trace, timeline presentation, realtime coalescing, and identity diagnostics stay redacted | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| Core chat / DMs | Steps 1-3 pass (list/load/send/attachments/participants live proof) |
| Core chat / group DMs | Step 4 passes (creation) and steps 11-13 pass (add/remove) |
| Core chat / saved messages | Step 5 passes with live availability |
| Core chat / typing indicators | Step 6 passes across server, DM, group |
| Core chat / read ack/unreads | Step 7 passes server + DM |
| Core chat / search | Step 8 passes (global search stays blocked) |
| Core chat / jump to message | Step 9 passes cross-context |

Group DM `partial` note: creation flow lands with Phase 55 item 3; add/remove lands with Phase 58; this lane proves existing-group, creation, and add/remove behavior together.
