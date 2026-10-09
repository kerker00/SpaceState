# SpaceState

Shows whether a hackerspace is open – in the macOS menu bar and (soon) on iOS.

Any space listed in the [SpaceAPI directory](https://spaceapi.io) works. For [Mainframe Oldenburg](https://www.kreativitaet-trifft-technik.de) the app also shows its rooms (Radstelle, 3D Lab, Machining) and finer states such as "members only" or "closing".

Project status, decisions and next steps: [docs/PROJECT.md](docs/PROJECT.md).

## Requirements

For the Apple apps:

- macOS 26 / iOS 26
- Xcode 26 or later

The underlying [SpaceStateKit package](SpaceStateKit/README.md) requires Swift 6.2 or later. Linux support is planned and has not yet been verified with a Linux build and test run.

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

## Linux and package extraction

When the API stabilizes, the generic `SpaceAPI` library is intended to move into its own repository, with Linux support tested from the start. The current library uses Foundation and has no SwiftUI, AppKit or UIKit dependencies. `MainframeStatus` remains a separate, optional module for Mainframe's rooms and extra states.

The first useful Linux application would be a command-line tool for finding spaces and querying their status, with human-readable and JSON output. This would let the community integrate it into status bars, scripts and displays in a hackerspace. Distributing Linux binaries would make the tool accessible to users who do not develop in Swift.

A Linux desktop interface would be a separate client using the same library. The existing Apple apps use SwiftUI; Linux desktop integration and local notifications belong in the Linux client.

See [SpaceStateKit's Linux plan](SpaceStateKit/README.md#linux-support-plan) for the required portability changes and verification.

## License

MIT, see [LICENSE.MD](LICENSE.MD).
