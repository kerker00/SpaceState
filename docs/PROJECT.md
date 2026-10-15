# SpaceState – architecture and build configuration

SpaceState shows whether a hackerspace is open on macOS and iPhone, with widgets and notifications. This document describes the current Apple implementation and its place in the portfolio. Last updated 2026-10-13.

The maintained roadmap, priorities and open decisions for all projects live in `Plan.md` in the parent workspace (`../../Plan.md` from this document in the shared checkout layout). That file is local and not tracked in this repository. Repository documentation describes how each component works and how to build it.

## Portfolio

| Repository | Responsibility |
| --- | --- |
| [SpaceState](https://github.com/kerker00/SpaceState) | SwiftUI apps for macOS 26 and iPhone with iOS 26; WidgetKit extensions and APNs device integration |
| [SpaceStateKit](https://github.com/kerker00/SpaceStateKit) | Shared Swift clients, models, tests and versioned releases; the Apple project pins exact version `0.3.3` |
| [SpaceStateCLI](https://github.com/kerker00/SpaceStateCLI) | Linux/macOS command line client; version `0.3.0` provides `show`, `info`, `search`, `watch` and saved spaces |
| [SpaceState-Android](https://github.com/kerker00/SpaceState-Android) | Android app developed separately on Linux, with a Swift-to-Kotlin bridge; in development |
| [SpacePush](https://github.com/kerker00/SpacePush) | Erlang/OTP service for shared status reads and APNs notifications |
| [SpaceStateWebsite](https://github.com/kerker00/SpaceStateWebsite) | Public project website and live SpaceAPI overview |
| [SpaceStateBar](https://github.com/kerker00/SpaceStateBar) | Historical 2014–2016 macOS predecessor, superseded by SpaceState |
| [SpaceStateBackEnd](https://github.com/kerker00/SpaceStateBackEnd) | Historical Erlang prototype, superseded by SpacePush |

Android's local checkout may lag behind work on the Linux development machine. Its own repository documents the bridge and build requirements. Each component has its own version; the CLI version does not imply a Kit version.

## Data flow and shared package

The Apple apps and widgets read through `SpacePushClient.StatusService`: SpacePush first, then direct requests if the service fails. Cancellation does not trigger a fallback. Mainframe's rooms are additional detail; a failed room request does not hide the space's state.

SpaceStateKit provides three products:

- `SpaceAPI`: generic directory and status client, with lenient decoding of schema v15 and the flat v0.12 layout. Malformed optional details do not discard an otherwise readable space.
- `MainframeStatus`: Mainframe Oldenburg's rooms and finer states, obtained from its `openState` API.
- `SpacePushClient`: device registration, status reads and the shared `StatusService` fallback.

Xcode resolves the external package at exact version `0.3.3`; `Package.resolved` records the matching revision. Package sources, tests and releases belong to SpaceStateKit, not this repository.

`SPACEPUSH_URL` supplies the Info.plist key `SpacePushURL`, currently `https://push.grafixmafia.net` in both Debug and Release. The apps have no App Transport Security exception. Direct fallback promotes directory endpoints from HTTP to HTTPS; SpacePush can also fetch spaces that only serve HTTP. Server deployment and configuration instructions belong to the [SpacePush README](https://github.com/kerker00/SpacePush#readme), rather than an App-side deployment snapshot.

## Apple implementation

| Path | Responsibility |
| --- | --- |
| `Shared/StatusStore.swift` | Selected space, persisted check interval, polling and widget reloads when state or rooms change |
| `Shared/DirectoryStore.swift` | Space directory and search |
| `Shared/SpaceDetailsView.swift`, `Shared/SpaceDetailLinks.swift` | Address, access hints, contacts, keyholders, feeds, projects, named links and linked-space destinations in a shared card layout |
| `Shared/PushStore.swift`, `Shared/ClientIdentity.swift` | Notification permission, device registration and request metadata |
| `Shared/Localizable.xcstrings` | English and German App, widget and notification strings |
| `macOS/` | Menu bar panel, regular status/detail windows, settings and optional Dock icon |
| `iOS/` | iPhone status screen, pull to refresh, navigation to details and settings sheet |
| `Widget/` | WidgetKit provider and views for both platforms |
| `Config/` | Info.plist additions and entitlements |

The macOS status panel opens details in a separate window; iPhone navigates to the same view. The card layout and contrast improvements landed in [#29](https://github.com/kerker00/SpaceState/pull/29) for macOS and [#30](https://github.com/kerker00/SpaceState/pull/30) for iPhone. Empty sections are omitted, and malformed contact values remain readable text. Contact links use a fixed scheme allowlist. Project/named/website links use the Kit HTTP(S) validation contract before opening. Linked-space endpoints open a locally owned temporary status sheet, including from another temporary target; they do not persist selection or change push subscriptions. Each target owns its polling lifecycle, with iPhone background suspension. Website-only linked spaces remain external website links. The view follows system appearance and increased contrast, with Dynamic Type on iPhone.

The current iOS app and widget targets use `TARGETED_DEVICE_FAMILY = 1`: iPhone. The macOS app delegate owns the shared status store so the menu panel and regular windows stay synchronized. Clicking a notification or the Dock icon opens the regular status window.

Widgets choose their own space through an App Intent; they do not follow the App's selection. Small, medium and large widgets are available on both platforms, with circular, rectangular and inline lock-screen families on iPhone. Medium/large widgets also show Mainframe's rooms and may fit current visitors/temperature; small and Lock Screen content is unchanged. WidgetKit is asked for another refresh after 15 minutes; the apps request timeline reloads when fetched state, rooms or displayed widget sensor values change, when the effective status becomes unknown or recovers, and from delivered notification callbacks.

Status refreshes from polling, pull to refresh, foreground transitions and
notifications share one current worker. New triggers invalidate its in-flight
result and coalesce into one follow-up read. Changing selection cancels the old
worker; its late results and cleanup cannot affect the new selection or refresh
indicator. `lastUpdate` records the last successful space read; `lastAttempt`
records a started attempt. These are client read times, not the source's data age.
iPhone polling pauses in the background and resumes on activation; macOS keeps
polling while its menu bar app runs.

Notification presentation and response handlers enqueue refresh work promptly.
They ask widgets to reload and refresh the selected space only when the payload
endpoint matches it, or when a legacy notification lacks an endpoint. Payloads
never replace the selection or supply display state. The service's current alert
pushes do not guarantee waking an iPhone app for background work; no additional
background execution capability is enabled here. Widget reloads remain subject
to WidgetKit scheduling. Navigation to the notification's space has its own scope.

## Notifications and identity

`PushStore` asks for notification permission and registers the device token with SpacePush. Subscriptions follow the selected space and its Mainframe rooms. Registration is refreshed on launch and when subscriptions change; turning notifications off removes the registration.

The APNs environment comes from the signed entitlement: `development` means sandbox and `production` means production. macOS reads `com.apple.developer.aps-environment` from its signature; iPhone reads `aps-environment` from the embedded provisioning profile, with distribution builds without a profile using production. The simulator uses sandbox. If the signature/profile cannot be read, Debug/Release is only a fallback. A Release build signed for development therefore still uses sandbox.

Both apps use bundle ID `net.grafixmafia.spacepush`, and widgets use `net.grafixmafia.spacepush.widget`. SpacePush's APNs topic must match the App bundle ID. The name remains SpaceState; the legacy bundle ID `net.grafixmafia.spacestate` could not be assigned to the current team.

Push preference changes use one ordered stream of server writes. An in-flight
request finishes before the latest desired registration or removal is sent;
stale responses do not publish success for an obsolete preference. Errors remain
visible and can retry automatically or from settings. Tokens which may have
reached SpacePush are retained in local UserDefaults until deletion succeeds,
so disabled apps can retry cleanup after reopening. Saved tokens are used for
cleanup; registration after a cold start requires a fresh APNs callback.

Launch and foreground checks read system authorization without showing a prompt.
Explicit enabling may ask for permission. Revoked authorization removes the
server registration while retaining the app's notification preference; returning
with authorization restores registration. Permission results that predate a newer
toggle are ignored. The selected Mainframe's known room IDs are retained locally,
bounded to 49 rooms plus the space, so failed or partial reads do not remove its
desired subscriptions. Selecting another space changes the subscription target.

Requests describe App/widget version and OS version in the user agent. Apps use `ActivePeriods` to mark the first request of a day, week and month for aggregate statistics; widgets do not report periods. No installation identifier is sent. APNs keys and operational secrets remain outside the repositories.

## Build and implementation decisions

Open `SpaceState.xcodeproj` in Xcode 26 or later and run `SpaceState-macOS` or `SpaceState-iOS`. Deployment targets are macOS 26 and iOS 26; SpaceStateKit requires Swift 6.2 or later. The widget targets are embedded in their respective App builds. Package verification commands are in the [README](../README.md#build).

The App integration branch is `dev`; feature branches start from it and pull requests target it. Package upgrades deliberately change the exact version in Xcode rather than copying package sources into `Shared/`.

| Decision | Reason |
| --- | --- |
| Support any space from the SpaceAPI directory | The App can serve other hackerspaces as well as Mainframe. |
| Keep generic SpaceAPI and Mainframe-specific data separate | Rooms and finer access states come from Mainframe's own API. |
| Treat a failed current status read as unknown | A stale open/closed state must not look current. |
| Do not discard a directory entry solely because the aggregator reports `valid: false` | An unrelated schema error does not necessarily invalidate its state. |
| Map Mainframe `none` to closed; `keyholder`, `member`, `closing` to restricted access; `open`, `open+` to open | Preserve the meaning of Mainframe's published states. |
| Keep a regular macOS status window alongside the menu panel | Notification and Dock clicks need a window that can be opened directly. |
| Make the Dock icon optional, off by default | The App remains a menu bar utility by default. |
| Configure widgets independently with App Intents | Several widgets can show different spaces without an App Group. |
