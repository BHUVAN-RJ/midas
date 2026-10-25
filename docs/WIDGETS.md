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
  tint: '#9CAF88',                  // optional: accent for symbols, rings, buttons, ticks
  background: { light: '#F4EEE3', dark: '#0F2229' },  // optional: the widget's own colour
                                    // (one colour, or one per mode); default white / #1C1C1E
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
`color`, `allDay`. An hourly reminder (`everyHours`) appears once per time (each time carrying its own
`snoozedUntil` from the item's `snoozes["@HHMM"]`), as `reminder:<id>@HHMM`
items, so every dose counts; a tick on one marks that time done on the item (`slotsDone`). Today is
filled for now and for the next midnight, so it rolls over on its own.

## Bindings

`"$today.next.title"`: a source, then fields; `.0` for a position, `.count` of a list. Inside words:
`"$today.open left"`. In a `list` row, `$item` is the row's item. A missing value is empty.
Any piece takes `if: '$binding'` or `unless: '$binding'` (empty, 0, false, null and [] count as no).

## Pieces

| Piece | Write | Draws |
|---|---|---|
| vstack / hstack | `{ vstack: [ … ], spacing: 6, align: 'leading' }` | column / row |
| grid | `{ grid: [ … ], columns: 3 }` | rows of N |
| list | `{ list: '$today.items', limit: 3, row: { … }, empty: 'All done' }` | one row per item |
| spacer, divider | `{ spacer: true }` | space / line |
| text | `{ text: '$today.open left', style: 'headline', color: 'secondary', lines: 2 }` | words; styles title, headline, body, caption, number |
| text, amounts | `{ text: '$water.ml of $settings.goalMl', format: 'l' }` | numbers read as ml: `ml` "1,250 ml", `l` "1.25 L", `oz` "42 oz" |
| symbol | `{ symbol: 'pills.fill', color: 'accent', size: 16 }` | SF Symbol |
| bar / ring / dots | `{ ring: { value: '$today.done', of: '$today.count', label: '…' } }` | progress |
| chart | `{ chart: '$week.values' }` | bars |
| timer | `{ timer: '$today.next.at', style: 'countdown', font: 'number' }` | counts on its own; countdown, relative, time |
| tick | `{ tick: '$item' }` | circle; tap marks the item done |
| button | `{ button: 'Taken', icon: 'checkmark', action: { … } }` | capsule |
| fill | `{ fill: { value: '$water.ml', of: '$settings.goalMl' }, color: { light: '#9CCFD3', dark: '#2E6E77' }, edge: 'wave', content: { vstack: [ … ] } }` | a colour rising from the bottom to value/of (0 to 100%, never past), a still wave on top (`edge: 'flat'` for none), `content` drawn over it; as a size's whole look it fills the widget edge to edge |

Colours: `primary`, `secondary`, `accent` (the tint), red, orange, yellow, green, cyan, blue,
indigo, pink, purple, brown, gray, mint, `#RGB`, `#RRGGBB`. A fill's `color` and the widget's
`background` also take `{ light, dark }`, one colour each. Widgets do not animate on iOS: the wave
is still. Drawn: `docs/mockups/hydration-widget-render-{light,dark}-2026-10-25.png`.

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
`reminder:`. They run in the app through the shell's one record writer (`RecordWriter`: a patch,
checked against the record's type; unknown fields kept), so sync and notifications follow at once.
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

## First user

`sidekicks/care-reminders/index.html`: "Meds today" (medicine list, Taken button, ring, ticks) and
"Next up" (next care reminder with a live relative time).
