# Sidekick widgets

How a Sidekick puts itself on the Home Screen. Built 2026-10-13 (founder: "Approve. You can start
building"; plan https://claude.ai/artifact/UXKbkcZ4wkFUagH26rFd8m,
`docs/mockups/sidekick-widget-plan-2026-10-13.html`). Shell code: `shell/Shared/SidekickWidget*.swift`,
`shell/Midas/SidekickWidget*.swift`, `shell/MidasWidgets/SidekickWidget.swift`.

```
Sidekick page                 phone                         Home Screen
store.set('widget:meds', …) → record store ⇄ account sync → shell fills $bindings → widget draws pieces
                                    ↑                                               │
                                    └──────── tap (Taken, +, toggle) changes a record ┘
```

- One gallery entry, **Sidekick**. Place it any number of times, any size; each copy picks a
  Sidekick, then one of its widgets (with one widget, the second pick can stay empty).
- A Sidekick can have several widgets: one record per widget, `widget:<name>`.
- No build, no upload: the description is a record like any other and syncs with the account.
  A new Sidekick or a new layout made of the pieces below needs no new app build. A new piece,
  a new tap or a new size needs one.
- A piece has one piece name; its other fields are settings, never piece names (a button's
  symbol is `icon`, a timer's text size is `font`).
- The shell checks the description when the page writes it; a broken one is refused with the
  reason (`store.set` rejects). A piece the shell does not know is skipped.
- Sizes: small, medium, large. A size left out draws the nearest one given. Lock Screen: later.

## The record

```js
await store.set('widget:meds', {
  version: 1,                       // anything extra is kept; the page uses it to skip rewrites
  name: 'Meds today',               // shown in the widget's settings, 1–40 characters
  tint: '#9CAF88',                  // optional: accent for symbols, rings, buttons, ticks (one
                                    // colour; its dark one is derived, give pieces pairs instead)
  background: { light: '#F4EEE3', dark: '#0F2229' },  // optional: the widget's own colour
                                    // (one per mode); default white / #1C1C1E
  sources: {                        // optional: what the bindings read
    today: { records: 'reminder:', when: 'today', where: { $type: 'care.item', list: 'medicine' } }
  },
  small:  { vstack: [ … ] },        // at least one of small, medium, large
  medium: { … },
  large:  { … }
});
```

## Sources

| Source | Gives |
|---|---|
| `{ records: 'reminder:', when: 'today' }` | `items` (open, by time), `open`, `done` (done today), `count` (open + done), `next` |
| `{ records: 'reminder:', when: 'upcoming' }` | `items` (each at its next time), `count`, `next` |
| `{ records: 'reminder:', when: 'planned', model: 'carry' }` | `items` (open, planned by day, in `order`), `open`, `done` (ticked today), `count`, `next`; see To-Do additions |
| `{ records: 'water:', sum: 'glasses' }` | `items`, `count`, `next`, `sum`, `values` (for a chart) |
| `{ record: 'water:today' }` | that record's fields, and `key` |
| `{ record: 'water:{today}' }` | today's record (`water:2026-10-25`); see Day keys |
| `{ records: 'water:', streak: { field: 'ml', goal: '$settings.goalMl', dayGoalField: 'goalMl' } }` | `days`: days in a row, back from today, whose `ml` met the goal |

A streak reads records keyed by day (`<prefix>YYYY-MM-DD`). A day counts when its `field` is at or
over its own `dayGoalField` (when it has one; a goal changed mid-week leaves earlier days as they
were), else `goal` (a number, or a binding to another source). Today counts once it is met; an
unmet today does not break the streak until it is over; a day with no record does. No goal: 0.
`streak` cannot be used with `when`.

### Day keys

`{today}` in a source's `record` key or in a tap's key is the phone's local date, `YYYY-MM-DD`
(Gregorian, whatever calendar the phone shows). The midnight look reads the new day, so a day's
total starts again at midnight without the Sidekick being opened. A tap resolves `{today}` when
it was tapped: a 23:59 tap the app writes at 00:05 still lands on the old day. An increment on a
day with no record makes one (`$type` stamped), so a day type should require only the counted
field.

Optional on `records`: `where: { field: value }` (all must match; select a type with
`where: { $type: 'care.item' }`), `limit` (1–50, default 20). With `sum`, a given `limit` keeps
the most recent N records by key, oldest first, for `items`, `count`, `sum` and `values`
(`{ records: 'water:', sum: 'ml', limit: 7 }` is the last 7 days); without `limit` the sum is
over every record.
A reminder item has its record's fields plus `key`, `id`, `at`, `time` ("9:00 AM"), `day` ("Tue"),
`color`, `allDay`, `late` (true once its time has passed today; never all day; Today's items are
open ones, so never done). An hourly reminder (`everyHours`) appears once per time (each time carrying its own
`snoozedUntil` from the item's `snoozes["@HHMM"]`), as `reminder:<id>@HHMM`
items, so every dose counts; a tick on one marks that time done on the item (`slotsDone`). Every
widget is filled for now and for the next midnight, so it rolls over on its own; a widget with a
`when: 'today'` source is also filled at each of today's reminder times still to come, so an item
turns `late` without the app running. Cap: the next 24 times today (an hourly reminder all day);
timeline entries do not count against WidgetKit's daily reload budget (about 40 to 70 reloads),
the cap keeps the shared file small. Times past the 24th turn late at the next reload (the app
coming to the front, a record change, the background refresh).

## Bindings

`"$today.next.title"`: a source, then fields; `.0` for a position, `.count` of a list. Inside words:
`"$today.open left"`. In a `list` row, `$item` is the row's item. A missing value is empty.
Any piece takes `if: '$binding'` or `unless: '$binding'` (empty, 0, false, null and [] count as no).

## Pieces

| Piece | Write | Draws |
|---|---|---|
| vstack / hstack | `{ vstack: [ … ], spacing: 6, align: 'leading' }` | column / row |
| grid | `{ grid: [ … ], columns: 3 }` | rows of N |
| list | `{ list: '$today.items', limit: 3, row: { … }, empty: 'All done', more: '+$more more' }` | one row per item; `more` under the rows when items did not fit, `$more` how many (caption, grey) |
| spacer, divider | `{ spacer: true }` | space / line |
| text | `{ text: '$today.open left', style: 'headline', color: 'secondary', lines: 2 }` | words; styles title, headline, body, caption, number |
| text, amounts | `{ text: '$water.ml of $settings.goalMl', format: 'l' }` | numbers read as ml: `ml` "1,250 ml", `l` "1.25 L", `oz` "42 oz" |
| symbol | `{ symbol: 'pills.fill', color: 'accent', size: 16 }` | SF Symbol |
| bar / ring / dots | `{ ring: { value: '$today.done', of: '$today.count', label: '…' } }` | progress |
| chart | `{ chart: '$week.values' }` | bars |
| timer | `{ timer: '$today.next.at', style: 'countdown', font: 'number' }` | counts on its own; countdown, relative, time |
| tick | `{ tick: '$item' }` | circle; tap marks the item done |
| button | `{ button: 'Taken', icon: 'checkmark', action: { … } }` | capsule |
| fill | `{ fill: { value: '$water.ml', of: '$settings.goalMl' }, color: { light: '#9CCFD3', dark: '#2E6E77' }, edge: 'wave', content: { vstack: [ … ] } }` | a colour rising from the bottom to value/of (0 to 100%, never past), a still wave on top (`edge: 'flat'` for none), `content` drawn over it; as a size's whole look it fills the widget edge to edge; `floor: 0.1` keeps that share of the height filled at 0 and still reaches the top at `of` (0 to 0.5; Water's low tide at 0 L, founder 2026-10-31; builds before 22 ignore it) |

Colours: `primary`, `secondary`, `accent` (the tint), red, orange, yellow, green, cyan, blue,
indigo, pink, purple, brown, gray, mint, `#RRGGBB`, `#RGB`. Every colour (any piece's `color`, the
widget's `background`) also takes `{ light, dark }`, one colour each, drawn by the phone's
appearance; see Light and dark. Any piece's `color` (not `tint`) can
also be a choice: `{ if: '$item.late', then: 'red', else: 'secondary' }` draws `then` when the
binding is present (as `if` on a piece), else `else` (without `else`, the piece's own default);
`then` and `else` may be pairs. Widgets do not animate on iOS: the wave
is still. Drawn: `docs/mockups/hydration-widget-render-{light,dark}-2026-10-25.png`.

## Light and dark (founder, 2026-10-27)

**Rule for every new or repaired widget: give light and dark.** Every explicit colour is a
`{ light, dark }` pair: `background`, a fill's `color`, text, symbol, button, chart, bar, ring,
dots, tick, timer, and the `then` / `else` of a colour choice. Dark is the Sidekick's own night
look (its `@media (prefers-color-scheme: dark)` colours), never purple. Leave text `primary` /
`secondary` (or without a colour) only when the widget has no background or fill of its own.

```js
background: { light: '#F4EEE3', dark: '#0E1A1E' },
small: { fill: { value: '$day.ml', of: '$settings.goalMl' },
         color: { light: '#9CCFD3', dark: '#2A6970' }, edge: 'wave',
         content: { vstack: [
           { text: '$day.ml', format: 'l', style: 'title', color: { light: '#24343A', dark: '#E3EEEF' } },
           { button: '+250 ml', color: { light: '#2F7E87', dark: '#5FB3BA' },
             action: { increment: 'water:{today}', field: 'ml', by: 250 } } ] } }
```

What the shell does (so no widget can draw white on light):

- Text and symbols that are `primary`, `secondary` or without a colour, over the widget's own
  background or a fill's sea, get an ink chosen for what is behind them in each mode: dark ink on
  light, light ink on dark, by luminance; `secondary` is the same ink, faded only as far as it
  still reads (contrast 4.5). Over the system background the system colours stay.
- A single colour from an older page still draws: in dark mode the shell derives one. A
  background or fill keeps its hue and goes dark; text, symbols, buttons, charts and ticks are
  kept when they read over what is behind them, else lightened (same hue) until they do. The
  tint is always one colour and is derived the same way.
- A button's label is white, or dark ink on a light button (Water's night `#5FB3BA`).
- The checker does not refuse a single colour: widgets already on phones keep working.

Older builds: a build before 2026-10-27 refuses `{ light, dark }` anywhere but `background` and a
fill's `color` ("color must be a name or #RRGGBB"). A page writes, in order, its light-and-dark
widget, the same widget with pairs only on `background` and the fill (builds from 2026-10-25), and
its plain stand-in, each when the one before is refused (`fallback` and `plain` in Water's and
Reminders' `widgetRecords`). Shell code: `shell/Shared/SidekickWidgetInk.swift` (the ink, the
derived colours, contrast), `SidekickWidgetViews.swift` (`WidgetSurfaceColors` in the
environment), `SidekickWidgetFiller.swift` (`resolvedColors`), `SidekickWidgetDescription.swift`
(`colorError`). Checks: `SidekickWidgetLightDarkTests`. Drawn:
`docs/mockups/widget-dark-{light,dark}-2026-10-27.png`.

## Taps

| Action | Does |
|---|---|
| `{ open: true }` | opens the Sidekick (tapping anywhere else does too) |
| `{ tick: '$today.next' }` | marks done: a reminder as the notification's Done, other records get `done: true` |
| `{ increment: 'water:today', field: 'glasses', by: 1 }` | adds to a number (a missing record starts at 0) |
| `{ increment: 'water:{today}', field: 'ml', by: 250 }` | the same on the day it was tapped (Day keys) |
| `{ toggle: 'settings:lamp', field: 'on' }` | flips true/false |
| `{ set: 'water:today', field: 'glasses', value: 0 }` | writes a value |

Taps change only the Sidekick's own records, never `widget:`, `request:` or (except tick)
`reminder:`.

A tap runs in the widget extension (founder, 2026-10-27, build 21): `SidekickWidgetActionIntent` is a
plain `AppIntent`, so iOS performs it there instead of first launching Midas in the background. It
queues the tap (`widget-sidekick-actions.json`, with `tappedAt`) and reloads the widget, which
redraws from the tap preview (`SidekickWidgetTapPreview`). The app writes the queue to the records
through the shell's one record writer (`RecordWriter`: a patch, checked against the record's
type; unknown fields kept) when it next runs: launch, coming to the front, a record change,
background refresh. Sync and notifications follow then; a listening reminder's quiet starts at
`tappedAt`, not when the app got to it (`NotificationEngine.noteWrites(tappedAt:)`). Until the app
runs, a reminder can still fire inside that quiet or after the goal the tap reached.
A `widget:` record is itself typed (`midas.widget`, shell/sdk/shell-types.js) and checked on write.

## Limits

150 pieces, 12 deep, 40 children per stack, 8 sources, 200 characters per text, 64 KB per record.
A fill's `content` counts toward the pieces and the depth like any child.
No scrolling, typing, web views or video in any widget (iOS). Smaller limits parked:
`docs/concerns/2026-10-13-glance-widget.md`.

## Hydration additions (founder, 2026-10-25)

Day keys, `format`, the streak source, `fill` and `background` were added for the Water Sidekick
(`docs/briefs/hydration-sidekick.md` 2.1, W1 to W4). They need the app build that has them. An
older build skips `fill` (unknown piece), ignores `background`, `format` and `streak` (no `days`),
reads `{today}` as a literal key, and refuses a description whose `color` is `{ light, dark }`
("is not a colour name or #RRGGBB"). A page that must work on older builds writes a plain
fallback widget when `store.set` is refused. Shell code: `SidekickWidgetShared.swift` (`SidekickWidgetDayKey`, `WidgetFillPiece`,
`WidgetBackgroundPiece`), `SidekickWidgetViews.swift` (the views, in Shared so tests can draw them),
`SidekickWidgetFiller.swift`, `SidekickWidgetDescription.swift`. Checks:
`SidekickWidgetDayKeyTests`, `SidekickWidgetUnitFormatTests`, `SidekickWidgetStreakTests`,
`SidekickWidgetFillPieceTests`, `SidekickWidgetSumLimitTests`.

## Reminders additions (founder, 2026-10-26)

`late` on reminder items with a look at each time, the colour choice and the list's `more` were
added so the Reminders Sidekick could make its own widget (founder: "Since now each sidekick can
create its own widget, shouldn't we just use that?"; approved "+N more" instead of page arrows).
The separate native Reminders widget was removed; the gallery lists Sidekick and Sidekicks only. A reminder tick waiting for the app now shows at once too: the
widget applies the Done patch the app will write (`ReminderChange`, compiled into the widget
extension), hourly times and early alerts included. An older build refuses a colour choice
("color must be a name or #RRGGBB"), ignores `more` and has no `late`; the Reminders page then
writes its plain stand-in (grey times). Shell code: `SidekickWidgetFiller.swift`
(`maximumLateLooks`, `lateMoments`, `chosenColor`), `SidekickWidgetDescription.swift`
(`colorError`), `SidekickWidgetTapPreview.swift` (`SidekickWidgetTapPatch.patch`). The page's
widget: `RemindersWidget` in `sidekicks/reminders/index.html`.

```js
small: { vstack: [
  { hstack: [ { text: 'Today', style: 'headline', color: { light: '#007AFF', dark: '#0A84FF' } }, { spacer: true },
              { text: '$today.open', style: 'headline', color: { light: '#007AFF', dark: '#0A84FF' } } ] },
  { list: '$today.items', limit: 3, empty: 'All done', more: '+$more more', row: { hstack: [
      { tick: '$item', size: 14 },
      { vstack: [ { text: '$item.title', style: 'caption' },
                  { text: '$item.time', style: 'caption', if: '$item.time',
                    color: { if: '$item.late', then: { light: '#FF3B30', dark: '#FF453A' }, else: 'secondary' } } ] } ] } },
  { spacer: true } ] }
```

## To-Do additions (founder, 2026-11-02)

`when: 'planned'` lists records by their day, as a to-do list's Today does (CONCERNS 25: `today`
lists only reminders with a time today, so untimed and carried-over to-dos were missing). It reads
the record fields `when` (YYYY-MM-DD), `time` (HH:MM), `done`, `completedAt`, `someday`,
`deletedAt`, `inToday` and `order`, on any prefix. `model` (optional, only with `planned`) is the
list's Today model: `carry` (default), `stay` and `gated` take every item planned for today or an
earlier day; `fresh` takes only items whose `inToday` is today. Someday and Trash items never
show. Items are the open ones, lowest `order` first; each adds `key`, `id`, `time` ("5:00 PM",
empty without one), `day` ("Sat", the planned day when it is before today, else empty) and `late`
(planned before today). `done` counts items ticked today (`completedAt`). The midnight look reads
the new day, so today's open ones carry over without the app. A tick on a `reminder:` item is the
reminder Done (`done`, `completedAt` at the tap time); a repeat's next copy is made by the page
when it next opens. Needs build 22; an older build refuses it ("when must be today or upcoming").
Shell code: `plannedValue` in `SidekickWidgetFiller.swift`, the checker in
`SidekickWidgetDescription.swift`. Checks: `SidekickWidgetPlannedDayTests`,
`SidekickWidgetToDoRenderTests`. The page's widget: `TodoWidget` in `sidekicks/todo/index.html`.

## Add to Home Screen (founder, 2026-10-26)

iOS has no way for an app to place a widget, so the shell shows the steps: a native sheet plays
touch and hold, Edit, Add Widget, Midas, Add Widget, with this Sidekick's own small widget landing on
the Home Screen (`docs/mockups/widget-howto-demo-2026-10-25.html`; Reduce Motion: the steps as a
numbered list). The widget it shows is the asking Sidekick's real one; a new Sidekick widget already
shows the last Sidekick opened, so there is no "pick the Sidekick" step.

**Rule for every Sidekick that writes `widget:` records:** (founder, 2026-10-27; option A of
`docs/mockups/water-add-widget-entry-2026-10-27.html`) its main screen's bottom bar has a
"Widget" button (four squares and the word, in the Sidekick's own style) next to the others,
shown **only until one of its widgets is on the Home Screen**. When it is hidden the other buttons
close up and centre, no gap. It replaces the "Add to Home Screen" row in Settings (2026-10-26),
which is gone. The button writes this request:

```js
await store.set('request:' + id, {
  kind: 'home-screen.widget',   // the shell shows the sheet for the Sidekick that wrote it
  widget: 'sidekick',           // the Sidekick widget ('folder' is the Sidekicks folder; no entry point yet)
  status: 'pending',
  createdAt: new Date().toISOString()
});
// The shell marks it { status: 'done' } at once (or 'failed' for a widget it does not know);
// read it back and delete it when it is no longer 'pending'.
```

Show the button only when the app build has the sheet and says no widget of this Sidekick is
placed. Both questions are POSTs to `location.origin + '/_midas/store'` (the store's own endpoint;
`store` has no call for them):

1. On open, `{ op: 'shell' }`. A build with the sheet answers
   `{ ok: true, requests: [..., 'home-screen.widget'] }`; an older one answers
   `{ ok: false, error: 'unknown op shell' }`, and marks the request itself failed ("unknown
   request") without showing anything. No `'home-screen.widget'`: no button.
2. On open and every time the page is back on screen (`visibilitychange`, so coming back from the
   Home Screen after adding the widget hides it), `{ op: 'widget-placed' }`. The shell answers
   `{ ok: true, placed: true | false }`: true when a Sidekick widget on the Home Screen shows this
   Sidekick (its settings pick this Sidekick or one of its widgets, or pick nothing while this is
   the last Sidekick opened). The Sidekicks folder widget does not count. A build before
   2026-10-27 answers `'unknown op widget-placed'`: no button.

```js
const requestOptions = {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ op: 'widget-placed' })
};
const response = await fetch(location.origin + '/_midas/store', requestOptions);
const reply = await response.json();
const showButton = hasSheet && reply.ok && reply.placed === false;
```

The button is in the page, not a tool: it shows the person something on their own screen, so
the agent block and `tools.js` do not change for it.

Shell code: `shell/Midas/HomeScreenWidgetSheet.swift` (`HomeScreenWidgetCenter`,
`ShellRequestDispatch`, the timeline), `HomeScreenWidgetSheetView.swift`,
`HomeScreenWidgetPlacement.swift` (`widget-placed`: WidgetKit's current configurations behind
`PlacedSidekickWidgetsSource`), `{ op: 'shell' }` and `{ op: 'widget-placed' }` in
`SidekickStoreChannel.swift`. First user: Water (`requestHomeScreenTask`, `shellSaysWidgetPlaced`
in `sidekicks/hydration/index.html`).

The sheet's demo follows the gallery: Sidekicks (the folder, small only) is first since
2026-10-27, so the Sidekick widget's demo swipes past that one page; the folder's has no swipe.

## First user

`sidekicks/care-reminders/index.html`: "Meds today" (medicine list, Taken button, ring, ticks) and
"Next up" (next care reminder with a live relative time).
