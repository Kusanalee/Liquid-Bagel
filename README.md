# Liquid Bagel

Liquid Bagel is an unofficial, native macOS SwiftUI client for [Stoat](https://stoat.chat), built directly against Stoat's REST and realtime (WebSocket) APIs — no Electron, no webview.

It covers the core of day-to-day chat: servers and channels, direct messages and group DMs, friends and relationships, roles and permissions, moderation tooling, member management, custom emoji, attachments and inline media, reactions and replies, native notifications, and account/profile editing. See [Features](#features) for the full list and [Current Limitations](#current-limitations) for what's intentionally left out of v1.0.

The app talks to your real Stoat account over live credentials only — there is no bundled demo/mock mode in the shipping build.

## Requirements

- macOS 15 or newer to run the app
- Xcode 26.5 or newer and the Swift 6 toolchain to build it

## Build

```bash
xcodebuild -project LiquidBagel.xcodeproj -scheme LiquidBagel -destination 'platform=macOS' build
```

## Test

```bash
Scripts/check.sh
```

The check script runs every local Swift package's test suite, fails the build if a `Mock`/`Stub`/`Fake` type has leaked into a library source (test doubles are only allowed in test targets), and then builds the macOS app target.

## Getting Started

1. Build and run the app (or open `LiquidBagel.xcodeproj` in Xcode and run the `LiquidBagel` scheme).
2. On first launch, sign in with your Stoat account credentials in the native login window.
3. Your session token is stored in the macOS Keychain, scoped to this app; it's never logged or sent to diagnostics. On the next launch the app re-validates it and connects automatically.

## Features

- **Servers & channels**: browse, create, and manage servers, channels, and categories.
- **Messaging**: send/edit/delete messages, replies, reactions, mentions, and rich markdown rendering.
- **Direct messages**: 1:1 and group DMs with conversation parity to the official client.
- **Friends & relationships**: friend requests, blocking, and profile popovers.
- **Members & roles**: member lists with live role colors, role assignment, and permission-guarded moderation actions.
- **Moderation**: kicks, bans, slowmode, and server/channel administration.
- **Media**: attachment upload, clipboard paste/drag-and-drop, inline image previews, avatars, server icons and banners, and custom emoji (including cross-server emoji).
- **Notifications**: native macOS notifications, dock badges, and per-server/channel notification preferences.
- **Account & identity**: profile and account editing, session/account management, and status.
- **Native macOS**: a SwiftUI app that follows system appearance, window, and interaction conventions rather than reskinning a web client.

## Structure

- `App/`: macOS SwiftUI app shell (window, commands, app lifecycle).
- `Packages/StoatModels`: core Stoat value models, ID wrappers, config decoding, and permission bitmasks.
- `Packages/StoatAPI`: REST API environment, auth credentials, Keychain-backed token storage, request/response handling, upload scaffolding, and the live API client.
- `Packages/StoatRealtime`: realtime WebSocket client, event decoding, diagnostics, and state store.
- `Packages/StoatPersistence`: app preferences, environment profiles, and the local cache repository boundary.
- `Packages/StoatDesignSystem`: shared styling tokens and components (the app's glass/native visual language).
- `Packages/StoatUI`: chat shell UI — timeline, composer, markdown rendering, embeds, and shared chat components.
- `Packages/StoatFeatures`: feature layer (view models, coordinators, and screen-level logic) used by the app target.
- `Docs/Research.md`: Stoat API/protocol research notes.
- `Docs/PhaseN.md` (phases 1–73): phase-by-phase implementation history and handoff notes.
- `Docs/QA/`: manual QA pass notes for release gates (freeze/perf, chat presentation, conversation state, notifications, account/identity, community management, native macOS behavior).

Test doubles (`Stub*`/`Test*` types) live only inside each package's test target — none ship in `Sources/`, and `Scripts/check.sh` enforces that on every run.

## Current Limitations

These are deliberate v1.0 scope cuts, not bugs:

- **No offline/persistent cache.** Messages and media are not persisted to disk between launches; everything is fetched live after connecting.
- **No voice/video.** Voice channels and calls are not implemented.
- **No push notifications.** Notifications only fire while the app is running (no APNs/background push), and there's no background networking when the app isn't active.
- **Settings sync is manual.** Cloud-synced settings use explicit fetch/push rather than automatic background sync.
- **Real credentials required.** There's no demo or mock mode in the shipping app — you need a Stoat account to use it, and the app shows a login screen rather than any content until you sign in.

See [Docs/Phase73.md](Docs/Phase73.md) for the most recent architecture notes and [Docs/QA/](Docs/QA/) for release-gate QA coverage.

## Contributing

This project is under active development (see `Docs/Phase*.md` for history). Before opening a PR:

1. Run `Scripts/check.sh` locally — it must pass (all package tests, the test-double gate, and the app build).
2. Keep test doubles inside test targets; don't add `Mock`/`Stub`/`Fake` types to `Packages/*/Sources` or `App`.
3. Add a short `Docs/PhaseN.md` note for notable changes, following the existing phase-log convention.

## License

No license file is currently published for this repository. Until one is added, treat the source as all-rights-reserved by its contributors.
