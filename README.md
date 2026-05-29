# Liquid Bagel

Liquid Bagel is a native macOS SwiftUI client skeleton for Stoat. Phase 0 establishes the project shape, local package boundaries, and a buildable placeholder app without implementing live API, realtime, persistence, login, or Keychain behavior yet.

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
- `Packages/StoatModels`: placeholder core model and ID types.
- `Packages/StoatAPI`: placeholder API environment, auth credential, and client protocol.
- `Packages/StoatRealtime`: placeholder realtime event and Ready-field types.
- `Packages/StoatPersistence`: placeholder cache repository boundary.
- `Packages/StoatDesignSystem`: initial glass styling tokens and components.
- `Packages/StoatUI`: placeholder native chat shell UI.
- `Packages/StoatFeatures`: feature facade used by the app target.
- `Docs/Research.md`: Phase 0 Stoat docs/source research notes.

## Phase Roadmap

1. Phase 0: project skeleton and research notes.
2. Phase 1: verified models, API foundation, login/session token storage abstraction.
3. Phase 2: realtime WebSocket foundation.
4. Phase 3: main UI shell connected to state.
5. Phase 4+: messaging, media, friends/DMs, settings, macOS integration, and hardening.

## Current Limits

No real Stoat credentials are required or used. Network clients, Keychain storage, realtime sockets, local persistence, and message actions are intentionally placeholders until the API details are verified in Phase 1.
