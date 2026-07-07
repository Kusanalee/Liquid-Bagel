# Phase 61 - Clipboard Media Paste And Avatar Continuity

Phase 61 responds to the sixth live-QA report. Phase 60 is accepted as directionally green for now: rapid scrolling can still show temporary CPU peaks and mild lag, but the app returns to idle near 0%. Unicode reactions pass live QA. Custom emoji reactions remain outside this pass.

## Implemented Behavior

- Composer Command-V now keeps text paste normal, but clipboard image data and Finder/file-provider URLs queue validated composer attachment chips immediately.
- Pasted media still follows the existing attachment policy: selected conversation required, upload permission checked before send, five-file limit, 20 MB cap, allowed file types only, and uploads wait for Send.
- Drag/drop keeps the explicit review sheet. The Message menu Paste Attachment route remains available as the explicit attachment paste path.
- Local sends preserve the current user and selected-server member identity through pending and confirmed reconciliation, including avatar metadata.
- Locally sent rows with a nonce can use a lightweight local-send presentation while Phase 60 prepares the full row, avoiding a brief generic skeleton/avatar fallback after confirmation.

## QA Status

- Phase 60 performance: record as acceptable unless a fresh sample or Phase 60 counters show repeating viewport flushes, unbounded row queues, stale row churn, image/decode loops, or avoidable main-thread row preparation.
- Reactions: Unicode add/remove/reload is green from live QA; custom emoji reactions are still not claimed.
- Avatar continuity: retest repeated sends in a warmed channel and confirm no initials/fallback flash.
- Notifications: QA Lane 4 lives in Settings -> Notifications. Signature/build readiness is also summarized in Developer diagnostics as Notification build.

## Verification

Run before completion:

```sh
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatFeatures
git diff --check
Scripts/check.sh
```
