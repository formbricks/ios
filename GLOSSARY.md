# Glossary

Domain terms the code and architecture reviews use. Only terms specific to the iOS SDK belong here: no general
programming concepts, and no implementation details.

## Setup

**Workspace** — The Formbricks container a host app's surveys, action classes and settings belong to, identified by `workspaceId`. _Avoid_: environment (`environmentId` is a deprecated alias kept for backward compatibility).

**Workspace state** — The workspace's surveys, action classes and settings, fetched from the client API, cached on device and refreshed when its `expiresAt` passes.

**Host app** — The app that embeds the SDK and calls its public API.

## Users

**User state** — What the server knows about the identified user: `userId`, `contactId`, segments, displays, responses, last display and language. Synced through `POST /user` and cached until it expires.

**Attribute** — A typed value (string, number or date) stored on the user's contact through `setAttribute` / `setAttributes`. Its type is fixed by its first write. _Avoid_: property, trait.

**Update queue** — The debounced queue that batches `setUserId`, attribute and language writes into one user sync.

**Embedded Data** — Context the host app attaches to future responses with `setEmbeddedData`: string, number, boolean or date values, kept in memory only and never persisted. Not an attribute.

## Surveys

**Action** — A named event the host app reports with `track`. It matches a code action class by its `key`.

**Action class** — A workspace-defined action a survey can be triggered by. The SDK only tracks action classes of type `code`.

**Trigger** — The link between a survey and an action class that shows it.

**Segment** — A server-computed group of users a survey can target. The device only receives segment IDs and never evaluates filters; anonymous users never match a segment with filters.

**Display** — A record that a survey was shown to the user. Displays drive the display option and recontact days.

**Response** — A user's submitted answers to a survey.

**Display option** — Whether a survey may show again: `displayOnce`, `displayMultiple` (until answered), `displaySome` (up to `displayLimit`) or `respondMultiple`.

**Recontact days** — The minimum number of days since the last display before another survey shows; a survey's own value overrides the workspace default.

**Display percentage** — The chance, per matching action, that a survey is shown.

**Interaction refresh** — The server's per-survey flag that a display, response or finish can change segment membership, so the SDK re-syncs the user state right away.

## Presentation

**Overlay** — The backdrop behind a survey: `none`, `light` or `dark`. With `none` the host app stays touchable around the survey card.

**Placement** — Where a survey card sits on screen: a corner or the center.

**Appearance** — The survey theme set by `setAppearance`: `light` (default), `dark` or `system`, which follows the host app's theme.
