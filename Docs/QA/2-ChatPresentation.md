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
| 20 | Put the caret in the middle of a draft and insert Unicode and custom emoji from the picker | Each emoji lands at the caret, the caret lands immediately after it, and the composer regains focus | | |
| 21 | Type `#`, `%`, and `:sh` in a server-channel draft; navigate and select results with Up/Down/Return/Tab/Escape | Visible text channels, rank-ordered roles, and custom emoji share one responsive popover and insert exact `<#ULID> `, `<%ULID> `, and `:ULID:` tokens | | |
| 22 | Compare picker and `:` typeahead insertion for the same custom emoji | Draft/wire token is byte-identical and has no trailing space | | |
| 23 | Try `# Heading`, `#1`, `#ffffff`, `https://`, `12:30`, `50%`, `a@b.com`, and sigils inside inline code | No autocomplete appears; valid mid-sentence `@`, `#`, `%`, and two-character `:` queries still appear | | |
| 24 | Send a message with a mention mid-sentence, then narrow the window until the mention reaches the right edge | The mention wraps to the next line **whole** (never split across two tinted fragments), the text around it wraps normally, and the mention stays clickable and role-colored | | |
| 25 | Select across a message containing a mention and a custom emoji, then copy | Selection crosses the whole body in one drag; the pasteboard contains the mention display name and the emoji shortcode | | |
| 26 | Open the autocomplete popover with 10 candidates and hold Down past the visible rows | All rows render at full height (never sliced); the list scrolls and the highlighted row stays in view | | |
| 27 | Send messages with `# h1` through `###### h6`, a nested list, a multi-line `>` quote, `---`, and a fenced block with a language | Six visibly distinct heading sizes; nesting is indented; the quote is one continuous bar; a rule renders; the fence shows its language label | | |
| 28 | Send `5 < 10 > 3` | Renders intact; no characters are eaten by the HTML sanitizer | | |
| 29 | Inspect an embed with a wide image, one with `ImageSize.preview`, and one still loading | Wide media keeps its aspect ratio; preview-sized media renders as a side thumbnail; the loading placeholder is the same size as the final image so the row does not reflow | | |
| 30 | Right-click an embed card with media | Preview/Save As/Open/Retry appear in the context menu; no button bar is drawn inside the card | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| Core chat / replies | Steps 5-8 pass including at least one deleted/unloaded variant |
| Core chat / pins | Steps 9-10 pass |
| Core chat / reactions | Steps 11-12 pass |
| Core chat / emoji picker | Steps 13, 20, and 22 pass official-client and caret comparison |
| Core chat / custom emoji | Steps 2, 12, 21, 22, and 24-25 pass with live syntax/media proof |
| Core chat / markdown | Steps 1-2 and 27-28 pass real-message comparison |
| Core chat / embeds | Steps 3-4 and 29-30 pass with live payload variety |
| Core chat / mentions | Steps 14-18, 21, and 23-25 pass, including all composer kinds, fenced-code, negative cases, unresolved mentions, and wrapping |

Phase 72 note: the mention background is a rectangular run, not a capsule, and per-pill VoiceOver
labels are expanded inline into the message body label instead. Both are deliberate; see
`Docs/Phase72.md`. Step 26 covers the autocomplete popover clipping fixed in the same phase.

Rows stay `partial` if a live-sensitive step is blocked; note the blocker as the row's concrete noncritical gap.
