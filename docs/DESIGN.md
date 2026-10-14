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

The iPhone screen keeps its native list, pull-to-refresh, navigation links and settings sheet. Both Mac status surfaces keep their existing actions. Space/settings pickers adopt the appropriate roles in their own step.

## Widgets

Widgets use the same localized status titles, symbols and semantic colors as the app. In full-color presentation, their removable container surface uses paper/slate and the app's contrast-aware foreground roles. In accented or vibrant presentation, foreground roles and accent groups defer to WidgetKit; the custom background is clear. The system still owns container margins, corners and rendering.

Small widgets prioritize the space name and status word/symbol. Observation time has priority over the optional state-change time when space is tight; unknown states do not show a change time. Medium widgets add room names and localized state words with distinct symbols, and fit up to five, three or one room according to available height. Missing room data stays visibly separate from the space's state. Long names may truncate visually but retain their complete accessibility labels; supporting metadata yields space before the main status does.

Lock Screen layouts are separate: circular widgets show a status symbol and short status word, inline widgets put the status before the space name, and rectangular widgets include the name, status and observation. Circular/inline accessibility labels contain the complete space name and a localized status value; other layouts combine related labels and hide decorative symbols from VoiceOver.

`SpaceStatusView` reads the actual WidgetKit environment and passes its presentation inputs to `SpaceWidgetContent`. The provider and C-01 observation/expiry timeline remain responsible for deciding the effective states. Native layout samples can verify appearance and fitting; actual WidgetKit tinting, accessibility font scaling and VoiceOver on devices require platform acceptance. Widget/notification navigation is tracked separately from appearance.

## Space selection and settings

Both pickers use `SpaceSelectionRow` on the shared card surface. The caller passes the directory's effective status and original observation time; retained raw flags do not select the displayed color. Names and addresses wrap, each status has a localized word and symbol, and selection has a checkmark, outline and accessibility selection trait. Related text is combined for VoiceOver. At accessibility text sizes, the decorative leading symbol yields width to the labels.

iPhone selection retains native list buttons, search and navigation/dismissal. Mac selection retains native list selection, endpoint tags and its keyboard path; its settings window has minimum dimensions and can grow. Empty searches use the system's no-results presentation. A retained directory failure has a visible retry action using the existing loader.

`SpaceRefreshControl` and `SpaceNotificationControl` share native picker/toggle/retry presentation. Their owners provide the existing bindings and actions. iPhone settings keep a native form with paper/slate row surfaces; Mac settings use scrollable cards for refresh, login/Dock options and notification feedback. The underlying preferences, registration, permissions, polling and directory stores retain their behavior. Device keyboard/VoiceOver and actual iPhone Dynamic Type acceptance remain separate from builds and native layout samples.

## Widget and notification destinations

Opened spaces use the existing status/room cards in a temporary navigation view,
with current observation/attempt times, errors, details, refresh and Done. A short
hint explains that the selected space stays unchanged. The iPhone uses the same
sheet presentation slot as settings, so an incoming target replaces an open
settings sheet instead of competing for a second modal. Mac targets use their own
resizable window; the menu bar and Dock reopen action keep the saved selection.

A requested Mainframe room is outlined and marked selected for accessibility;
when present after loading, the view scrolls to its room card. Data freshness and
unknown handling still come from the store, including in the focused room. The
window/sheet owns its temporary polling lifetime; closing or replacing a target
cancels pending work. Real URL delivery, interaction, room focus and VoiceOver on
installed apps remain part of platform acceptance.
