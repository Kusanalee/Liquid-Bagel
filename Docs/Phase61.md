# Phase 61 - Clipboard Media Paste And Avatar Continuity

Phase 61 responds to the sixth live-QA report. Phase 60 is accepted as directionally green for now: rapid scrolling can still show temporary CPU peaks and mild lag, but the app returns to idle near 0%. Unicode reactions pass live QA. Custom emoji reactions remain outside this pass.

## Implemented Behavior

- Composer Command-V now keeps text paste normal, but clipboard image data and Finder/file-provider URLs queue validated composer attachment chips immediately.
- Pasted media still follows the existing attachment policy: selected conversation required, upload permission checked before send, five-file limit, 20 MB cap, allowed file types only, and uploads wait for Send.
- Drag/drop keeps the explicit review sheet. The Message menu Paste Attachment route remains available as the explicit attachment paste path.
- Local sends preserve the current user and selected-server member identity through pending and confirmed reconciliation, including avatar metadata.
- Locally sent rows with a nonce can use a lightweight local-send presentation while Phase 60 prepares the full row, avoiding a brief generic skeleton/avatar fallback after confirmation.

## P1 Remediation: Native Paste And Avatar Continuity

The seventh live-QA pass failed the two rows above. This remediation fixes only those two confirmed regressions; Phase 60 CPU/performance and notifications are untouched and explicitly deferred.

### Failed Live Proof

- Clipboard paste: a Finder/screenshot copy that also exposes a plain-text representation (e.g. a filename or the image's text alias) fell through the delegate's `doCommandBySelector:` check for `paste:`, which tested for a non-empty string *before* checking for a file URL or image payload. Text always won -- the attachment was silently dropped -- and because that check only intercepted the key-binding-interpreted paste path, a menu- or Services-invoked Command-V bypassed the delegate entirely and fell straight through to `NSTextView`'s own default text paste.
- Avatar continuity: the row view and its avatar consumer id were both keyed by `timelineMessage.message.id`, which changes at pending -> confirmed reconciliation (`pending-<nonce>` -> the real ULID). SwiftUI's `.id()` reset boundary on the row therefore tore down and rebuilt the entire row -- including the avatar image view -- forcing an `onDisappear`/`onAppear` pair that hid and re-requested the avatar resource under a new consumer id, producing the reported initials/skeleton flash even though the underlying identity data was already correct.

### Fix

- The composer now overrides `NSTextView.paste(_:)` directly on a dedicated `ComposerPasteInterceptingTextView` subclass instead of relying solely on the delegate's `doCommandBySelector:` hook, so every paste path (key equivalent, Edit menu, Services) runs the same classification: file URLs first, then PNG/TIFF image data, and only then falls through to normal text paste. When an attachment payload is present it wins outright -- the existing composer draft text is left untouched and no clipboard text is inserted, whether the draft was empty or not.
- `TimelineRenderItem` adds a `renderIdentity` derived from the message's nonce for the current user's own locally-sent messages, falling back to the real message id for everything else (including all incoming messages). The timeline `ForEach`, the row's `.id()` reset boundary, and the avatar visibility consumer id all use `renderIdentity` instead of the real id, so a locally sent row's view -- and its avatar -- survives pending -> confirmed -> realtime-echo reconciliation without being torn down. The real `MessageID` is unchanged and still drives preparation targeting, actions, acknowledgements, and navigation.
- Visibility/skeleton tracking moves from the old id to the new confirmed id directly inside row-state synchronization, never through `imageResourceBecameHidden`/`imageResourceBecameVisible`, so the avatar resource is never hidden or re-requested as part of reconciliation.
- The reducer backfills nonce/user/member onto the confirmed message when the send response omits them, and again on any later snapshot merge or realtime echo of that same locally-sent message, so identity/avatar do not blank out after the fact.

### P1 Follow-up: SwiftUI Provider Route And Grouping Reconciliation

- The second live retest confirmed that the built app still bypassed the `NSTextView` interception path for ordinary Command-V. The composer now owns a SwiftUI `onPasteCommand` route at the actual input surface for `UTType.image` and `UTType.fileURL` providers. It loads the provider's advertised representation, accepts direct file URLs first, normalizes image data to PNG, and then queues the existing validated attachment chips.
- The original AppKit `paste(_:)` / `readSelection(from:type:)` interception remains only as a guarded fallback for non-SwiftUI delivery. A short-lived general-pasteboard change-count handoff suppresses duplicate native delivery while preserving an intentional later repeat paste of the same clipboard contents.
- Attachment diagnostics now record only categorical paste source/media-category/outcome/provider-count/item-count fields (`SwiftUI` or `AppKit`; file, image, mixed, or unknown; queued, rejected, unsupported, load failed, duplicate suppressed). They never include clipboard content, filenames, paths, or type identifiers; load, validation, and unsupported failures show safe composer copy instead of failing silently.
- Optimistic messages do not yet have a server-issued ULID timestamp. Treating them as distant-future rows made a pending local message start its own group, then join the preceding local-message group on confirmation, which visibly removed its avatar. Timeline grouping now gives pending rows a current-pass timestamp and permits the same safe grouping rule as confirmed rows; the row also keeps its last decoded avatar bytes for its nonce-stable `renderIdentity` while the confirmed presentation is prepared.
- This is implementation and regression-test proof only. Clipboard paste upload and local-send avatar continuity remain `partial` until the same live retest passes.

### Corrected Acceptance Criteria

- `clipboard paste upload` (Docs/ParityMatrix.md) and the chat-parity avatar-continuity row stay `partial` until a live retest passes; this fix is not itself proof and does not promote either row.
- Required retest, clipboard paste: Command-V with an empty draft and with a non-empty draft, pasting both a screenshot (image data) and a Finder file (file URL) where the clipboard also exposes a text representation -- a chip must appear immediately, the draft text must stay intact, and upload must wait for Send.
- Required retest, avatar continuity: repeated sends in a warmed channel must show continuous avatar art through pending, confirmation, and realtime echo -- no initials or skeleton flash -- including at least one send while the row stays scrolled into view.

## QA Status

- Phase 60 performance: record as acceptable unless a fresh sample or Phase 60 counters show repeating viewport flushes, unbounded row queues, stale row churn, image/decode loops, or avoidable main-thread row preparation.
- Reactions: Unicode add/remove/reload is green from live QA; custom emoji reactions are still not claimed.
- Clipboard paste: the Phase 61 live retest passed for screenshot/Finder payloads with empty and non-empty drafts; chips appear immediately, draft text remains intact, and upload waits for Send.
- Avatar continuity: chat rows passed through pending, confirmation, and realtime echo. A separate flash remains in the upper-left current-user rail avatar and moves to Phase 62.
- Scrolling: a rapid-scroll peak reached roughly 112%, then settled to 0-10% within two seconds. This is acceptable for Phase 61, with native-feeling scroll smoothness still available for later optimization.
- Notifications: explicitly deferred in this pass. QA Lane 4 lives in Settings -> Notifications. Signature/build readiness is also summarized in Developer diagnostics as Notification build.

## Verification

Run before completion:

```sh
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatFeatures
git diff --check
Scripts/check.sh
```
