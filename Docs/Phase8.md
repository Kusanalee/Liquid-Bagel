# Phase 8 Summary

## What Was Implemented

Phase 8 adds native macOS keyboard ergonomics, centralized command routing, a real local quick switcher, focus intent modeling, lightweight timeline selection, accessibility helper text, adaptive glass/density styling, and mock-only tests.

The app remains mock-safe. It still does not auto-connect to live Stoat or auto-validate saved credentials on launch.

## Command Routing Architecture

`StoatFeatures` now owns `AppCommand` and `AppCommandHandling`. `MainShellViewModel` implements command availability, disabled reasons, and command execution for shell navigation, runtime actions, focus, quick switcher, timeline actions, and settings routes.

`App/AppCommands.swift` routes macOS menu commands through the focused shell command handler instead of posting shortcut notifications.

## Keyboard Shortcuts

- Command+K opens the quick switcher.
- Command+L focuses the composer.
- Command+R refreshes the current runtime context.
- Command+Shift+R explicitly reconnects Live Manual when a scoped credential is available.
- Command+Shift+M toggles the member panel.
- Command+, opens Account & Connection settings.
- Command+1 through Command+9 selects visible servers.
- Option+Command+Up/Down moves between servers.
- Command+Up/Down moves between channels only when the composer or quick switcher is not focused.

## Quick Switcher Behavior

The placeholder quick switcher was replaced with a local command palette. It indexes the current in-memory snapshot only: servers, channels, DMs, Home, Discover, settings routes, and safe runtime commands such as Refresh, Reconnect, Disconnect, Reset to Mock, Focus Composer, and Toggle Member Panel.

Filtering is case-insensitive and local. It makes no live network calls, performs no remote search, and does not include token or session data.

## Focus Management Behavior

`ShellFocusTarget` models shell-level focus intent for the server rail, channel list, timeline, composer, quick switcher, and member panel. Opening the quick switcher focuses its search field; closing it restores the previous modeled focus where practical. Command+L requests composer focus through the existing AppKit-backed text input without clearing drafts.

The conservative navigation policy is implemented: channel/message keyboard navigation pauses while typing in the composer or quick switcher.

## Server And Channel Navigation Behavior

`ShellNavigationHelper` provides pure navigation over the active snapshot:

- select server by visible index
- select next/previous server
- select next/previous selectable channel
- select next/previous unread channel
- skip voice/unselectable channels
- no-op safely with status text when no target exists

Existing selection methods still perform unread clearing, message loading, and safe live selection persistence.

## Timeline Keyboard Behavior

`TimelineSelection` tracks the selected message for the active channel. The shell can move to next/previous messages, jump to newest, copy selected message content, and route edit/delete/reaction/retry commands through existing message action handlers where available.

Selection clears on channel changes and reconciles when messages disappear.

## Accessibility Improvements

Shared helper text now covers server labels, channel labels, message labels, composer disabled reasons, runtime labels, unread/mention state, selected state, and disabled/unavailable state. Message rows expose selected and pending/failed status. Runtime chip labels include mode, connection, and safe health text.

Decorative controls continue to use system images with labels or are hidden/disabled appropriately. New quick switcher rows expose labels, selected value, and activation hints.

## Reduce Transparency, Contrast, Motion, And Density

Glass surfaces now have stronger solid fallbacks for Reduce Transparency. High contrast strengthens glass strokes. Existing Reduce Motion handling remains in button animations. Message density continues to affect timeline spacing, with new testable density helper values. Reduce glass intensity is represented in style helpers and remains wired through Phase 6 preferences.

## Preferences Integration

Phase 8 continues using safe Phase 6 preferences:

- member panel visibility
- message density
- reduce glass intensity
- developer runtime controls
- last selected live server/channel IDs

No tokens are stored in preferences. Live selection persistence still only writes IDs that exist in the current live Ready snapshot.

## Live Navigation Ergonomics

Quick switcher and keyboard navigation work against live Ready snapshot data once the user explicitly connects. Disconnected, failed, empty-server, and no-channel states keep recoverable actions visible through command routing and existing runtime surfaces: Reconnect, Refresh, Reset to Mock, and Account & Connection settings.

No hidden live network behavior was added.

## Tests Added

Mock-only tests were added for:

- command routing and disabled no-op behavior
- quick switcher indexing, filtering, activation, and token-safe labels
- focus intent for quick switcher and composer
- server/channel/unread navigation
- navigation pause while typing
- timeline message selection, fallback, and content-only copy
- accessibility helper text
- density and adaptive material helpers

## Deferred

Still deferred:

- automatic live connect on launch
- automatic credential validation on launch
- uploads/media UI
- notifications
- persistent message cache/database
- full friends/DM/discover APIs
- voice
- server/channel settings
- full account editing
- full permission resolver
- global or remote search
- live tests requiring real credentials

## Known Risks And Limitations

- Timeline keyboard selection is lightweight and view-model based; it is not a full virtualized list focus system.
- Channel arrow shortcuts are intentionally conservative and pause while text entry owns focus.
- The quick switcher searches local snapshot data only.
- Live server/channel collections still depend on realtime Ready data.

## How To Run

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatDesignSystem
swift test --package-path Packages/StoatPersistence
Scripts/check.sh
```

Run the app from the `LiquidBagel` Xcode scheme. It opens in mock mode. Use Account & Connection settings or the runtime chip to validate/connect manually.

## Recommended Phase 9 Next Step

Phase 9 should deepen message and channel productivity: richer keyboard message actions, safer inline edit flows, better local unread/read ergonomics, and a clearer non-persistent message history model, still without hidden live network behavior.
