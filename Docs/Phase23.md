# Phase 23 - Discover, Invites, and Create Server

Phase 23 was completed during the Phase 24 audit. The app keeps the existing live-first manual-connect runtime and adds explicit community entry points without hidden networking.

## Landed

- Discover is a web-backed native surface. Native community listings stay deferred until a first-party Discover API is verified.
- Join Invite accepts Stoat invite codes plus supported invite URLs, previews invites only after the user presses Preview, and joins only after confirmation.
- Create Server is wired through the verified `POST /servers/create` route and mock client. It validates the server name locally and runs only after the user presses Create.
- Invite management supports explicit create/copy/list/revoke using verified invite routes. Listing uses the Refresh button; it does not run from server selection.
- Quick switcher and menu commands include Discover, Join Invite, Create Server, Invite Management, Create Invite, and Open Discover in Browser.
- User-facing errors use short safe copy through the Phase 23 redaction helper.

## Deferred

- Native Discover marketplace/listing APIs are not implemented.
- Invite preview/join remain manual and require Live Manual connection outside preview data.
- No automatic invite creation, server creation, live refresh, background sync, push, or persistent cache was added.

## Tests

- Mock-only coverage exists for invite parsing, safe invite/create-server states, command routing, and the Phase 24 regression that invite management opening does not auto-refresh.
- Run focused checks with:

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatFeatures
```
