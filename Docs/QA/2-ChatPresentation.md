# QA Lane 2 - Chat Presentation

Covers replies, pins, reactions, emoji picker, custom emoji, Markdown, embeds, and mentions. Run after the freeze gate passes.

## Prerequisites

- Two real accounts, one safe owned test server, official client open beside Liquid Bagel for every comparison.
- At least one channel with website/image/video/unknown embeds available or creatable.

## Evidence Rules

Categorical outcomes only. No payload bodies, private URLs, full IDs, or message content beyond safe snippets.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | Send messages with headings, lists, quotes, inline styles, links, and fenced code blocks; compare both clients | Rendering matches official client closely; code blocks stay literal | | |
| 2 | Send current-server custom emoji `:shortcode:` inside normal text and inside fenced code | Renders inline emoji in text; stays literal in code; matches official client | | |
| 3 | Inspect website, text, image, video, none, and unknown embeds | Cards sanitize title/site/description/url; official-client layout is comparable | | |
| 4 | Confirm external embed image/video URLs do not autoload | Media loads only through explicit bounded controls | | |
| 5 | Reply to a loaded message; open the reply preview and jump | Preview shows resolved identity; jump scrolls/highlights target | | |
| 6 | Reply to an unloaded (old) message and jump | Around-message fetch loads target; jump works | | |
| 7 | Inspect a deleted/inaccessible reply target if safely possible | Safe fallback text; no crash, no raw IDs | | |
| 8 | Reply to an embed-only message | Summary uses embed title/description/site/host, not `1 embed` | | |
| 9 | Pin a message, open the pinned sheet, jump to it, unpin it | Pin/unpin dedupe correctly; sheet refreshes; jump highlights | | |
| 10 | Pin or search an embed-only message | Summary useful; no private URL/raw ID leak | | |
| 11 | React with common Unicode emoji from both accounts; remove reactions | Counts/render match official client | | |
| 12 | React with current-server custom emoji | Name/image resolve through bounded media loading | | |
| 13 | Open composer emoji picker; search Unicode aliases and custom shortcodes; compare grouping and autocomplete with official client | Groups Common/Unicode/Current Server/Other Servers; insertion syntax matches live behavior | | |
| 14 | From the official client, send a message that mentions this account (`<@ULID>`); observe it in Liquid Bagel | Pill renders the resolved display name, role-colored in server context; the whole row is accented as a self-mention; clicking the pill opens the profile | | |
| 15 | Type `@` in the composer and a few letters of a real member's name | Keyboard-navigable popover appears with matching candidates; Up/Down/Return/Tab/Escape work as expected | | |
| 16 | Select a candidate from the popover | Composer text now contains the verified `<@ULID>` token; official client renders it as a real mention when the message is sent | | |
| 17 | Send a mention inside a fenced code block | Token stays literal text, not a pill, in both clients | | |
| 18 | Mention a user ID that cannot be resolved locally (if safely testable) | Safe `Unknown User` fallback pill renders; no raw ID leak, no crash | | |
| 19 | Copy Developer Verification diagnostics after this lane | No redaction leaks | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| Core chat / replies | Steps 5-8 pass including at least one deleted/unloaded variant |
| Core chat / pins | Steps 9-10 pass |
| Core chat / reactions | Steps 11-12 pass |
| Core chat / emoji picker | Step 13 passes official-client comparison |
| Core chat / custom emoji | Steps 2, 12 pass with live syntax/media proof |
| Core chat / markdown | Steps 1-2 pass real-message comparison |
| Core chat / embeds | Steps 3-4 pass with live payload variety |
| Core chat / mentions | Steps 14-18 pass, including the fenced-code and unresolved-mention cases |

Rows stay `partial` if a live-sensitive step is blocked; note the blocker as the row's concrete noncritical gap.
