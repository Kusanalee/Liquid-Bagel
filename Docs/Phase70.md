# Phase 70 - Custom Emoji Interoperability and Developer Diagnostics Hardening

Phase 70 follows the successful Phase 69 three-launch identity retest. The same QA pass corrected an earlier custom-emoji assumption and exposed a separate Developer Verification performance regression: Liquid Bagel rendered its own `:name:` content locally, but Stoat Web treated that text literally, while opening Developer Verification repeatedly validated the app signature from a SwiftUI computed getter.

## Source Verification and Root Causes

- Stoat for Web commit `45134ba647080fba774a3efcc98498197c96ea39` inserts custom emoji as `:<emoji ULID>:` and recognizes a colon-wrapped 26-character ULID in message content. The friendly emoji name is picker/search presentation, not the wire token.
- Liquid Bagel's picker instead inserted `:name:`. Its local Phase 68 index recognized that provisional token, masking the interoperability failure until the same message was viewed on web.
- Developer Verification placed eight actions in one compressible `HStack`, leaving labels such as `Copy Ti...` indistinguishable at the normal Settings width.
- The attached 145.6-second Activity Monitor trace recorded 53.88 seconds of CPU time and 10.39 GiB of reads. Main-thread samples repeatedly passed through `CredentialSetupView.developerDiagnosticsSection`, `notificationBuildSigningChecklist`, Security signature validation, SHA-256, and file reads because each SwiftUI evaluation recomputed the signature.

Official source:

- Picker insertion: <https://github.com/stoatchat/for-web/blob/45134ba647080fba774a3efcc98498197c96ea39/packages/client/components/ui/components/features/messaging/composition/picker/EmojiPicker.tsx#L279>
- Content token parser: <https://github.com/stoatchat/for-web/blob/45134ba647080fba774a3efcc98498197c96ea39/packages/client/components/markdown/emoji/util.ts#L8>

## Custom Emoji Fix

- Custom picker items now insert `:<emoji ID>:` while retaining their friendly name and legacy `:name:` shortcode as display/search metadata.
- Phase 68 scanning returns the exact matched token with its resolved emoji. Official ID tokens are globally unambiguous and may resolve from any known server, matching the official all-server picker. Historical name tokens remain readable but server-scoped to avoid duplicate-name ambiguity.
- Timeline preparation passes the exact token to StoatUI, so official web messages, optimistic local messages, confirmed echoes, edits, and image requests share one representation.
- Image work remains deduplicated by emoji ID. Unknown tokens and fenced Markdown code stay literal. Reaction routes, message JSON, cache budgets, and media loading bounds are unchanged.

## Developer Diagnostics Fix

- Copy actions use an adaptive grid with readable two-line labels, SF Symbols, full accessibility labels, and Help text. Member refresh is a separate maintenance action.
- Signature status begins as `not checked`, changes to `checking`, and publishes one cached categorical result.
- Developer Verification and Notification Settings request the check through one idempotent entry point. The Security work runs in a detached utility task; concurrent/repeat requests are counted as cache hits instead of revalidating.
- The signed-build override changes only the displayed result. Readiness getters and copied diagnostics never perform signature I/O and report only started/completed/cache-hit counts.

## Automated Proof

- Phase 34/68/70 feature coverage verifies official picker insertion, exact-token rendering, legacy compatibility, global ID/current-server-name precedence, fenced-code behavior, lazy/coalesced/cached signature checks, and distinct Developer action labels.
- StoatUI coverage verifies that custom picker items retain friendly display/search metadata while carrying an official ID insertion token.
- The focused Phase 35/65/68/69/70 lane passed 21 tests, StoatUI passed 41 tests, and StoatFeatures passed 403 tests with no failures.
- `git diff --check` and `Scripts/check.sh` passed on July 14, 2026, including the macOS app build.

## Focused Live Retest

1. Select and send current-server and other-known-server custom emoji alone and inside normal text. Confirm Liquid Bagel and Stoat Web render the same artwork.
2. Send an official custom emoji from web and confirm Liquid Bagel renders it. Confirm historical `:name:` messages remain readable locally and fenced code remains literal.
3. Resize Developer Verification to its minimum and default widths; every copy action must remain identifiable and operable by pointer and keyboard.
4. Capture Developer Verification for 30 settled seconds. CPU must settle below 10%, disk reads must stop growing, signature started/completed counts must remain `1/1`, and no recurring main-thread Security/SHA/file-read stack or related microhang may appear.

Custom emoji remains `partial` until this cross-client pass succeeds. Animated playback, custom reactions, and broader official-client comparison remain separate live-proof gaps.
