# Phase 47 - Core Chat Polish

Phase 47 improves visible chat fidelity without adding new routes, persistent caches, or hidden background fetches. It focuses on markdown/custom-emoji coexistence, richer embed presentation, modeled embed-media loading through the existing bounded image-resource path, safer embed-only summaries for reply/pin/search surfaces, and conservative parity reporting.

## Implemented Behavior

- Markdown rendering now keeps the block parser for headings, quotes, lists, code blocks, and normal text while allowing inline current-context custom emoji in non-code blocks.
- Code blocks remain literal, so `:shortcode:` text inside fenced code is not rendered as custom emoji.
- `MessageEmbedDisplayItem` carries sanitized embed title/description/site/url metadata, safe accessibility text, and optional modeled media preview state.
- `MessageRow` accepts explicit embed display items and embed-media callbacks while preserving fallback rendering from `message.embeds` for existing callers.
- `EmbedTimelineCard` now audits website, text, image, video, none, and unknown variants with compact-density support, safe URL display/opening, accessibility labels, and modeled media controls.
- Modeled `embed.media` files use the existing bounded image-resource loader only from row visibility and explicit reload-visible-images paths.
- Arbitrary external `icon_url`, `image.url`, and `video.url` values remain display-only/link-only and are not auto-loaded.
- Reply previews, pinned-message rows, and search/jump summaries use safe embed title/description/site/host text for embed-only messages instead of always falling back to `1 embed`.
- Composer emoji sections include a slightly broader local Unicode set, dedupe entries, and continue searching local aliases and Ready custom emoji shortcodes.

## Safety Boundaries

- No global/server search route was added.
- No external embed media auto-fetching was added.
- No persistent message, markdown, thumbnail, or embed cache was added.
- No unverified emoji syntax, embed schema, or media route was introduced.
- Live-sensitive parity rows remain `partial` until live QA proves behavior against real chat data.

## Verification

- `swift test --package-path Packages/StoatUI`
- `swift test --package-path Packages/StoatFeatures --filter Phase47`

## Manual QA Checklist

- [ ] Send or inspect messages with markdown plus custom emoji shortcodes and confirm formatting is preserved outside fenced code blocks.
- [ ] Inspect website, text, image, video, none, and unknown embeds from real messages.
- [ ] Confirm modeled embed media can preview/save/open through explicit controls when a modeled file is present.
- [ ] Confirm external embed image/video URLs do not auto-load.
- [ ] Open reply previews, pinned messages, and search results for embed-only messages and confirm summaries are useful and redacted.
- [ ] Open the emoji picker, search local aliases and custom shortcodes, and confirm duplicates do not appear.
- [ ] Copy Developer Verification diagnostics and confirm no tokens, raw payloads, local paths, full IDs, or private URLs leak.
