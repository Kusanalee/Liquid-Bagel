# Phase 53 - Slowmode And Server Emoji Management

Phase 53 extends the existing server-settings architecture with source-verified channel slowmode editing and server emoji administration. It does not claim live parity, add speculative routes, or move file/image preparation into SwiftUI render paths.

## Implemented Behavior

- Channel edit drafts carry the verified numeric slowmode field and preserve `0` as explicitly off.
- Channel settings expose bounded common slowmode choices through the existing edit/save flow.
- Server emoji management uses the verified `emojis` upload tag plus create, list, and delete routes.
- Server settings can refresh emoji, validate and create an uploaded emoji, and request a confirmed deletion.
- Emoji presentation remains prepared through the server-settings snapshot layer, while file reads reuse Phase 52 off-main I/O.
- Permission gating uses `ManageCustomisation`; owners remain allowed and unresolved permission state fails closed.

## Verification

Focused coverage:

```sh
swift test --package-path Packages/StoatModels --filter Phase53
swift test --package-path Packages/StoatAPI --filter Phase53
swift test --package-path Packages/StoatFeatures --filter Phase53
```

The full repository gate is required before Phase 53 is considered implementation-complete:

```sh
git diff --check
Scripts/check.sh
```

Repository verification completed on June 30, 2026:

- `StoatModels` Phase 53: 1 selected test passed.
- `StoatAPI` Phase 53: 1 selected test passed.
- `StoatFeatures` Phase 53/54 slice: 2 selected tests passed.
- `git diff --check`: passed.
- `Scripts/check.sh`: all package suites passed, including 296 `StoatFeatures` tests, and the macOS app ended with `** BUILD SUCCEEDED **`.

## Live QA Still Required

1. Edit a test channel through off and multiple slowmode durations, reconnect, and compare persistence with the official client.
2. Verify a user without `ManageCustomisation` cannot mutate server emoji.
3. Refresh emoji in a safe owned server.
4. Upload and create a valid emoji, confirm it appears in settings, the composer, reactions, and messages, then reconnect.
5. Delete that emoji through the confirmation flow and confirm removal after reconnect.
6. Exercise invalid name, invalid file, upload failure, route failure, and lost-permission behavior.
7. Confirm no synchronous file reads, image decoding, or emoji-list rebuilding appears in SwiftUI render samples.

Slowmode/channel management and server emoji management remain `partial` until the live evidence is recorded.
