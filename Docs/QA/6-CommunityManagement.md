# QA Lane 6 - Community Management

Covers slowmode, category/channel ordering, and server emoji management. Run entirely in one safe owned test server.

## Prerequisites

- One safe owned test server where destructive-adjacent actions are acceptable.
- A second account without `ManageCustomisation` for the permission checks.
- A small valid emoji image file plus an invalid file (wrong type/oversized).

## Evidence Rules

Categorical outcomes only; no file paths or full IDs in evidence notes.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | Edit a test channel through slowmode off → several durations → off; reconnect after each save | `0`-means-off persists; official client shows the same values | | |
| 2 | As the second account, send at the slowmode interval | Enforcement matches official client | | |
| 3 | Open Server Settings → Categories; reorder categories up/down; Apply; reconnect | Order persists; official client agrees | | |
| 4 | Reorder channels within a category and move a channel across categories via the Picker; Apply; reconnect | `moveChannels` persists; sidebar and official client agree | | |
| 5 | Refresh server emoji in settings | List matches official client | | |
| 6 | Create an emoji from a valid file | Appears in settings, composer picker, reactions, and rendered messages; survives reconnect | | |
| 7 | Try invalid name, invalid file, and a simulated upload/route failure | Validated rejection; no partial state | | |
| 8 | As the second account (no `ManageCustomisation`), attempt emoji create/delete | Fails closed | | |
| 9 | Delete the test emoji through the confirmation flow; reconnect | Removed everywhere after reconnect | | |
| 10 | Sample the app during steps 5-9 | No synchronous file reads, image decoding, or emoji-list rebuilds in SwiftUI render stacks | | |
| 11 | Create a test channel and delete it; create an invite, list, and revoke it | Management flows match official client | | |
| 12 | Copy Developer Verification diagnostics after this lane | No leaks | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| Server/community / channel create/edit/delete | Steps 1-2, 11 pass with live slowmode persistence |
| Server/community / categories | Steps 3-4 pass with live reorder persistence |
| Server/community / server emoji management | Steps 5-10 pass including permission and failure paths |
| Server/community / invite create/list/revoke | Step 11 invite portion passes |
