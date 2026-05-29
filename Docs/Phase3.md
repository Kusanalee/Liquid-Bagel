# Phase 3 Summary

## What Was Implemented

Phase 3 replaces the Phase 0/1 placeholder shell with a native SwiftUI macOS chat-client foundation. The app now opens into a mock-safe Liquid Bagel shell with a server rail, channel sidebar, chat timeline placeholder, composer placeholder, member panel, Home/Friends/Discover placeholders, command hooks, previews, accessibility labels, and pure tests for selection and message grouping.

The phase remains offline by default. It does not log in, auto-connect to Stoat realtime, send messages, upload files, persist state, or deliver notifications.

## Main Shell Architecture

The app target stays thin. `LiquidBagelRootView` creates a `MainShellViewModel` in mock runtime mode and presents `MainShellView`.

`StoatFeatures` owns the shell-specific state and views:

- `ShellSpace`, `ShellRoute`, and `ShellSelection` model in-memory navigation.
- `MainShellViewModel` owns selection, `RealtimeSnapshot`, connection state, diagnostics, placeholder command state, and routing helpers.
- `MainShellView` lays out the fixed native shell with a 72 px server rail, 260 px channel sidebar, flexible chat area, and 240 px hideable member panel.

## Design System Overview

`StoatDesignSystem` now contains reusable Liquid Glass foundation tokens:

- spacing, sizing, corner radius, typography, elevation, and animation constants
- material hierarchy wrappers for rail/sidebar/panel/composer/toolbar/popover surfaces
- badge formatting helpers
- initials generation
- accessibility label helpers
- reduce-transparency fallback for glass backgrounds

Official future Liquid Glass APIs can be added behind availability wrappers later. Phase 3 uses SwiftUI materials such as `.regularMaterial`, `.thinMaterial`, and `.bar`.

## Components Added

`StoatUI` now provides reusable components for shell construction:

- glass containers, toolbar, icon buttons, search field, and composer
- avatar and server icon placeholders
- unread and mention badges
- presence dots
- empty/loading/error states
- message row/group rendering with attachments, embeds, reactions, edited marker, and timestamps
- channel, server rail, and member rows

These components are mock-safe and avoid live image loading or network behavior.

## Selection And Navigation Behavior

The default selection is Home. Selecting a server updates the shell space and auto-selects the first visible text-style channel. Selecting a channel updates the selected server/channel route. Selecting Home or Discover clears server/channel selection. The member panel visibility is stored in memory only.

Command hooks are stubbed safely:

- Command+K opens the quick switcher placeholder.
- Command+L toggles composer focus intent.
- Command+R shows a refresh/reconnect placeholder.
- Command+Shift+M toggles the member panel.
- Command+1 through Command+9 select mock servers by index.
- Command+comma shows a settings placeholder message.

## Mock Data Strategy

`MockShellData` builds a `RealtimeSnapshot` fixture with users, servers, channels, members, unread state, typing state, and channel messages. The fixture is the single obvious source for Phase 3 shell previews and tests.

The snapshot shape matches the Phase 2 realtime store, so later phases can swap in a `RealtimeStateStore` snapshot stream without changing the shell layout.

## Accessibility Considerations

Phase 3 includes accessibility labels for server icons, badges, composer, unread separators, and combined message/member rows. Selection is exposed in labels where practical. Unread and mention states are not color-only because they also use labels and badges. Glass surfaces honor Reduce Transparency by falling back to a solid system background.

Deeper keyboard traversal and assistive-technology QA are intentionally deferred to Phase 8.

## Tests Added

`StoatFeaturesTests` covers:

- default selection
- server and channel selection
- Home/Discover clearing behavior
- member panel toggling
- invalid selection fallback
- Command+1...9 selection helper behavior
- message grouping for same/different author, same/different channel, time threshold, system messages, replies, edited messages, and empty input

`StoatUI` and `StoatDesignSystem` tests cover initials, badge formatting, accessibility helper output, and stable token dimensions.

## How To Run

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
Scripts/check.sh
```

Run the app from the `LiquidBagel` Xcode scheme. It starts in mock shell mode and does not open a live WebSocket.

## Intentionally Deferred

- login/session UI
- live realtime auto-connect
- real message sending/editing/deleting/reactions
- file uploads
- notifications
- disk persistence/cache
- media viewer
- full search
- real friends/DM/discover workflows
- server/channel settings
- voice features

## Recommended Phase 4 Next Step

Phase 4 should wire the shell to a controlled realtime snapshot source behind explicit runtime/session state, then add the first non-sending message MVP surfaces such as pagination/loading states, richer empty states, and permission-aware composer readiness.
