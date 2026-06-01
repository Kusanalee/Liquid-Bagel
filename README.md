# Liquid Bagel

Liquid Bagel is a native macOS SwiftUI client skeleton for Stoat. It now includes verified model/API/realtime foundations, a live-first manual runtime, retained preview/test mock data, manual credential setup, safe non-token preference persistence, focused account/session management, inline image previews, identity media, and a repaired live-manual chat send path.

## Requirements

- macOS with Xcode 26.5 or newer
- Swift 6 toolchain

## Build

```bash
xcodebuild -project LiquidBagel.xcodeproj -scheme LiquidBagel -destination 'platform=macOS' build
```

## Test

```bash
Scripts/check.sh
```

The check script runs every local Swift package test target, then builds the macOS app target.

## Structure

- `App/`: thin macOS SwiftUI app shell.
- `Packages/StoatModels`: core Stoat value models, ID wrappers, config decoding, and permission bitmasks.
- `Packages/StoatAPI`: REST API environment, auth credentials, Keychain-backed token storage, request/response handling, upload scaffolding, live client, and mock client.
- `Packages/StoatRealtime`: realtime WebSocket client, event decoding, diagnostics, and state store.
- `Packages/StoatPersistence`: safe app preferences, environment profiles, and placeholder cache repository boundary.
- `Packages/StoatDesignSystem`: initial glass styling tokens and components.
- `Packages/StoatUI`: placeholder native chat shell UI.
- `Packages/StoatFeatures`: feature facade used by the app target.
- `Docs/Research.md`: Stoat docs/source research notes.
- `Docs/Phase1.md` ... `Docs/Phase21.md`: phase implementation summaries and handoff notes.

## Phase Roadmap

1. Phase 0: project skeleton and research notes.
2. Phase 1: verified models, API foundation, login/session token storage abstraction.
3. Phase 2: realtime WebSocket foundation.
4. Phase 3: main UI shell connected to state.
5. Phase 4: controlled live manual runtime and message actions.
6. Phase 5: manual credential import, login/MFA, Keychain scoping, and verification.
7. Phase 6: safe preferences, environment profiles, account summary, and session management.
8. Phases 7-21: timeline actions, replies, diagnostics, search, attachments/media, notifications/lifecycle, live send repair, live-first startup, inline images, avatars, server icons, and banners.

## Current Limits

No real Stoat credentials are required to run the app. Normal launch is live-first and starts signed out or ready for manual connection; it never auto-connects to live Stoat, never auto-validates credentials on launch, and stores session tokens only in Keychain. Preview/mock data remains available for tests, previews, and developer controls. Persistent message/media cache, friends/discover APIs, voice, broad server/channel settings, and automatic background networking remain deferred.
