# Records: to-do list primitive

Record shapes a to-do Sidekick keeps through `store` (`shell/sdk/midas-store.js`). Each prefix is
declared as a JSON Schema in the manifest's `types`; the shell stamps `$type` and rejects a record
that does not fit. Max 64 KB per record. Written 2026-10-31; updated the same day to match what was built in
`sidekicks/todo/` (`manifest.json` holds the schemas; built code wins over this page). The
prototype (`docs/mockups/todo-primitive-2026-10-31.html`) used `todo:` keys and `repeat` through
a stand-in `store`; the built Sidekick uses the keys and fields below.

A field with no value is left out, never written as `null` (the schemas refuse `null`).

## 1. `reminder:<id>` (one to-do, `$type` `todo.item`)

The key is `reminder:` (founder, 2026-10-31) so the shell's notification engine, the Done button
on a notification and the shell's reminder check work on a to-do as built.

| Field | Type | Meaning |
|---|---|---|
| `title` | string, required | The to-do |
| `notes` | string | Free text |
| `list` | string | `list:` id it belongs to (`inbox` when none) |
| `when` | `YYYY-MM-DD` | Day it is planned for (shows in Today from that day) |
| `part` | `morning` / `afternoon` / `evening` | Part of day (TD-DAY-02) |
| `time` | `HH:MM` | Time of day; with `when`, the to-do notifies (TD-OUT-01) |
| `deadline` | `YYYY-MM-DD` | Due by, separate from `when` |
| `recur` | `{ every: day / weekday / week / month, from: schedule / done }` | TD-ITEM-04. Not the engine's `repeat`, which has no weekday rule and treats a ticked one as repeating |
| `subtasks` | `[{ id, title, done }]` | One level; a ticked subtask stays under its parent |
| `done` | boolean | |
| `completedAt` | ISO time | Set when ticked; kept (logbook) |
| `createdAt` | ISO time | |
| `order` | number | Manual order inside its list (fractional, so an insert between needs one write) |
| `emoji` | string | Optional icon (TD-ROW-04) |
| `color` | `#RRGGBB` | Optional highlight colour (TD-ROW-03) |
| `inToday` | `YYYY-MM-DD` | Fresh-start model only: the day the person picked it for Today |
| `someday` | boolean | Hidden from Today and Upcoming until given a day |
| `deletedAt` | ISO time | In the Trash since then; removed when the page opens 30 days later |
| `externalId` | string | The Apple Reminders id it was imported from; the next import matches on it |
| `nextId` | string | A ticked repeat's next copy, so a second tick (page, voice or notification) never makes another |
| `at`, `timeZone` | ISO time, IANA zone | Engine fields, written by the page only when the to-do has `when` and `time` and is not in the Trash. An untimed to-do has no `at`: the engine accepts it and never notifies (`ReminderRecord.swift`) |
| `alerts`, `reminderType` | | Engine fields; kept as stored |
| `snoozedUntil`, `snoozes`, `lastDoneAt`, `doneThrough` | | Written by the shell from a notification; kept, and the snooze dropped when the time changes |

Repeat: ticking a repeating to-do sets `done`, `completedAt` and `nextId` on it and writes the
next copy as a new `reminder:` with the next `when` (from the schedule, after today; or from the
tick day when `from: done`). A second tick within 2 s of the first does nothing (checklist:
double tick never finishes the next). A repeat ticked from a notification (the shell writes only
`done` and `completedAt`) gets its next copy when the page or a tool next reads it.

## 2. `list:<id>` (`todo.list`)

`{ name, emoji, color, wallpaper, order, externalId }`, `name` required. `wallpaper` is a named
gradient (`ocean`, `sunset`, `forest`, `sand`, `sky`, `graphite`). The Inbox (`inbox`) shows
without a record until it is changed. Deleting a list moves its to-dos to the Trash and asks
first when any are open. `externalId` is the Apple Reminders list id.

## 3. `settings:self` (`todo.settings`, "Make It Yours", TD-SET-01)

Every variation in the blocks is one field here, plus `preset` (`mine`, `paper`, `notebook`,
`soft`, `wallpaper`, `heat`, or `custom` after one option changed). The start, preset "Mine", is
the founder's own selections (2026-10-31): `look` notebook, `theme` auto, `accent` #2F6FEB,
`textSize` m, `density` comfy, `font` system, `checkbox` end, `showMeta` true, `dateColors` true,
`tickSound` chimes, `haptic` true, `celebrate` allDone, `doneGoes` stay, `add` row, `parse` true,
`swipeRight` complete, `swipeLeft` delete, `home` tabs, `todayModel` carry, `dayParts` false. The
table lists every value (the prototype's basic value first).

| Field | Values (basic first) | Block |
|---|---|---|
| `look` | `paper`, `notebook`, `soft`, `wallpaper`, `heat` | TD-LOOK-01 |
| `theme` | `auto`, `light`, `dark` | TD-LOOK-02 |
| `accent` | hex colour, basic `#2F6FEB` | TD-LOOK-03 |
| `textSize` | `m`, `s`, `l`, `xl` | TD-LOOK-04 |
| `density` | `comfy`, `compact` | TD-LOOK-05 |
| `font` | `system`, `serif`, `rounded`, `mono` | TD-LOOK-06 |
| `checkbox` | `circle`, `square`, `end`, `none` | TD-ROW-01 |
| `showMeta` | `true`, `false` | TD-ROW-02 |
| `dateColors` | `true`, `false` | TD-ROW-03 |
| `tickSound` | `ding`, `chimes`, `pop`, `off` | TD-DONE-02 |
| `haptic` | `true`, `false` | TD-DONE-03 |
| `celebrate` | `allDone`, `confetti`, `off` | TD-DONE-04 |
| `doneGoes` | `stay`, `sink`, `hide`, `logbook` | TD-DONE-05 |
| `add` | `fab`, `dragFab`, `bar`, `row` | TD-ADD-01..04 |
| `parse` | `true`, `false` | TD-ADD-05 |
| `swipeRight` | `complete`, `tomorrow`, `delete`, `none` | TD-GEST-01 |
| `swipeLeft` | `delete`, `tomorrow`, `complete`, `none` | TD-GEST-01 |
| `home` | `list`, `tiles`, `tabs` | TD-NAV-01 |
| `todayModel` | `carry`, `stay`, `fresh`, `gated` | TD-DAY-01 |
| `dayParts` | `false`, `true` | TD-DAY-02 |

## 4. Apple Reminders import (TD-SET-04)

The page writes `request:<id>` `{ kind: "import.apple-reminders", status: "pending", createdAt }`;
the shell reads Apple Reminders and writes the export as `import:<id>:<nnnn>` parts (`todo.import`)
and sets the request to `done` (with `prefix`), `denied`, `cancelled` or `failed`. The page joins
the parts, writes lists and to-dos matched on `externalId` (imported, updated or up to date; a
repeat the page does not offer is counted as not imported), then deletes the parts and the
request.

## 5. Not mapped yet

- A widget: the shell's `reminder:` Today source lists only records with `at` today, so untimed
  and carried-over to-dos would not show. Needs a new source (shell work).
- Haptics: no page API; the page toggles a hidden `<input type="checkbox" switch>` (TD-DONE-03).
