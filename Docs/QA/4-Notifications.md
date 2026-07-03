# QA Lane 4 - Notifications

Covers signed authorization and delivery, click routing, mutes, and active-channel suppression.

## Prerequisites

- A signed build: Phase 58 flips `CODE_SIGNING_ALLOWED`/`CODE_SIGNING_REQUIRED` to `YES` in project.pbxproj, so a normal Xcode build now produces an ad-hoc signed app using the existing `DEVELOPMENT_TEAM`/entitlements already configured — no extra archive step should be required. Confirm via Developer Verification diagnostics that "Signature" reads `signed and valid` before running this lane.
- Second account able to send server messages, mentions, and DMs.

## Evidence Rules

Categorical outcomes only. Notification diagnostics record status transitions, not content.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | In the signed build, request notification permission from Settings → Notifications | System prompt appears; before/after diagnostics show `notDetermined` → granted/denied; app appears in System Settings → Notifications | | |
| 2 | Run the authorized self-test notification | Banner delivers | | |
| 3 | Receive a server message, a mention, and a DM while the app is backgrounded/in another channel | Notifications deliver; privacy mode redacts content when enabled | | |
| 3a | From a second account, send a message containing a composer-inserted `<@ULID>` mention of this account | The mention is classified and delivered as a mention notification (not a plain message notification) | | |
| 4 | Click a server-message notification | Routes to channel and jumps to the target message when its ID is present | | |
| 5 | Click a DM notification | Routes to the DM conversation | | |
| 6 | Click a notification whose target message is unavailable/deleted (if testable) | Degrades to channel-level route without error | | |
| 7 | Click a notification while disconnected, then reconnect | Route queues and replays once after Ready | | |
| 8 | Mute a channel and a DM locally; trigger messages in each | Delivery suppressed; suppression counters increment | | |
| 9 | With the target conversation active/focused, receive a message in it | Active-channel suppression prevents the banner (server, DM, and group paths) | | |
| 10 | Set Busy, then Focus, and receive non-mention and mention messages | Busy suppresses all; Focus suppresses non-mentions only | | |
| 11 | Copy Developer Verification diagnostics after this lane | Build-readiness bundle and counters look sane; no leaks | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| Notifications / local notifications | Steps 1-3 pass in a signed build |
| Notifications / route on click | Steps 4-7 pass including one degraded case |
| Notifications / mutes | Step 8 passes (server-wide cloud mute stays blocked without a verified route) |
| Notifications / active-channel suppression | Steps 9-10 pass with live presence |

If step 1 fails, capture the diagnostics checklist fields (bundle/signing/delegate) before filing a fix; the row stays `partial` with that concrete gap.
