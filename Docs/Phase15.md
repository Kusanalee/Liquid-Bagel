# Phase 15 Summary

## What Was Implemented

Phase 15 adds the first native attachment workflow while keeping Liquid Bagel mock-safe by default.

Implemented:

- in-memory composer attachment drafts
- file picker attachment flow
- paste image/file handling in the composer
- drag-and-drop file handling on the composer
- explicit manual upload and Send-triggered upload
- mock and live upload handlers using the existing `StoatAPIClient.uploadFile` route
- message send payloads with uploaded attachment `FileID`s
- attachment-only sends
- upload status and failure states in composer chips
- remove and retry controls for queued/failed attachments
- permission-aware attachment controls using the existing `uploadFiles` permission hint
- safer local validation for count, size, type, folders, packages, and executables
- timeline attachment cards based on server/local file metadata
- a simple native preview sheet for local image drafts
- sandbox read entitlement for user-selected files
- mock-only Phase 15 tests

## Attachment Flow

Adding a file never uploads by itself. Picker, paste, and drag/drop only add a local draft entry to the selected channel composer.

Uploads start only when the user either:

- presses an attachment retry/upload control, or
- presses Send, which uploads any queued attachments before sending the message

After upload, the existing send path uses `MessageDraft.attachments` with the uploaded file IDs. If the message send fails after upload, failed-message retry keeps the uploaded IDs and does not re-upload the same files.

## Validation And Privacy

Attachments are session-memory only. Liquid Bagel does not persist file paths, media bytes, or media cache entries.

Local validation rejects:

- more than 5 attachments per message
- files over 20 MB
- folders and packages
- executable files
- unsupported MVP file types

Supported MVP types are common images, PDF, plain text, Markdown, JSON, CSV, and RTF.

Displayed filenames are sanitized to avoid path leakage. Upload errors use safe user-facing messages and do not expose tokens, raw server responses, or full local paths.

## Mocked Vs Live

Mock mode remains fully local and never uploads to the network. Mock upload returns deterministic mock attachment IDs and mock sends preserve those IDs for timeline rendering.

Live upload uses the already verified media upload route through `StoatAPIClient.uploadFile(data:filename:mimeType:tag:)` with `.attachments`, and only after explicit user action in Live Manual.

No startup networking, automatic credential validation, hidden background upload, persistent media cache, persistent message cache, notifications, global search, full gallery, or full permission resolver were added.

## Tests Added

Added mock-only feature coverage for:

- queued attachments do not upload automatically
- manual upload updates attachment status
- validation rejects oversized files
- attachment controls honor `uploadFiles`
- Send-triggered upload passes attachment IDs to the message action handler
- attachment-only sends
- upload failure keeps the draft intact and does not send

## Known Limitations

Upload progress is coarse because the current API client uploads a prepared multipart body through `URLSession.data(for:)` without byte-level progress callbacks. Phase 15 reports queued, reading, uploading, uploaded, and failed states.

Timeline previews are metadata-first and do not fetch remote media automatically. Local image drafts can preview from memory or the selected file URL.

## How To Run

```sh
swift test --package-path Packages/StoatFeatures
Scripts/check.sh
```
