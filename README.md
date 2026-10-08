# SpaceState

Shows whether a hackerspace is open – in the macOS menu bar and (soon) on iOS.

Any space listed in the [SpaceAPI directory](https://spaceapi.io) works. For [Mainframe Oldenburg](https://www.kreativitaet-trifft-technik.de) the app also shows its rooms (Radstelle, 3D Lab, Machining) and finer states such as "members only" or "closing".

Project status, decisions and next steps: [docs/PROJECT.md](docs/PROJECT.md).

## Requirements

- macOS 26 / iOS 26
- Xcode 26 or later

## Structure

| Path | Contents |
| --- | --- |
| `SpaceStateKit/` | Swift package: `SpaceAPI` (generic SpaceAPI client) and `MainframeStatus` (Mainframe extras) |
| `Shared/` | App code shared by macOS and iOS |
| `macOS/` | Menu bar app |
| `Config/` | Info.plist additions |

## Build

Open `SpaceState.xcodeproj` and run the `SpaceState-macOS` scheme.

Package tests:

    cd SpaceStateKit && swift test

## License

MIT, see [LICENSE.MD](LICENSE.MD).
