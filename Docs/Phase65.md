# Phase 65 - Timeline Stability, Resize Performance, And Custom Emoji

Phase 65 responds to the Phase 64 live pass. Immediate channel loading, composer isolation, scroll intents, attachment plus Character Viewer input, and long/short biography disclosure passed. Three concrete gaps remained: live resize and rapid scrolling were laggy, hover actions shifted message geometry, and the emoji picker showed custom shortcodes instead of artwork.

## Timeline And Resize Stability

- `ChatPlaceholderView` now gives `MessageTimelineView` the flexible region directly. Toolbar and selected-channel composer are top/bottom `safeAreaInset` content, so live resizing no longer makes three `VStack` siblings renegotiate the timeline height.
- The timeline keeps default layout priority. The Phase 64 guard remains explicit: an ideal-height proposal on the `ScrollView` would measure the full loaded `LazyVStack` and reintroduce the channel-load freeze.
- Phase 60 flattened rows, Phase 61 render identity, Phase 63 boxed/equatable rows, visible-first preparation, and the shared 750 ms media visibility-lease worker remain unchanged.

## Stable Message Hover Actions

- Message action controls moved from the content `HStack` to a top-trailing overlay.
- Rows reserve the action bar's trailing width whenever actions exist, independent of hover, focus, or selection. Revealing controls no longer changes message width, wrapping, height, or timeline position.
- Hidden controls do not accept pointer or accessibility interaction. Full-row hit testing and existing context menus remain intact.

## Custom Emoji Picker Artwork

- `EmojiPickerItem` carries stable identity, insertion text, display/search metadata, an optional custom-media key, and optional presentation bytes.
- The cached emoji catalog contains metadata only. Presentation reads hydrate already-loaded artwork separately, so an image completion updates visible picker cells without sorting or rebuilding the catalog.
- Custom artwork requests start only when a lazy grid cell appears and use the existing bounded `.customEmoji` image queue. Loading/failure retains a readable shortcode fallback; loaded artwork renders in a fixed 28-point cell.
- Current-server emoji win duplicate-shortcode resolution over other known servers. Selection still inserts the existing verified `:shortcode:` representation; no route or message payload changed.

## Automated Proof

- StoatUI tests cover fixed hover-action reservation plus custom-item artwork/fallback metadata.
- StoatFeatures tests cover current-server duplicate precedence and prove no custom image request occurs until the picker cell explicitly requests it; the loaded bytes then hydrate the cached catalog without a duplicate fetch.
- Existing Phase 63 composer isolation, 250-message no-rebuild, render equality, visibility lease, biography, Markdown/custom emoji, and scroll-target suites remain the regression gate.

## Live QA Required

1. Load the capped 250-message channel; confirm immediate first paint and CPU below 10% within two seconds.
2. Resize continuously for ten seconds; confirm responsive interaction, no full-history `measureEstimates` loop, and CPU below 10% within two seconds after release.
3. Hover wrapped, attachment, reaction, and compact rows; confirm no movement or rewrapping and verify action buttons/full-row context menus.
4. Rapid-scroll for ten seconds with the pointer over and outside the timeline; confirm no row jumps and the same two-second settling gate.
5. Open/search the emoji picker; confirm custom artwork loads progressively, failure remains readable, selection inserts the shortcode, and the sent message renders it.
6. Reconfirm jump-to-newest, load-older position preservation, unread scrolling, and long/short biography disclosure after the chat-layout restructure.

Large-channel performance, emoji picker, and custom emoji remain `partial` until this live retest passes. Animated custom emoji playback and unverified cross-server usage remain outside Phase 65.

## Live QA Result (2026-07-14)

- **Scrolling failed:** the app froze again while scrolling the capped timeline, so the remaining Phase 65 QA is paused.
- The supplied 1.616-second sample did not reproduce the Phase 64 full-history measurement loop. Instead, 632 of 718 platform-view update samples were inside SwiftUI's macOS `AppKitPopUpAdaptor`, rebuilding message action `Menu` content and accessibility labels.
- Phase 65 preserved row geometry by keeping the action-bar overlay mounted at zero opacity for inactive rows. That also materialized an AppKit-backed menu for every realized row, turning rapid lazy-row creation into main-thread menu work.
- Phase 66 keeps the fixed trailing reservation but mounts the action bar and menu only for the active hovered, focused, or selected row. Large-channel performance remains `partial` pending the Phase 66 live gate.
