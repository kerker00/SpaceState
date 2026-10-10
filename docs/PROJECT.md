# SpaceState – project status and plan

SpaceState shows whether a hackerspace is open and notifies its users when that changes. This document records where the revival of the 2014–2016 project stands, the decisions behind it, and what comes next. Last updated 2026-10-09.

## Where we left off (2026-10-09, evening)

Start here when picking the work up again.

**SpacePush runs in production** at `https://push.grafixmafia.net` on the Uberspace 7 account, as a supervisord service. There are two APNs keys, one for Sandbox and one for Production; until the server uses `apns_keys` (SpacePush branch `feature/apns-keys`), it signs both environments with the Production key, so pushes to development builds fail. It serves the apps the spaces' state (`/v1/directory`, `/v1/spaces`, `/v1/mainframe/rooms`) and sends notifications. How it was built and how to update it is in the [SpacePush README](https://github.com/kerker00/SpacePush#deploy-on-uberspace-7). The server still runs the branch `feature/read-proxy`; it switches to the 2.0.0 release (`git fetch && git switch --detach v2.0.0` in `~/spacepush/src`, then the update steps).

**Release 2.0.0** of SpaceState and SpacePush: `dev` merged into `master`, tagged `v2.0.0`, with GitHub releases in both repositories.

**Next steps:**

1. Switch the server from `feature/read-proxy` to `master` (or the `v2.0.0` tag) and run the update steps.
2. Set `apns_keys` in the server's `sys.config` to both keys (see the SpacePush README), then test push on the iPhone and the Mac in both environments.
3. TestFlight build, to test the production APNs environment.
4. Housekeeping: archive SpaceStateBar and SpaceStateBackEnd.

**How to check the current state:**

    # SpaceState: package tests (about 10 s) and macOS build
    cd SpaceStateKit && swift test
    xcodebuild -project SpaceState.xcodeproj -scheme SpaceState-macOS -destination 'platform=macOS' build

    # SpacePush: tests (about 2 s), static checks, local run on http://127.0.0.1:8080
    rebar3 eunit
    rebar3 xref && rebar3 dialyzer
    rebar3 shell

`rebar3 shell` uses `config/sys.config`: no APNs key, so deliveries are only logged, and data goes to `data/` in the SpacePush checkout.

## Repositories

