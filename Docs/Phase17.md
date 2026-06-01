# Phase 17: Message Actions, Reactions, and Timeline Ergonomics

Phase 17 adds a UI-facing message action runtime and timeline affordances for common message work: copying safe text, copying stable message IDs, replying, editing, deleting or discarding, retrying failed sends, pinning, and toggling reactions.

## Message Actions

`Phase17Runtime` derives `MessageActionItem` values from the selected `TimelineMessage`, current user, delivery state, and existing capability checks. The UI consumes those derived items for row hover/focus actions and context menus, so keyboard command gating and item-specific menus stay aligned.

Copy Text copies only message or system text when present. Copy Message ID is available only for confirmed, stable message IDs and remains behind developer controls. Pending local IDs are not copied.

Delete of confirmed messages still uses the existing confirmation dialog. Failed sends expose Retry, Edit & Retry, and local Discard without calling live delete APIs.

## Reactions

Reactions are grouped by emoji/key with a count and current-user selected state. Timeline chips are clickable toggles, and the quick reaction set is fixed to `👍`, `❤️`, `😂`, `👀`, and `✅`.

Live add/remove reaction behavior uses the existing `MessageActionHandling` and `StoatAPIClient` methods. No new Autumn routes were added.

## Privacy And Safety

Message actions and diagnostics avoid raw tokens, raw URLs, local paths, raw server payloads, and auth-like values. Message copy uses the injectable `MessageCopying` abstraction with AppKit and mock implementations; tests use mocks only.

Attachment behavior from Phase 16 is unchanged. Timeline attachment rows remain metadata-only until the user explicitly previews, saves, opens, or retries.

## Deferred

No persistent message cache, media cache, gallery, background prefetch, OCR, full search, notifications, voice, server/channel settings, or unverified live endpoints were added.

## Tests

Added focused Phase 17 tests for action availability, ownership/state gating, stable ID gating, delete confirmation state, mock copy redaction, reaction grouping/toggle direction, UI accessibility helpers, and attachment no-load regression.

Run results:

- `swift test --package-path Packages/StoatModels`: pass
- `swift test --package-path Packages/StoatAPI`: pass
- `swift test --package-path Packages/StoatRealtime`: pass
- `swift test --package-path Packages/StoatFeatures`: pass
- `swift test --package-path Packages/StoatUI`: pass
- `swift test --package-path Packages/StoatDesignSystem`: pass
- `swift test --package-path Packages/StoatPersistence`: pass
- `Scripts/check.sh`: pass
