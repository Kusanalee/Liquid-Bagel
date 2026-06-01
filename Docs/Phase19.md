# Phase 19: App Lifecycle, Notification Reliability, and Safe Resume UX

Phase 19 hardens notification and lifecycle behavior without changing Liquid Bagel's mock-safe launch model.

## Lifecycle Model

`AppLifecyclePhase` tracks whether the app is active, inactive, or backgrounded. SwiftUI scene phase changes and AppKit activation callbacks feed the shell view model through a small shared lifecycle bridge.

Lifecycle transitions reconcile dock badge state, notification diagnostics, stale in-app banners, and queued notification routes. They do not start Live Manual realtime, validate credentials, register for push notifications, or create background sync.

## Notification Policy

Foreground active behavior is in-app only. The selected channel suppresses notifications only while the app is active and the selected channel is considered visible. When the app is inactive or backgrounded, a selected channel is not treated as visible for active-channel suppression.

Native notifications remain opt-in and permission-gated. Permission prompts are still explicit from notification settings; app activation and settings refresh only read current system authorization status.

In-app banners remain memory-only, capped, and pruned during lifecycle reconciliation. Mock mode still posts no notifications except the explicit demo action.

## Route Queue And Manual Resume

Notification clicks still enter through `AppDelegate` and `NotificationRouteCenter`. If the shell handler is not ready, the route center keeps an in-memory queue of safe route IDs and drains it when the shell installs a handler.

If a notification click targets an unloaded message while Live Manual is not connected and ready, Liquid Bagel queues only the safe route IDs and shows “Connect manually to open this message.” It does not reconnect, validate credentials, fetch messages, or keep a hidden socket alive. Queued routes expire after 10 minutes.

After the user manually reconnects and realtime reaches ready state, non-expired queued routes replay as direct responses to the original click. Expired routes are dropped.

## Diagnostics And Settings

Notification diagnostics now include lifecycle phase, active-channel visibility, queued route count, expired route count, last route outcome, dock badge value, delivery counts, and suppression details. Diagnostic copy is redacted and contains no tokens, raw notification payloads, raw server responses, or local file paths.

Notification settings explain that active app delivery is in-app only, native delivery is for inactive/background use, and notification clicks require manual reconnect if Live Manual is disconnected.

## Tests

Phase 19 adds mock-only coverage for:

- lifecycle-driven active-channel suppression
- queued notification clicks before shell handler readiness
- disconnected notification clicks queuing without connecting
- dock badge reconciliation on lifecycle changes
- redacted lifecycle notification diagnostics

Acceptance remains `Scripts/check.sh`.