| Repository | Contents | State |
| --- | --- | --- |
| [kerker00/SpaceState](https://github.com/kerker00/SpaceState) | macOS and iOS apps with widgets, `SpaceStateKit` package | active |
| [kerker00/SpacePush](https://github.com/kerker00/SpacePush) | Erlang/OTP push service | active |
| [kerker00/SpaceStateBar](https://github.com/kerker00/SpaceStateBar) | 2014 macOS menu bar app | superseded by this repo, to be archived |
| [kerker00/SpaceStateBackEnd](https://github.com/kerker00/SpaceStateBackEnd) | 2015 Erlang prototype that polled the old SpaceAPI directory | superseded by SpacePush, to be archived |

Both active repositories use `dev` as the integration branch; feature branches start from `dev` and their pull requests target `dev`.

## Status

| Part | State | Where |
| --- | --- | --- |
| `SpaceStateKit` package (`SpaceAPI`, `MainframeStatus`) | done, tested | SpaceState #1, #5 |
| macOS menu bar app | done | SpaceState #2 |
| German localization | done for both apps | SpaceState #3 |
| App icon (Icon Composer, Liquid Glass) | done | SpaceState #4 |
| SpacePush rewrite | done, tested | SpacePush #1, 2.0.0 |
| APNs keys (`.p8`) | two keys created 2026-10-09, one for Sandbox and one for Production; stored locally outside the repositories and on the server | – |
| SpacePush in production | running on Uberspace at `https://push.grafixmafia.net` | SpacePush #3, 2.0.0 |
| Push in the macOS app | registration, notifications and status window done; tested end to end against a local SpacePush | SpaceState #10 |
| iOS app | status, rooms, space picker, settings, push registration; reads through SpacePush with direct fallback | SpaceState #11, #12, #13 |
| Widgets | iOS (home and lock screen) and macOS (desktop, Notification Center); each widget picks its space | SpaceState #13 |

## Architecture

```
            api.spaceapi.io (all spaces)      Mainframe openState (rooms)
                    │                                   │
        ┌───────────┴───────────┐                       │
        ▼                       ▼                       ▼
  SpaceState apps          SpacePush (Uberspace) ◄──────┘
  (SpaceStateKit)          poll → confirm → outbox → APNs
        │                       ▲                │
        │ PUT /v1/devices/:token│                │ push
        └───────────────────────┘                ▼
                                          Apple Push Notification service → devices
```

### Apps

- `SpaceStateKit/` – local Swift package with three modules:
  - `SpaceAPI`: generic SpaceAPI client. Reads schema v15 and the flat v0.12 layout leniently, reads the directory from the aggregator. Contains nothing specific to Mainframe.
  - `MainframeStatus`: rooms and finer states of Mainframe Oldenburg.
  - `SpacePushClient`: registers and removes devices with SpacePush, reads the spaces' state from it, and `StatusService`, which the apps use for all reads: SpacePush first, the spaces directly if SpacePush fails.
- `Shared/` – app code for both platforms: `StatusStore` (selected space, polling, persisted choice), `DirectoryStore`, `PushStore` (permission, device token, registration), `ClientIdentity` (user agent and the shared `ActivePeriods` for SpacePush's statistics; widgets report no periods), display helpers, string catalog, app icon.
- `macOS/` – `MenuBarExtra` with a status panel; a regular status window with the same view, opened by clicking a notification or the Dock icon; settings (space picker, refresh interval, open at login, show in Dock, notifications). The app delegate owns the `StatusStore` so both views share it.
- `iOS/` – iPhone and iPad app (iOS 26): status of the selected space with Mainframe's rooms, pull to refresh, link to the website; settings sheet with space picker, refresh interval and notifications. Same bundle ID as the macOS app, so both form one App Store entry.
- `Widget/` – WidgetKit extension, built twice (`SpaceStateWidget-iOS`, `SpaceStateWidget-macOS`) and embedded in the apps, bundle ID `net.grafixmafia.spacepush.widget`. Small and medium widgets everywhere, plus circular, rectangular and inline on the iPhone lock screen. Each widget is configured with an App Intent to show any space from the directory (default Mainframe; medium shows Mainframe's rooms). It reads through `StatusService` and refreshes every 15 minutes; the apps reload widgets when they see a change. From `Shared/` it takes only the display helpers, `StatusService+Configured` and the string catalog – the app-only files are listed as exceptions in the project.
- `SPACEPUSH_URL` build setting, read from the Info.plist as `SpacePushURL`: `https://push.grafixmafia.net` in Debug and Release. SpacePush tells sandbox and production devices apart itself. For a local SpacePush, set it to `http://127.0.0.1:8080` in Debug.
- Bundle ID `net.grafixmafia.spacepush` (see Decisions), team `7E3BJ546SA`, App Sandbox with outgoing network access. No App Transport Security exception: the apps only connect over HTTPS. SpacePush also reaches the few spaces that serve plain HTTP; when the apps fall back to direct reads, they try `http` endpoints as `https`.

### SpacePush

See the [SpacePush README](https://github.com/kerker00/SpacePush#readme) for the API and configuration. In short:

- Polls the aggregator and Mainframe's `openState` every minute. Data the aggregator could not refresh within 15 minutes counts as unknown.
- A new state is confirmed only when fresh data still shows it two minutes later; every new candidate restarts the wait.
- Confirmed changes become deliveries in a persistent outbox, one per device and topic; temporary APNs failures are retried for up to an hour.
- Tracker, outbox and registrations are synced to disk, so an abrupt restart loses nothing.

## Decisions

| Decision | Reason |
| --- | --- |
| Rebuild in SwiftUI for iOS 26 / macOS 26 only | Hobby project; no compatibility code needed. |
| Any space from the SpaceAPI directory, not only Mainframe | The apps are useful to other hackspaces too. |
| One uniform source: the SpaceAPI aggregator, polled | One request covers all spaces; SpaceAPI has no push mechanism. Mainframe's SSE stream and a few spaces' ad-hoc MQTT were left out to keep one code path. |
| Exception for Mainframe Oldenburg only: rooms and finer states from `openState`, polled in the same loop | Rooms (Radstelle, 3D Lab, Machining) and states such as "members only" are not part of SpaceAPI. |
| Mainframe states: `none` = closed, `keyholder`/`member`/`closing` = not public, `open`/`open+` = open | Matches `ktt-ol/spacestatus2` (`openValues.go`). |
| `valid: false` in the aggregator does not discard a space | A schema error elsewhere does not make the open flag wrong. |
| Keep `SpaceStateKit` in this repository for now; publish `SpaceAPI` as its own package once stable | Avoids two pull requests per change while the API is still moving. No Swift SpaceAPI package exists yet. |
| SpacePush stays Erlang/OTP, with gun (APNs HTTP/2) and cowboy (API) as the only dependencies | Revives the original design; jiffy replaced by OTP's `json`. The legacy binary APNs interface was shut down in 2021. |
| Dependencies pinned to releases at least a month old (gun 2.6.0, cowboy 2.19.0) | The newest releases were published the day they were chosen. |
| Host SpacePush on Uberspace | Domain, HTTPS, process supervision and backups already exist there; no home VM or tunnel needed. |
| SpacePush reliability rules from two review rounds: confirm only on fresh data, persistent outbox, one request per device and topic, send only on connections that are up, versioned registrations and disk formats | Every rule has a test; see the SpacePush pull request for the reasoning. |
| iOS app after hosting and push | Agreed priority; the macOS app covers daily use until then. |
| Bundle ID `net.grafixmafia.spacepush` instead of the old `net.grafixmafia.spacestate` | The old ID is taken but can no longer be assigned to the team, neither in Xcode nor in the developer portal. The app keeps its name SpaceState; SpacePush's `apns_topic` must match this ID. |
| A regular status window in addition to the menu bar panel | Notification clicks need something that can be opened from code; it shows the same view. |
| Dock icon optional (`Show in Dock`, off by default) | A menu bar app by default, as before; some users prefer a Dock icon. |
| Use [GMSnagNav](https://github.com/kerker00/GMSnagNav) if a view needs a sidebar | Own package, already used in PreCal. |
| Widgets configured per widget with an App Intent instead of following the app's selected space | Several widgets can show different spaces, and no App Group is needed between app and widget. |

## Next steps

### 1. SpacePush on Uberspace – done

Running since 2026-10-09 on Uberspace 7 (CentOS 7) at `https://push.grafixmafia.net`:

- OpenSSL 3.5.9 (static) and Erlang/OTP 28.5.0.7 built in the home directory, since the system's OpenSSL 1.0.2 and OTP 21 are too old.
- The release runs as a supervisord service on port 52184, which is closed to the outside; Uberspace's web backend forwards HTTPS to it. DNS: `A`/`AAAA` records for `push` at Namecheap.
- Configuration, APNs key and data live outside the release under `~/spacepush/`.
- The user runs all commands on the host; Claude prepares them.

The full procedure, updates, rollback and troubleshooting are in the [SpacePush README](https://github.com/kerker00/SpacePush#deploy-on-uberspace-7).

### 2. Push in the apps (iOS and macOS)

Done for macOS (SpaceState #10):

- Push entitlement (`com.apple.developer.aps-environment`) in `Config/macOS.entitlements`.
- `PushStore` asks for permission, receives the device token and sends `PUT /v1/devices/<token>` with `environment` `sandbox` in Debug and `production` otherwise. It re-registers on every launch and whenever the subscriptions change, and sends `DELETE` when notifications are turned off.
- Subscriptions are the selected space and, for Mainframe, each of its rooms.
- The string catalog has the six body keys SpacePush sends (`PUSH_STATE_OPEN`, `PUSH_STATE_CLOSED`, `PUSH_STATE_KEYHOLDER`, `PUSH_STATE_MEMBER`, `PUSH_STATE_OPEN_PLUS`, `PUSH_STATE_CLOSING`) in English and German.
- Clicking a notification opens the status window. The menu bar panel cannot be opened from code: `MenuBarExtra` has no API for it, and clicking its status item programmatically has no effect on macOS 26.

Still open:

- UI to choose several spaces or single Mainframe rooms; today it follows the selected space.

The APNs keys exist (see Status); SpacePush reads one per environment from `apns_keys`, or a single key for both from `apns_key_file` and `apns_key_id`. The apps register with the environment of their signature (`aps-environment`), not of the build configuration. Never commit a key – `*.p8` is in the `.gitignore` of both repositories.

#### Running the local push test again

1. Start SpacePush with the key (data in a scratch directory, not in the checkout):

        erl -sname spacepush_local -setcookie <random> -noshell -pa _build/default/lib/*/ebin \
          -config config/sys.config \
          -spacepush apns_key_file '"<path to AuthKey_….p8>"' -spacepush apns_key_id '<<"<key id>">>' \
          -spacepush registry_file '"<scratch>/registry.dets"' -spacepush outbox_file '"<scratch>/outbox.dets"' \
          -spacepush tracker_file '"<scratch>/tracker.bin"' \
          -eval 'application:ensure_all_started(spacepush).'

2. Set `SPACEPUSH_URL` to `http://127.0.0.1:8080` for Debug, run the macOS app from Xcode and turn on notifications in its settings.
3. Inject a change from a second node: `rpc:call(Node, spacepush_outbox, enqueue, [[{{Endpoint, Room}, Name, From, To}]])`. To check the outbox, read `ets:tab2list(spacepush_outbox_entries)` – do not call `spacepush_outbox:due/3` with a future time: it drops entries that would be expired at that time.

### 3. Housekeeping

- Archive [SpaceStateBar](https://github.com/kerker00/SpaceStateBar/settings) and [SpaceStateBackEnd](https://github.com/kerker00/SpaceStateBackEnd/settings) on GitHub (Settings → Danger Zone → Archive this repository). Both are still unarchived.
- Do not delete the branches `REST-Api` and `handle-state` in SpaceStateBackEnd: they were never merged into its `master` and hold its latest 2015 work (19–20 commits, incl. the REST API). Archiving keeps them as they are.

### 4. iOS app

First version in SpaceState #11: target `SpaceState-iOS` sharing `Shared/`, the string catalog and the icon; status screen, settings sheet, space picker and push registration (`aps-environment` in `Config/iOS.entitlements`).

Still to do:

- Push test on a device against production SpacePush.
- A sidebar on iPad via GMSnagNav, if several spaces are shown at once later.

### Later

- Publish `SpaceAPI` as its own Swift package (`git subtree split`), with DocC and a listing on spaceapi.io.
- Access control for the SpacePush API (for example App Attest) if the current cap, expiry and rate limit turn out not to be enough.
- A real APNs delivery test and a load test for SpacePush (both not done yet; everything else is covered by tests).
- If deliveries for one APNs environment pile up while its connection is down, they take the sender's free slots for that round; fine at this scale, worth revisiting if usage grows.
- App Store / TestFlight distribution.
