# SpaceState – project status and plan

SpaceState shows whether a hackerspace is open and notifies its users when that changes. This document records where the revival of the 2014–2016 project stands, the decisions behind it, and what comes next. Last updated 2026-10-08.

## Where we left off (2026-10-08)

Start here when picking the work up again.

**Everything is merged into `dev` in both repositories; there are no open pull requests and no local changes. Merged feature branches were deleted, so both repositories only have `dev` and `master`.**

- SpacePush: the complete rewrite ([#1](https://github.com/kerker00/SpacePush/pull/1)), incl. two review rounds. 102 EUnit tests pass, xref and Dialyzer are clean, a local run against the real sources worked (also after `kill -9`).
- SpaceState: package, macOS app, localization, icon, the legacy-layout comment fix, Xcode's project file formatting and this document (#1–#7).
- `master` in both repositories is still the 2016 state. Merging `dev` into `master` is a release step and needs an explicit decision.

**Priorities agreed for the next session:**

1. Local push test: SpacePush on the Mac with the APNs key, the macOS app registering via `127.0.0.1:8080`, a state change injected in `rebar3 shell`. Needs only the token registration in the macOS app (part of step 2), no hosting.
2. Host SpacePush on Uberspace – needs answers 1–3 below.
3. Push in the apps – details still to be discussed.
4. Housekeeping: archive the two old repositories.
5. iOS app – later; it is not urgent.

**Questions to answer before continuing** (deferred on 2026-10-08):

1. Uberspace version: U7 or U8? `cat /etc/os-release` on the host answers it.
2. Who manages DNS for `grafixmafia.net`?
3. SSH host and user for the Uberspace account, and may Claude connect to look around (no changes without approval)?
4. Push in the apps: which details still need discussing before work starts (see [step 2](#2-push-in-the-apps-ios-and-macos))?

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
| [kerker00/SpaceState](https://github.com/kerker00/SpaceState) | macOS app, upcoming iOS app, `SpaceStateKit` package | active |
| [kerker00/SpacePush](https://github.com/kerker00/SpacePush) | Erlang/OTP push service | active |
| [kerker00/SpaceStateBar](https://github.com/kerker00/SpaceStateBar) | 2014 macOS menu bar app | superseded by this repo, to be archived |
| [kerker00/SpaceStateBackEnd](https://github.com/kerker00/SpaceStateBackEnd) | 2015 Erlang prototype that polled the old SpaceAPI directory | superseded by SpacePush, to be archived |

Both active repositories use `dev` as the integration branch; feature branches start from `dev` and their pull requests target `dev`.

## Status

| Part | State | Where |
| --- | --- | --- |
| `SpaceStateKit` package (`SpaceAPI`, `MainframeStatus`) | done, tested | SpaceState #1, #5 |
| macOS menu bar app | done | SpaceState #2 |
| German localization | done for the macOS app | SpaceState #3 |
| App icon (Icon Composer, Liquid Glass) | done | SpaceState #4 |
| SpacePush rewrite | done, tested locally, merged into `dev` | SpacePush #1 |
| APNs key (`.p8`) | created 2026-10-09 (Sandbox & Production), stored locally outside the repositories, verified with SpacePush | – |
| Hosting of SpacePush | planned on Uberspace, open questions below | – |
| Push in the apps | not started, to be discussed | – |
| iOS app | not started, low priority; shared code is ready | – |
| Widgets | low priority | – |

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

- `SpaceStateKit/` – local Swift package with two modules:
  - `SpaceAPI`: generic SpaceAPI client. Reads schema v15 and the flat v0.12 layout leniently, reads the directory from the aggregator. Contains nothing specific to Mainframe.
  - `MainframeStatus`: rooms and finer states of Mainframe Oldenburg.
- `Shared/` – app code for both platforms: `StatusStore` (selected space, polling, persisted choice), `DirectoryStore`, display helpers, string catalog, app icon.
- `macOS/` – `MenuBarExtra` with a status panel and settings (space picker, refresh interval, open at login).
- Bundle ID `net.grafixmafia.spacestate`, team `7E3BJ546SA`, App Sandbox with outgoing network access. `NSAllowsArbitraryLoads` is set because some SpaceAPI endpoints are plain HTTP.

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
| Use [GMSnagNav](https://github.com/kerker00/GMSnagNav) if a view needs a sidebar | Own package, already used in PreCal. |
| Widgets are low priority | The menu bar and notifications cover the main use. |

## Next steps

### 1. SpacePush on Uberspace

1. Provide Erlang/OTP 28 and build the release on the Uberspace host or in a Linux container that matches it; a release built on macOS does not run on Linux.
2. Run it as a supervised service that restarts on failure and after reboots.
3. Add the subdomain (for example `push.grafixmafia.net`) with `uberspace web domain add` and route it with `uberspace web backend set … --http --port 8080`; the certificate is issued automatically. Check whether the backend must listen on `0.0.0.0` instead of the default `127.0.0.1` (`http_ip`).
4. Production configuration (a separate config file, not `config/sys.config`): `trust_proxy` on, logger level `notice` (with `info`, every process start is logged as a progress report), data under `~/spacepush/data`, the `.p8` key readable only by the account, `apns_key_id` set.
5. Check `GET /health` from outside, then register a development build and wait for a real state change.

#### Open questions

- Uberspace version (U7 or U8) – decides how the service and Erlang are set up. `cat /etc/os-release` on the host answers it.
- Who manages DNS for `grafixmafia.net` – the subdomain needs a record pointing to the Uberspace host.
- SSH host and user for setting it up, and whether Claude may connect to look around (no changes without approval).

### 2. Push in the apps (iOS and macOS)

Still to be discussed. What is needed:

- `aps-environment` entitlement and push capability for both targets.
- Register for remote notifications, then send the device token with `PUT /v1/devices/<token>`: `environment` is `sandbox` for debug builds and `production` for TestFlight and App Store builds.
- Re-register on every launch; SpacePush expires registrations not renewed within 60 days.
- UI to choose which spaces (and Mainframe rooms) to be notified about; `DELETE` when the user turns notifications off.
- String catalog entries for the six body keys SpacePush sends: `PUSH_STATE_OPEN`, `PUSH_STATE_CLOSED`, `PUSH_STATE_KEYHOLDER`, `PUSH_STATE_MEMBER`, `PUSH_STATE_OPEN_PLUS`, `PUSH_STATE_CLOSING`.
- The APNs key exists (see Status); SpacePush reads it from `apns_key_file` with `apns_key_id` set. Never commit it – `*.p8` is in SpacePush's `.gitignore`.

Until the apps register devices, SpacePush runs but has nobody to notify.

### 3. Housekeeping

- Archive [SpaceStateBar](https://github.com/kerker00/SpaceStateBar/settings) and [SpaceStateBackEnd](https://github.com/kerker00/SpaceStateBackEnd/settings) on GitHub (Settings → Danger Zone → Archive this repository). Both are still unarchived.
- Do not delete the branches `REST-Api` and `handle-state` in SpaceStateBackEnd: they were never merged into its `master` and hold its latest 2015 work (19–20 commits, incl. the REST API). Archiving keeps them as they are.

### 4. iOS app

- Add an iOS 26 target to `SpaceState.xcodeproj` that shares `Shared/`, the string catalog and the icon.
- Screens: status of the selected space (with Mainframe rooms), space picker from the directory, settings.
- Sidebar on iPad via GMSnagNav if a sidebar is needed.

### Later

- Publish `SpaceAPI` as its own Swift package (`git subtree split`), with DocC and a listing on spaceapi.io.
- Widgets.
- Access control for the SpacePush API (for example App Attest) if the current cap, expiry and rate limit turn out not to be enough.
- A real APNs delivery test and a load test for SpacePush (both not done yet; everything else is covered by tests).
- If deliveries for one APNs environment pile up while its connection is down, they take the sender's free slots for that round; fine at this scale, worth revisiting if usage grows.
- App Store / TestFlight distribution.
