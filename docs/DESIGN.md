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

The prominent iPhone status card uses the filled surface without an extra outline inside the grouped list's rounded clipping. Its status word, symbol, spacing and semantic colors remain the same for open, closed and unknown states. Mac status cards and other card types retain their outlines.

The main iPhone status screen shows one observation date as a centered closing row with a small decorative clock, wrapping Dynamic Type footnote text and stable numeral widths. The compact row has more space above than below it, placing the date closer to the lower safe area. An inset hairline and the card surface separate this quiet footer from the list, without a button shape or outline. It uses the displayed data's original observation time and omits the separate client-attempt date. Missing observation evidence does not produce a substitute date.

## Widgets

Widgets use the same localized status titles, symbols and semantic colors as the app. In full-color presentation, their removable container surface uses paper/slate and the app's contrast-aware foreground roles. In accented or vibrant presentation, foreground roles and accent groups defer to WidgetKit; the custom background is clear. The system still owns container margins, corners and rendering.

Small widgets prioritize the space name and status word/symbol. Observation time has priority over the optional state-change time when space is tight; unknown states do not show a change time. Medium widgets add room names and localized state words with distinct symbols, and fit up to five, three or one room according to available height. Missing room data stays visibly separate from the space's state. Long names may truncate visually but retain their complete accessibility labels; supporting metadata yields space before the main status does.

Lock Screen layouts are separate: circular widgets show a status symbol and short status word, inline widgets put the status before the space name, and rectangular widgets include the name, status and observation. Circular/inline accessibility labels contain the complete space name and a localized status value; other layouts combine related labels and hide decorative symbols from VoiceOver.

`SpaceStatusView` reads the actual WidgetKit environment and passes its presentation inputs to `SpaceWidgetContent`. The provider and C-01 observation/expiry timeline remain responsible for deciding the effective states. Native layout samples can verify appearance and fitting; actual WidgetKit tinting, accessibility font scaling and VoiceOver on devices require platform acceptance. Widget/notification navigation is tracked separately from appearance.

## Sensors

The shared `SpaceSensorPresentation` selects one reading per climate/visitor kind
for the status card beneath the rooms. Details show every supported typed reading,
including location, sensor name, description and original value-change time.
Provider metadata remains plain text; numeric formatting follows the view locale
and units are preserved without inference or conversion. Missing/invalid rows are
hidden, visitor counters are never summed, and visitor-name lists are not shown.
Generic sensor JSON is not interpreted as app measurements.

The card uses the shared surface/palette, labelled symbols, wrapping metadata and
stacked labels/values when a horizontal row does not fit. Related values combine
for accessibility; icons are decorative. Retained rows are labelled and dimmed
when document evidence is stale, missing or failed. An explicit timeline updates
this label at document expiry without changing observation or sensor times. The
Mac panel can scroll when its cards exceed the available capped height.

Medium/large widgets use first-fit footers with at most visitors and temperature,
including their location/name. Observation time is retained before optional
sensor rows; small and Lock Screen layouts do not add sensors. Sensor data is
removed in the existing space-expiry entry, independently of room expiry. App
reloads compare only displayed widget values/unit/place, not hidden metadata or
value-change dates. Real Dynamic Type, VoiceOver, tinting and widget fitting are
separate platform acceptance.

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

## Projects, links and linked spaces

Details omit empty project/link/linked-space cards. Provider names, descriptions and complete URLs remain plain, wrapping text with the shared card typography. Duplicate provider entries retain distinct stable row identities. Projects and named links use native external links only after HTTP(S) endpoint validation; unsupported or invalid values remain selectable text.

Linked spaces distinguish an internal “Space status” button from their external website link. Only a valid API endpoint can open a status view; a website is never substituted. Each detail view owns its temporary navigation sheet, preserving the source view and saved selection/subscriptions. The shared target view cancels work on dismissal and suspends iPhone polling outside the active scene, including targets opened from another target. Installed-device sheet, keyboard, VoiceOver and long-text acceptance remains separate from compilation and model/store regression coverage.

## Mac window sizing

The menu-bar panel measures its cards at a consistent 380-point width. Short content uses its natural height; long content scrolls within a viewport bounded by the current display. The action bar remains below the scroll area so refresh, details, settings and quit stay reachable.

Regular detail windows initially fit the measured content, with a smaller minimum height and a screen-bounded maximum. Settings fit the general tab's cards; the searchable space list keeps a useful viewport. Automatic fitting stops after a manual window resize, preserving the user's chosen size. Temporary-target windows start compact and remain resizable. No saved preferences are deleted to adjust window geometry.
