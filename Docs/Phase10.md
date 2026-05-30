# Phase 10 Summary

## What Was Implemented

Phase 10 stabilizes the message timeline without changing the app architecture. The app still launches mock-safe, does not auto-connect to Stoat, and does not validate saved credentials on launch.

Implemented:

- explicit timeline viewport and scroll intent state
- stronger channel-scoped message action focus
- reply scaffolding in the composer and timeline
- per-channel composer draft state with reply context and mention toggle
- reply send payloads using the existing Stoat `MessageReply` model
- compact reply previews and missing-reference fallback
- jump/newest/first-unread scroll intents
- load-older preserve-position intent
- verified live channel read ack route
- local read state wording and active-channel ack debounce
- keyboard/menu commands for reply, cancel reply, and timeline focus
- accessibility helpers for reply context, reply previews, focused messages, jump affordances, and local read state
- mock-only Phase 10 tests plus an API route test for ack

## Timeline Viewport And Scroll Intent

`TimelineViewportState` now owns the active channel, visible anchors, at-newest state, new-message indicator, and pending `TimelineScrollIntent`.

The timeline still uses SwiftUI `ScrollViewReader`, but scroll behavior is requested through deterministic state:

- channel selection scrolls to first unread when loaded, otherwise newest
- jump newest scrolls to the newest loaded message
- jump first unread scrolls only when the marker is loaded
- missing first unread reports “Unread message is not loaded.”
- loading older messages creates a preserve-position intent using the previous oldest message
- edit completion, retry, and delete fallback keep the relevant message visible
- new messages only auto-scroll when the user is at newest

## Message Focus Model

`TimelineSelection` now wraps `MessageActionFocus`, including channel ID, message ID, source, and mode.

Focus modes cover selected, editing, replying, action menu, and failed recovery. Commands consult this model and continue to pause message actions while the composer, quick switcher, or inline editor owns text entry focus.

## Reply Scaffolding

Replies are implemented as scaffolding, not threads.

- confirmed messages can be replied to from the context menu or command routing
- pending, failed, and system messages are not reply targets
- starting a reply focuses the composer
- composer reply strip shows author, short preview, cancel, and a “Mention” toggle
- cancel reply preserves the current draft text
- reply context is per channel and not persisted
- timeline rows render a compact local reply preview when the referenced message is loaded
- missing references render “Original message unavailable”

Reply sends use `MessageDraft.replies` with `MessageReply(id:mention:)`. The mention toggle defaults on to match the official SDK, but the user can turn it off per reply before sending.

## Composer State

Composer drafts now use `ComposerDraftState` per channel. Normal text, reply context, and mention preference stay isolated by channel.

Inline editing does not clear composer text. Failed reply sends keep reply metadata on the failed timeline row so retry/edit-and-retry can remain contextual.

## Read / Unread / Ack Strategy

Phase 10 verified live channel ack as:

```text
PUT /channels/{channel}/ack/{message}
```

The route is user-only, takes no body, and acknowledges a specific message ID in a channel.

Liquid Bagel sends live ack only when:

- the app is in explicit Live Manual mode
- the session is connected
- the channel is the active selected channel
- the timeline is at newest
- the same message ID has not already been acked locally

Ack sends are debounced and failure only surfaces safe status text. No credential is cleared or retried automatically. Mock mode keeps read behavior local-only.

## Timeline UI

The timeline now shows a clear focused/selected state, compact reply previews, a jump-to-newest affordance when newer messages arrive while not at newest, and reduced-motion-aware scroll animation.

The composer reply strip uses existing design tokens and remains compact for dense timelines. Attachments, media previews, full emoji picking, pinned panels, and threads remain out of scope.

## Keyboard Commands

Added or refined commands:

- Reply to Message
- Cancel Reply
- Focus Timeline
- Jump to Newest Message
- Jump to First Unread
- existing failed-message retry/discard/edit-and-retry commands remain gated while typing

The quick switcher indexes the new commands locally and still performs no remote search.

## Accessibility Improvements

New helper text covers:

- focused message state
- reply context strip
- timeline reply previews
- jump-to-newest affordance
- local read state wording
- composer reply state

Decorative reply icons are hidden from accessibility. Labels do not include tokens, raw credentials, or unsafe diagnostics.

## Tests Added

Added mock-only feature tests for:

- viewport reducer scroll intents
- reply context, composer state, send payload, and cancel behavior
- command gating while typing
- missing first unread status
- live ack debounce and mention clearing through a recording sender

Added API test coverage for:

- `PUT /channels/{channel}/ack/{message}`
- no request body
- authenticated session header

## Mocked Vs Live

Mock mode remains fully local. Live read ack is the only new live route, and it is scoped to the active selected channel after explicit Live Manual connection.

No startup networking, hidden credential validation, uploads, notifications, persistent message database, friends/discover APIs, voice, server/channel settings, account editing, or moderation surfaces were added.

## Known Risks And Limitations

- At-newest detection is lightweight SwiftUI visibility tracking, not a custom virtualized timeline engine.
- Reply previews resolve only against currently loaded local messages.
- Failed reply retry preserves reply IDs, but richer per-failed-row reply mention preferences can be improved later.
- Server-wide ack remains deferred.

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

## Recommended Phase 11 Next Step

Phase 11 should harden timeline ergonomics around real-world volume: better visible-range tracking, loaded/unloaded unread recovery, richer retry metadata, and optional message-reference fetching, still without adding persistent cache or hidden launch-time networking.
