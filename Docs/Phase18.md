# Phase 18: Native Notifications, Dock Badge, and Notification Preferences MVP

Phase 18 adds a narrow, mock-safe notification workflow for already-running Live Manual realtime sessions.

## Notification Runtime

`Phase18Runtime` defines the local notification model, permission status, notification routes, classifier decisions, content sanitization, dock badge counts, redacted diagnostics, and native/mock service abstractions.

Native notification delivery uses `UserNotificationsNotificationService`, while tests and previews can use `MockNotificationService`. Dock badge writes go through `DockBadgeManaging`, with an AppKit implementation and mock recorder.

## Preferences

`AppPreferences` now includes `NotificationPreferences`.

Defaults are conservative:

- native notifications off
- in-app banners on
- private notification content
- current-channel suppression on
- mentions and direct messages only
- dock badge counts unread channels plus mentions
- local per-channel overrides only

Per-channel mute/suppress preferences are stored locally in preferences. No server settings, push registration, or background sync were added.

## Delivery Behavior

Notifications are classified only from new messages that appear in the Live Manual realtime snapshot after the live connection baseline is established. Mock runtime does not emit notification events unless the user presses the explicit demo action in notification settings.

The classifier suppresses:

- current user's own messages
- muted channels
- messages with `suppressNotifications`
- the active visible channel, unless the user disables that preference
- non-mention/non-DM messages unless all-message delivery is explicitly selected

Notification text is sanitized and truncated. Raw URLs, local paths, token-like fields, markdown/html markup, raw attachment URLs, and raw payloads are not displayed. Attachments are summarized by count.

## Routing And Badge

Native notification clicks route through `NotificationRouteCenter` to the active shell view model. Loaded messages are selected and scrolled into view. Unloaded targets can be loaded around only as a direct response to the click and only when Live Manual message loading is available.

Dock badge counts exclude muted channels. The unread count is channel-based because current unread state does not provide exact message totals.

## Tests

Added focused tests for:

- conservative default preferences
- older preference payload decoding
- per-channel override validation
- mention/DM classification
- self-message, active-channel, muted-channel, and suppress flag filtering
- privacy/sanitization/attachment summaries
- badge count modes
- notification route handling
- explicit mock notification delivery

Run results:

- `swift test --package-path Packages/StoatPersistence`: pass
- `swift test --package-path Packages/StoatFeatures`: pass

Full `Scripts/check.sh` should remain the Phase 18 acceptance check.
