# QA Lane 4 - Notifications

Covers signed authorization and delivery, click routing, mutes, and active-channel suppression.

## Prerequisites

- A signed build: the checked Xcode settings have `CODE_SIGNING_ALLOWED = NO`, so produce a locally signed archive/build first — the permission prompt will not appear otherwise (Phase 31/36 finding).
- Second account able to send server messages, mentions, and DMs.

## Evidence Rules

Categorical outcomes only. Notification diagnostics record status transitions, not content.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | In the signed build, request notification permission from Settings → Notifications | System prompt appears; before/after diagnostics show `notDetermined` → granted/denied; app appears in System Settings → Notifications | | |
| 2 | Run the authorized self-test notification | Banner delivers | | |
| 3 | Receive a server message, a mention, and a DM while the app is backgrounded/in another channel | Notifications deliver; privacy mode redacts content when enabled | | |
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
