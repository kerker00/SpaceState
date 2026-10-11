# Shared app appearance

`Shared/SpaceStyle.swift` defines the Apple app's palette, typography, spacing and card surface. The colors follow the SpaceState website's `assets/css/site.css`: warm paper in light mode, slate in dark mode and readable amber accents from the app icon.

## Color roles

All values are opaque sRGB colors. SwiftUI's environment selects the appearance, so views also follow system appearance changes while open.

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#f4f3ee` | `#151a22` | Page background |
| `surface` | `#fbfaf7` | `#1e2530` | Card background |
| `text` | `#252d38` | `#f4f3ee` | Content and headings |
| `secondaryText` | `#5e6570` | `#b7c0ce` | Supporting labels |
| `border` | `#ced0d2` | `#394353` | Card outlines and separators |
| `accent` | `#925400` | `#fac276` | Link symbols and actions |
| `statusOpen` | `#4f723b` | `#aad77c` | Open status |
| `statusClosed` | `#ad3d31` | `#ff9b8b` | Closed status |
| `statusUnknown` | `#5e6570` | `#b7c0ce` | Unknown status |

With increased contrast, supporting labels, unknown status and borders use `text`. Opaque surfaces and explicit text colors preserve readability in inactive Mac windows. Status must also be expressed with a title or symbol; color alone does not convey its meaning.

## Cards and text

`SpaceCard` provides a surface with an optional localized heading, full content width, an 18-point inset, a 16-point corner radius and a one-point outline. Headings retain their accessibility header trait. It reads appearance itself and can be used by any app view:

```swift
SpaceCard("Address") {
    Text(address)
        .textSelection(.enabled)
}
```

`SpaceLayout` centralizes page/card insets, section/row spacing, the 720-point reading width and the 44-point minimum control height. `SpaceTypography` keeps the readable Mac sizes and uses semantic, Dynamic Type fonts on iOS, including an emphasized status title. Native navigation, controls, selectable text and link behavior remain part of each view.

The detail view, iPhone status screen, Mac menu bar panel and regular Mac status window use these components. `SpaceStatusCard` combines the status symbol/title, change time and message. `SpaceRoomsCard` keeps room names and localized state labels together; rows stack vertically at accessibility text sizes. Restricted room states use amber, while open, closed and unknown keep their own color roles.

The iPhone screen keeps its native list, pull-to-refresh, navigation links and settings sheet. Both Mac status surfaces keep their existing actions. WidgetKit rendering and space/settings pickers still use their existing presentation; each consumer adopts the appropriate roles explicitly.
