# Phase 9 Summary

## What Was Implemented

Phase 9 deepens the message experience while keeping Liquid Bagel mock-safe by default. The app still launches in mock mode, does not validate credentials on launch, and does not open REST or WebSocket connections unless the user explicitly acts.

Implemented:

- explicit in-memory message history state
- reducer-based timeline reconciliation
- inline message editing
- safer confirmed-delete and failed-message recovery flows
- pin/unpin wiring through existing API methods
- expanded quick reactions
- local read/unread state and first-unread/newest jumps
- richer message commands and menus
- improved message accessibility labels
- mock-only tests for message history, actions, unread behavior, commands, and accessibility

## Message History Model

`ChannelMessageHistory` is the per-channel non-persistent history model. It stores timeline wrappers, loading flags, pagination state, the first unread marker, newest message ID, last load time, and a sanitized error message.

`ChannelMessageState` remains as the view-facing compatibility adapter, so existing timeline loading/empty/error UI can keep reading the same shape. No database, persistent cache, or message file storage was added.

## Timeline Reconciliation

`ChannelMessageHistoryReducer` now handles initial loads, older loads, snapshot merges, optimistic sends, send confirmations, failed sends, retries, local discards, realtime messages, updates, deletes, reactions, pins, unread marker moves, and local mark-read events.

Messages dedupe by ID and optimistic nonce, sort chronologically, preserve pending/failed local rows across channel switching, keep cached messages on failed loads, and cap memory per channel while retaining active local messages.

## Inline Edit Behavior

Editing now uses `InlineEditState` and renders in the message timeline instead of a sheet. The edit draft initializes from the selected confirmed message, composer drafts remain untouched, blank/unchanged saves are disabled, save progress is shown, failures keep the draft visible, and success reconciles the returned message and exits edit mode.

Message commands pause while the composer, quick switcher, or inline editor owns focus.

## Delete Behavior

Confirmed messages still require explicit confirmation and are removed only after the action handler succeeds. Pending messages are not server-deleted. Failed local messages can be retried, edited and retried, or discarded without a server call. Delete failure leaves the message visible and reports a sanitized status.

Selection falls back safely when a selected message is removed.

## Pin And Reaction Behavior

`MessageActionHandling` now includes `pinMessage` and `unpinMessage`. Live handling calls the already-verified `StoatAPIClient` pin routes. Mock handlers record pin/unpin calls for tests.

Message menus expose Pin/Unpin when the selected message is confirmed and permissions allow it. Rows show an accessible pinned marker. Quick reactions are `👍`, `❤️`, `😂`, `👀`, and `✅`; toggles continue to use the shared action path.

## Failed And Pending Messages

Pending messages show progress state and accessibility text. Failed messages show the sanitized error plus Retry, Edit & Retry, and Discard actions. Failed local messages are session-memory only and are not persisted.

Retry removes the failed local row and sends a fresh optimistic message with a new nonce, while normal snapshot/realtime nonce reconciliation still prevents duplicate confirmed echoes.

## Local Unread And Read Behavior

`LocalReadState` tracks channel-local first unread, last read, unread count, and mention count in memory. Selecting a channel records the first unread marker before locally clearing unread count. Mention count is preserved when the client cannot confidently clear server-side mention state.

Jump to first unread selects and scrolls to the stored marker when loaded. Jump to newest selects and scrolls to the newest loaded message. No live ack send was added.

## Keyboard Message Commands

Phase 9 adds command routing for:

- copy selected message
- developer-gated copy selected message ID
- edit selected message
- delete selected message
- retry/discard/edit-and-retry failed message
- pin/unpin selected message
- jump to first unread
- jump to newest

Mac menu commands route through `AppCommandHandling`, matching context menu behavior.

## Accessibility Improvements

Message labels now include edited, pinned, reaction count, pending/failed/deleting, and selected state when applicable. Inline edit fields, failed-message actions, reaction labels, unread separators, and jump affordances have explicit labels or hints.

## Tests Added

New mock-only coverage includes:

- reducer reconciliation for loads, optimistic sends, confirmation, failed sends, local discard, reactions, pin/unpin, and caps
- inline edit state and composer draft preservation
- delete confirmation/removal and selection fallback
- failed-message discard without API delete
- command gating while inline editing
- pin/reaction routing through mocks
- local unread state and jump-first-unread behavior
- UI/design accessibility helper text

## Mocked Vs Live

Mock mode remains fully local. Live message send/edit/delete/react/pin actions call verified REST methods only after explicit user action in Live Manual. Tests use mocks only and require no credentials or live network.

## Deferred

Still deferred:

- automatic live connect on launch
- automatic credential validation on launch
- live read ack sending
- uploads/media UI
- notifications
- persistent message cache/database
- full friends/DM/discover APIs
- voice
- server/channel settings
- full account editing
- full permission resolver
- full emoji picker or remote emoji search
- pinned-message panel

## Known Risks And Limitations

Timeline scrolling remains a lightweight SwiftUI `ScrollViewReader` selection intent rather than a virtualized timeline focus system. Local unread state is intentionally conservative and does not claim server acknowledgement. Pin permission handling uses the available local permission hints and remains limited until a full resolver exists.

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

## Recommended Phase 10 Next Step

Phase 10 should focus on richer timeline navigation and message composition polish: stable scroll position tracking, a real message action focus model, reply scaffolding if desired, and a verified strategy for live read acknowledgements only if the endpoint/event shape is confirmed.
