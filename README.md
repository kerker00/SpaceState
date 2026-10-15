# SpaceState

Shows whether a hackerspace is open – in the macOS menu bar, on iOS and in widgets on both.

Any space listed in the [SpaceAPI directory](https://spaceapi.io) works. For [Mainframe Oldenburg](https://www.kreativitaet-trifft-technik.de) the app also shows its rooms (Radstelle, 3D Lab, Machining) and finer states such as "members only" or "closing".

Architecture and build configuration: [docs/PROJECT.md](docs/PROJECT.md). The maintained roadmap for all SpaceState projects is the local `../Plan.md` in the shared workspace; it is not part of this repository.

Shared English/German status labels, room names, product names and time meanings:
[docs/TERMINOLOGY.md](docs/TERMINOLOGY.md).

## Features

### Everywhere

- Any space from the SpaceAPI directory, searchable by name and address; Mainframe Oldenburg is the default.
- Open, closed or unknown at a glance, with the time of the last change and the space's status message.
- Mainframe's rooms (Space, Radstelle, 3D Lab, Machining) with their own states.
- Push notifications when the selected space opens or closes, sent by [SpacePush](https://github.com/kerker00/SpacePush).
- Push preferences reconcile through ordered server writes, with visible failures and retries. Permission is checked on launch and returning to the foreground; failed token cleanup is retained locally for a later attempt.
- State is read through SpacePush, with direct SpaceAPI requests as fallback.
- Space details with address, access instructions, contacts, keyholders, feeds, projects, named links and linked spaces, presented in the same card layout on macOS and iPhone.
- English and German.
- Usage statistics for SpacePush without an identifier: the apps send their version and OS version, and mark the first request of each day, week and month (`X-SpaceState-First`); SpacePush only adds these up. See [SpacePush's statistics](https://github.com/kerker00/SpacePush#statistics).

### macOS

- Menu bar item with the current state; a click opens a panel with details, rooms, the space's website, refresh and settings.
- Settings: space, check interval, open at login, Dock icon, notifications.
- Clicking a notification (or the Dock icon) opens the status in a regular window.
- Desktop and Notification Center widgets (small and medium).

### iPhone

- Status screen with rooms, status message and a link to the space's website.
- Settings sheet with space search, check interval and notifications.
- Home screen widgets (small and medium) and lock screen widgets (circular, rectangular, inline).

Each widget chooses its own space, so several widgets can show different spaces.

## Observation times

The app and directory use the observation APIs from Kit 0.3.2. “Observed” (German
“Stand”) describes the original successful proxy fetch or directory observation;
a direct read uses the successful receipt time. “Last checked” describes the
client's latest attempt, including a failure. Neither time replaces a state-change
timestamp. A successful HTTP read does not prove that the provider physically
measured a door at that instant.

Proxy age limits and expiry headers are preserved, with a conservative 15-minute
default for older proxies and direct reads. Missing, future, expired or otherwise
unproven observations provide unknown current status. Timers update the app and
directory between polls; failed directory reads retain the searchable list with
unknown current flags. Details remain available as a labelled last known view.

Space and Mainframe room reads have independent observation times and errors.
A failed room read retains the last known names and values, displays their status
as unknown, and does not remove desired push subscriptions. A successful room
read remains usable even when the separate space read fails.

Widget timelines include explicit unknown entries at the space and room expiry
times, independently of the next network refresh. WidgetKit controls when entries
and reloads are rendered; local tests and unsigned builds do not establish device
scheduling or push delivery. Widget selection and appearance behavior are otherwise
unchanged.

## Opening a space from a widget or notification

A widget tap opens its configured SpaceAPI endpoint; a notification tap opens the
payload's endpoint. The app loads that space's current observation in a temporary
view (an iPhone sheet or a separate Mac window). Closing it returns to the saved
space. The main selection, check interval and desired push subscriptions remain
unchanged; a foreground notification refreshes data without navigating.

Links use `spacestate://status?endpoint=<encoded SpaceAPI URL>` with an optional
`room` for Mainframe. The app validates the link route, unique query items and
endpoint using Kit's URL contract before opening a target. The generic APNs room
`space` refers to the overall space. A valid Mainframe room is emphasized after
fresh room data arrives; a missing room does not replace the space view. Legacy
notifications without an endpoint open the current saved space. Notification
state/name fields never supply the displayed status.

Widget entries retain their configured endpoint across failed reads and expiry;
preview placeholders have no opening target. Actual cold-start URL delivery,
notification interaction and widget taps on each platform require device
validation in addition to local builds and regression tests.

## Sensors

The current source adds a climate/visitors card beneath the rooms on iPhone,
the Mac status panel and temporary opened-space views. It shows the first valid
visitor counter, temperature, humidity and CO₂ reading with the provider's unit
and location/name, without adding overlapping counts or converting units. Details
list all eleven supported sensor kinds and their optional metadata/value-change
time. Empty sections are hidden; visitor names are not included. Other sensor
kinds retained as generic JSON by Kit are not interpreted by the app.

Retained readings are explicitly labelled as last known after failure or when
document observation evidence is stale or missing. Sensor change times do not
refresh that evidence. Medium and large widgets may add current visitors and
temperature when space allows, while keeping the status and observation time;
the existing expiry timeline removes these values at space expiry. Small and
Lock Screen layouts keep their existing content. Changed visible widget readings
also request a reload, subject to WidgetKit scheduling. Real widget fitting,
tinting, VoiceOver, device lifecycle and signed builds remain platform acceptance.

## Projects and linked spaces

Linked spaces in the details view open their SpaceAPI endpoint in a temporary status sheet on either platform. The saved space and notification subscriptions stay unchanged. A separate website link opens externally; a website alone is never treated as an API endpoint. Project and named links open only after HTTP(S) URL validation; invalid values remain readable without an action. Empty sections are hidden.

## Screenshots

The screenshots below predate the sensor display.

| macOS menu bar | macOS settings | macOS widget |
| --- | --- | --- |
| ![Menu bar panel showing Mainframe open with its rooms](docs/screenshots/macos-menu-bar.png) | ![Settings with check interval, login item, Dock icon and notifications](docs/screenshots/macos-settings.png) | ![Small desktop widget](docs/screenshots/macos-widget.png) |

| iOS (German) |
| --- |
| ![iOS status screen showing Mainframe open with its rooms](docs/screenshots/ios-status.png) |

## Requirements

For the Apple apps:

- macOS 26 / iOS 26 (iPhone)
- Xcode 26 or later

The shared [SpaceStateKit package](https://github.com/kerker00/SpaceStateKit) requires Swift 6.2 or later. Xcode resolves the independently maintained package at the exact version `0.3.3`. The Kit repository owns its tests, Linux/macOS CI and releases.

## Structure

| Path | Contents |
| --- | --- |
| External `SpaceStateKit` dependency | Swift products `SpaceAPI`, `MainframeStatus` and `SpacePushClient`, pinned in the Xcode project |
| `Shared/` | App code shared by macOS and iOS |
| `macOS/` | Menu bar app |
| `iOS/` | iOS app |
| `Widget/` | WidgetKit extension for both platforms |
| `Config/` | Info.plist additions and entitlements |
| `docs/` | Architecture and screenshots |

## Build

Open `SpaceState.xcodeproj` and run the `SpaceState-macOS` or `SpaceState-iOS` scheme.

Appearance roles and reusable SwiftUI components are documented in [docs/DESIGN.md](docs/DESIGN.md).

The hostless macOS `SpaceState-PushTests` scheme compiles the production stores
and tests push ordering, retries, permission changes, retained room subscriptions,
coordinated status refreshes, polling, observation expiry, directory freshness and
widget timeline transitions/reload triggers:

```sh
xcodebuild -project SpaceState.xcodeproj -scheme SpaceState-PushTests \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

These regressions use mocked HTTP and notification-system operations, controlled
retry waits and isolated UserDefaults. They do not launch the app, request real
notification permission, contact SpacePush/APNs or reload installed widgets.
Signed app behavior and delivery on real iPhone/Mac devices need separate validation.

The package sources are maintained separately. To run their tests in this workspace:

```sh
cd ../SpaceStateKit
swift test
python3 IntegrationTests/run.py
```

## Shared package and Linux CLI

[SpaceStateKit](https://github.com/kerker00/SpaceStateKit) contains the three shared products, their tests and fixtures. The original package history was preserved during extraction. Update the exact package version in Xcode deliberately when adopting a new release; do not reintroduce a source copy into this repository.

[SpaceStateCLI](https://github.com/kerker00/SpaceStateCLI) `0.3.0` uses the same package for `show` (the default command), `info`, `search` and polling `watch`, with text, JSON, NDJSON and Waybar output. Linux/macOS verification and installation requirements are documented in those repositories.

The Apple apps own their SwiftUI interface, widgets and APNs device integration; the shared package supplies their data and service clients.

## License

MIT, see [LICENSE.MD](LICENSE.MD).
