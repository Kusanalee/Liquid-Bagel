# Liquid Bagel

Liquid Bagel is a native macOS SwiftUI client skeleton for Stoat. Phase 1 establishes verified model, REST API, authentication-storage, request-building, response-decoding, upload, and mock-client foundations while keeping the app UI intentionally lightweight.

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
- `Packages/StoatRealtime`: placeholder realtime event and Ready-field types.
- `Packages/StoatPersistence`: placeholder cache repository boundary.
- `Packages/StoatDesignSystem`: initial glass styling tokens and components.
- `Packages/StoatUI`: placeholder native chat shell UI.
- `Packages/StoatFeatures`: feature facade used by the app target.
- `Docs/Research.md`: Stoat docs/source research notes.
- `Docs/Phase1.md`: Phase 1 implementation summary and Phase 2 handoff.

## Phase Roadmap

1. Phase 0: project skeleton and research notes.
2. Phase 1: verified models, API foundation, login/session token storage abstraction.
3. Phase 2: realtime WebSocket foundation.
4. Phase 3: main UI shell connected to state.
5. Phase 4+: messaging, media, friends/DMs, settings, macOS integration, and hardening.

## Current Limits

No real Stoat credentials are required to run the app. The visible shell uses `MockStoatAPIClient`; the live REST client is available for verified endpoints but there is no login UI yet. Realtime sockets, full persistence, full chat UI, and live server/channel hydration are deferred to later phases.
