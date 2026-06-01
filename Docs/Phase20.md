# Phase 20: Live Send Repair And Diagnostics

Phase 20 repairs the core chat send path for manual live sessions while preserving the project rule that launch remains mock-safe. The app still starts in mock mode, does not auto-connect, does not validate saved credentials in the background, and does not prefetch media.

## Verified Root Cause

- The current generated API package (`stoatchat/javascript-client-api` package version `0.13.7`) defines `POST /channels/{target}/messages` with an `Idempotency-Key` header and a `DataMessageSend` body.
- `DataMessageSend` carries `content`, `attachments`, `replies`, `embeds`, `masquerade`, `interactions`, and `flags`. The old body `nonce` field is deprecated in favor of the header.
- Liquid Bagel previously sent the same nonce in both places.
- Backend source consumes the `Idempotency-Key` header before message creation, then rejects the duplicate body nonce when `create_from_api` tries to consume it again.
- Official web/SDK behavior sends the idempotency key header and omits body `nonce`.

## Implementation

- `StoatAPIClient.sendMessage` now still sets `Idempotency-Key` from the draft nonce, but encodes a wire payload that omits body `nonce`.
- The send UI records `MessageSendDiagnostics` across validation, runtime checks, permission checks, upload, payload build, optimistic creation, request, decode/reconcile, and failure.
- Composer blocked reasons now distinguish empty drafts, manual-live disconnection, upload-in-progress, failed attachment, and known permission denial.
- Timeline diagnostics include redacted send state without tokens, paths, raw JSON payloads, or long secrets.
- Attachment sends preserve local pasted-image preview data through optimistic and confirmed message reconciliation.
- Media URL resolution uses Autumn routes under `https://cdn.stoatusercontent.com/{tag}/{file_id}` for previews and `/{tag}/{file_id}/original` for originals, with no query parameters.
- Remote preview loading rejects HTML responses and requires image content types for image attachments.

## Tests Added

- API send request uses the `Idempotency-Key` header and verifies the encoded body shape.
- API send request omits nil unsupported fields.
- Attachment URL resolver produces verified Autumn preview/original routes.
- Live manual connected state can send when permissions are unknown/inherited and blocks known denials.
- Send diagnostics redact token/path/raw-payload shaped failures.
- Pasted image sends preserve local preview bytes for timeline rendering.

## QA Checklist

- Launch remains mock mode by default.
- No live connection, validation, cache hydration, APNs registration, or media request happens at startup.
- Manual live send requires an explicitly connected live session.
- Text and attachment sends use the same explicit send action.
- Failed sends remain recoverable in the local timeline.
- Media previews load only after an explicit user action, except local pasted-image preview bytes already held in memory for the just-sent message.

## Deferred

- End-to-end live send should be checked manually with a real Stoat session and a low-risk test channel.
- Realtime echo timing could add a distinct `waitingForRealtimeEcho` state once REST and gateway echo behavior are observed together.
- Persistent media caching remains intentionally absent.
- Broader server/channel permission resolution is still conservative and source-driven.
