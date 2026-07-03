# Phase 58 - Mentions Parity, Group DM Members, Notification Signing, Native macOS Gate Prep

Phase 58 closes the largest remaining code-parity gap (user/channel/role mentions), completes the Phase 55 group DM feature loop (member add/remove), unblocks the notification permission prompt that has been dead since Phase 31, and prepares the QA Lane 7 native macOS gate with a code-level VoiceOver/high-contrast/keyboard-shortcut pass.

## Research

Before any code changed, `Docs/Research.md` gained a `## Phase 58 Notes` section verifying:

- The backend's `logos`-based content-token parser (`crates/core/parser/src/lib.rs`) recognizes `<@ULID>`, `<%ULID>`, `<#ULID>`, and `:ULID:` outside code spans; mentions are derived from `content` server-side (`DataMessageSend` has no `mentions` field), so no send-path model change was needed.
- `PUT/DELETE /channels/{target}/recipients/{member}`: add is gated by the `InviteOthers` channel permission (which `DEFAULT_PERMISSION_DIRECT_MESSAGE` grants to every group member by default) plus a friends-with-target check -- **not** owner-only. Remove is owner-only and explicitly rejects self-removal (`CannotRemoveYourself`); leaving a group is the pre-existing `DELETE /channels/{target}` route, not this one.
- The official macOS keybind table (`DEFAULT_MAC_SEQUENCES`) verifies exactly two new candidates: Escape (`CHAT_JUMP_END`) and Shift-Escape (`CHAT_MARK_SERVER_AS_READ`). It also surfaces a known, deliberately *not* remapped deviation: our existing Cmd-Option/Cmd-Control server/channel navigation modifiers are inverted relative to the official Cmd/Ctrl-Cmd mapping.

## Implemented Behavior

- **Mention rendering (Part A1/A2)**: `MarkdownInlineToken` (StoatUI) now recognizes `<@ULID>`/`<#ULID>`/`<%ULID>` alongside `:emoji:`, tokenizing outside fenced/inline code exactly like custom emoji. `Phase52TimelineAssetContext.inlineReferenceItems(for:identitySnapshots:currentUserID:)` resolves each token via the Phase 43 identity store (users) or direct snapshot reads (channels/roles) inside the existing detached, cancellable row builder -- render-time reads stay cache-only. Unresolved mentions render a safe `Unknown User`/`unknown-channel`/`unknown-role` fallback pill instead of disappearing (fixing a pre-existing bug where the angle-bracket sanitizer silently ate raw `<@ID>` text). User pills are tappable and open the profile popover (`ProfileOpenSource.mention`).
- **Self-mention accent (Part A3)**: `MessageRow` gains `mentionsCurrentUser`, computed from the message's server-parsed `mentions` field (`Phase52TimelineInteractionPreparer.mentionsCurrentUser`) -- a subtle accent background and leading bar highlight the whole row, reusing the existing search-highlight seam.
- **Send-path verification (Part A5)**: audited only, no code change -- `MessageDraft`/`MessageSendWireDraft` already omit `mentions` (matching the verified schema), the notification classifier already keys off server-parsed `message.mentions` (Phase18Runtime.swift), and optimistic pending messages correctly carry no local `mentions` until the confirmed echo replaces them.
- **Composer `@` autocomplete (Part A4)**: `ComposerTextView.Coordinator` detects the active `@query` immediately before the caret (bounded backward scan, cancels on whitespace, rejects word-character-preceded `@` to avoid triggering on emails). `Phase58MentionCandidateIndex` sorts candidates once and answers with prefix binary search, cached per `(channelID, snapshotRevision)` so a run of keystrokes never rebuilds from server members/DM participants/friends. Up/Down/Return/Tab/Escape are intercepted by the coordinator only while candidates are showing; selecting a candidate splices the verified `<@ULID> ` token into the draft and repositions the caret via a one-shot `ComposerCursorRequest`.
- **Group DM member add/remove (Part B)**: `addGroupRecipient`/`removeGroupRecipient` added to the API client protocol (live + mock). The group participants panel gets an "Add Members" header button (any member, friends-only candidates, optimistic append) and an owner-gated "Remove from Group" context-menu item with confirmation (self-removal is blocked client-side and routes nowhere near this API, matching the verified backend rejection).
- **Notification signing unblock (Part C)**: `CODE_SIGNING_ALLOWED`/`CODE_SIGNING_REQUIRED` flipped to `YES` in both build configs (ad-hoc, existing `DEVELOPMENT_TEAM`/entitlements unchanged). `NotificationSignatureChecker` replaces the manual-only "signed build" heuristic with a real `SecStaticCodeCreateWithPath`/`SecStaticCodeCheckValidity` check; the manual override toggle remains for edge cases.
- **Native macOS gate prep (Part D)**: fixed `MarkdownInlineContent`'s accessibility label to describe resolved text instead of raw mention tokens; labeled the autocomplete popover and its rows ("mention suggestions, N results", per-row name+subtitle, `.isSelected` trait on the highlighted row); added the two verified keyboard shortcuts (Escape/Shift-Escape) as new `AppCommand` cases wired into `AppCommands.swift` and the quick switcher; made mention-pill role coloring fall back to the system accent under Increase Contrast, matching the pre-existing author-name convention. This pass was code-review-driven, not a live VoiceOver/Accessibility Inspector session -- that remains QA Lane 7's job.

## Known Limitations

- Mention pills share the existing inline-emoji limitation of not wrapping mid-token across line breaks (an `HStack` of tokens, unchanged this phase).
- Channel and role mentions render but have no composer autocomplete (only `@user` autocomplete was in scope).
- The Cmd-Option/Cmd-Control server/channel navigation shortcut inversion found during keybind verification is a known, deferred deviation -- not remapped this phase.

## Automated Verification

```sh
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatAPI
git diff --check
Scripts/check.sh
```

- `StoatUI`: 23 tests passing, including 6 new Phase 58 tests (mention tokenizer extraction/code-literalness/fallback/sanitizer-bypass/channel-role recognition, composer inline-trigger detection and cancellation).
- `StoatFeatures`: 307 tests passing, including 16 new Phase 58 tests (mention pipeline resolution/fallback/self-mention flag, autocomplete index rebuild/capping/insertion, group add/remove optimistic/owner-gating/candidate-exclusion, signature-detection mapping, mark-channel/server-read command routing).
- `StoatAPI`: 38 tests passing, including 1 new Phase 58 test (recipient add/remove request shape).
- The Phase 54 parity-matrix drift test (`testPhase54ParityMatrixMatchesDocumentedSectionItemStatuses`) passes with the new `mentions` row and updated `group DMs`/`local notifications`/`keyboard shortcuts`/`accessibility`/`high contrast` rows.

## Live QA Still Required

1. Run `Docs/QA/1-FreezeGate.md` before all other lanes.
2. `Docs/QA/2-ChatPresentation.md` steps 14-18: mention render/self-accent/click-to-profile, composer autocomplete, fenced-code literalness, unresolved-mention fallback.
3. `Docs/QA/3-ConversationState.md` steps 11-13: group member add (any member, friends-only) and remove (owner-only, no self-remove option).
4. `Docs/QA/4-Notifications.md`: re-run in the now-signed-by-default build, including new step 3a (mention-classified notification).
5. `Docs/QA/7-NativeMacOSGate.md` steps 6-7, 10: live VoiceOver pass over mention pills/autocomplete popover, the two new shortcuts, and Increase Contrast on mention pills.

All Phase 58 rows stay `partial` until this evidence is recorded.
