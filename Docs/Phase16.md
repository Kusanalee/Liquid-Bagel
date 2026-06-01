# Phase 16 Summary

## What Was Implemented

Phase 16 hardens the Phase 15 attachment workflow with explicit media actions, safer display state, better previews, and mock-only tests while keeping Liquid Bagel mock-safe by default.

Implemented:

- attachment display items that separate local drafts, uploaded drafts, remote files, and unavailable files
- safer filename, content type, kind, file size, and short-ID formatting
- richer timeline attachment cards with Preview, Save As, Retry, and Open controls
- explicit remote preview/download loading through a remote attachment loader
- mock and live remote loaders, with live loading based on the verified Autumn media routes
- preview sheet support for local drafts, loaded remote images, and generic file details
- Save As and Open Externally abstractions with mock test doubles
- system-temp files for explicit Open Externally when a remote attachment has already been loaded
- composer aggregate attachment count/size copy
- clearer queued/uploading/uploaded/failed attachment states and retry behavior
- attachment diagnostics with token/path redaction
- sandbox user-selected read-write entitlement for native Save As

## Attachment Display Model

`AttachmentDisplayItem` is the UI-facing model for attachments. It stores safe display metadata, inferred kind, preview state, and source information without local file paths, raw URLs, tokens, or raw server errors.

Sources are represented as local draft, uploaded draft, remote, or unavailable. Kinds include image, PDF, text, archive, generic file, and unsupported.

## Timeline Card Behavior

Timeline cards are metadata-only on render. They do not fetch remote media on appearance.

Cards show sanitized filename, kind, MIME/type label, file size when known, preview state, and explicit controls:

- Preview loads image/PDF/text-compatible remote content only after click.
- Save As loads the original file only after click.
- Open Externally appears only after local/temp data exists.
- Retry appears only after preview load failure.

## Remote Media Loading Behavior

Remote loading is explicit and memory-first. The live loader uses the configured media base URL and verified Autumn routes:

- preview: `/{tag}/{file_id}`
- original: `/{tag}/{file_id}/original`

The loader adds no query parameters and sends no auth headers. Preview requests enforce a size limit and map failures to short safe copy.

## Preview Behavior

The preview sheet supports:

- local pasted-image data
- local file image data when user-selected access allows it
- loaded remote image data
- generic file detail preview for non-image files
- retry after preview failure
- Save As and Open Externally controls when allowed
- optional shortened file ID when developer controls are enabled

It never displays raw local paths.

## Download, Save As, And Open Externally

Save As is user-controlled through the native save panel. Cancellation is not treated as an error.

Open Externally uses only local or system-temp files and is never automatic. Executable-like extensions and executable files are blocked before opening.

## Composer Attachment Polish

The composer now shows aggregate attachment count and size. Queued and failed attachments expose explicit upload/retry controls; all attachments can be removed. Send is disabled while uploads are running or any upload has failed.

## Permission Behavior

Existing `uploadFiles` behavior is preserved. Known missing upload permission disables attach controls, while mock mode remains usable. Phase 16 improves disabled labels and hints without adding a full permission resolver.

## Security And Privacy Behavior

Phase 16 keeps the attachment workflow session-memory only:

- no hidden remote fetches
- no startup media load
- no persistent media cache
- no persistent message cache
- no file path leakage in diagnostics or broad UI
- no token or raw URL output
- no remote HTML rendering
- no executable auto-open

## Tests Added

Mock-only tests cover display mapping, kind inference, remote load gating, preview state, Save As/Open state, diagnostics redaction, and composer retry/readiness behavior.

## Deferred

Still deferred: persistent cache/database, background prefetch, gallery browsing, video/audio playback, OCR, full file manager, search, notifications, voice, server/channel settings, full permission resolver, and live tests requiring credentials.

## How To Run

```sh
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
Scripts/check.sh
```

## Recommended Phase 17

Phase 17 should focus on message/reaction ergonomics and timeline action polish, keeping media caching and gallery behavior deferred unless a clear product need appears.
