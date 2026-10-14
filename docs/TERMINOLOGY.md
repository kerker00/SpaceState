# Shared terminology / Gemeinsame Begriffe

This document defines the display vocabulary for SpaceState on Apple and Android,
the website and the CLI. Translations change presentation, never protocol values,
room IDs, JSON keys, executable names or notification localization keys.

## Products

| Name in both languages | Meaning |
| --- | --- |
| SpaceState | Project and Apple app; qualify with macOS or iOS when needed. |
| SpaceState for Android / SpaceState für Android | Android app; its launcher name is SpaceState. |
| SpaceStateCLI | Command-line project; the executable is `spacestate`. |
| SpaceStateKit | Shared Swift package and Android bridge. |
| SpacePush | Status proxy and Apple push service. |
| SpaceAPI | External data standard and directory, not a SpaceState product. |
| Mainframe Oldenburg | The space with additional room support. |

Space names, addresses and messages belong to their publishers and are not translated.
Use “Space” / “Space” and “Rooms” / “Räume” for interface categories.

## Opening status

| Data value | English | Deutsch | Meaning |
| --- | --- | --- | --- |
| `open` | Open | Offen | A current, usable observation reports open. |
| `closed` | Closed | Geschlossen | A current, usable observation reports closed. |
| `unknown` | Unknown | Unbekannt | No usable current opening claim, including missing, expired or failed evidence. |

Unknown is independent of closed. Retained details or the last known value may be
shown with an explicit historical label; they cannot provide a current opening
flag. A report describes the published data, not a guarantee of physical access.
Website status badges use these same labels; conversational copy may use “zu”.
CLI text, JSON and Waybar retain the lowercase English values above in both locales.

## Mainframe room states

| Protocol value | English | Deutsch | Guest-opening classification in Kit |
| --- | --- | --- | --- |
| `closed` | Closed | Geschlossen | closed |
| `keyholder` | Keyholders only | Nur Schlüsselträger | closed |
| `member` | Members only | Nur Mitglieder | closed |
| `open` | Open | Offen | open |
| `open+` | Open+ | Offen+ | open |
| `closing` | Closing soon | Schließt gleich | closed |
| unrecognised | Unknown (original value) | Unbekannt (Originalwert) | unknown |

Restricted states and closing retain their more specific labels. They do not mean
open to guests. “Open+” is the provider's distinct state; do not invent an extra
access promise. The general space observation and the room observations remain
independent. These terms do not change any state mapping or API alias.

Apple push bodies use the same terms, with “Now” / “Jetzt” for open and closed
transitions. Existing `PUSH_STATE_*` keys stay unchanged. The person label is
“Keyholder” / “Schlüsselträger”. SpaceAPI and CLI JSON call the corresponding
contact collection `keymasters`; the CLI's existing “Keymasters” heading remains
the API-oriented name for that collection.

## Mainframe room names

These are the shared Kit display names in **both** languages. Preserve them as
proper room labels in apps, widgets and notification titles; preserve IDs in
subscriptions and APIs. Unknown room IDs retain their original text.

| Room ID | Display name (DE/EN) |
| --- | --- |
| `space` | Space |
| `radstelle` | Radstelle |
| `lab3d` | 3D Lab |
| `machining` | Machining |
| `woodworking` | Woodworking |

## Times and freshness

| English | Deutsch | Meaning |
| --- | --- | --- |
| Changed | Geändert | Provider's state-change time (`since`); not a fresh observation. |
| Observed | Stand | Original successful observation; direct reads use successful receipt. |
| Received | Abgerufen | Successful receipt by this client; does not renew proxy evidence. |
| Last checked | Zuletzt geprüft | Latest client attempt, including a failure. |
| Last known | Letzte bekannte … | Retained historical data; current state is evaluated separately. |
| Snapshot | Momentaufnahme | Historical page/build data, not live evidence. |

The website's “Oldest known observation” / “Ältester bekannter Stand” describes
the oldest observation included in its counts. Page creation has its own label.
The CLI's legacy JSON field `checkedAt` holds the original **observation**, while
`attemptedAt` holds the latest attempt; keep these compatibility names intact.
Expiry and source policy follow the shared observation contract. Neither a retry,
a widget render nor a page rebuild makes old data current.

## Translation changes

Update English and German together, preserving format placeholders and raw values.
Use the tables above when adding labels, notifications or another client. This is
a vocabulary reference; implementation and release planning stay in the local
workspace plan.
