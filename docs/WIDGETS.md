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
  sources: {                        // optional: what the bindings read
    today: { records: 'reminder:', when: 'today', where: { list: 'medicine' } }
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

Optional on `records`: `where: { field: value }` (all must match), `limit` (1–50, default 20).
A reminder item has its record's fields plus `key`, `id`, `at`, `time` ("9:00 AM"), `day` ("Tue"),
`color`, `allDay`. Today is filled for now and for the next midnight, so it rolls over on its own.

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
| symbol | `{ symbol: 'pills.fill', color: 'accent', size: 16 }` | SF Symbol |
| bar / ring / dots | `{ ring: { value: '$today.done', of: '$today.count', label: '…' } }` | progress |
| chart | `{ chart: '$week.values' }` | bars |
| timer | `{ timer: '$today.next.at', style: 'countdown', font: 'number' }` | counts on its own; countdown, relative, time |
| tick | `{ tick: '$item' }` | circle; tap marks the item done |
| button | `{ button: 'Taken', icon: 'checkmark', action: { … } }` | capsule |

Colours: `primary`, `secondary`, `accent` (the tint), red, orange, yellow, green, cyan, blue,
indigo, pink, purple, brown, gray, mint, `#RGB`, `#RRGGBB`.

## Taps

| Action | Does |
|---|---|
| `{ open: true }` | opens the Sidekick (tapping anywhere else does too) |
| `{ tick: '$today.next' }` | marks done: a reminder as the notification's Done, other records get `done: true` |
| `{ increment: 'water:today', field: 'glasses', by: 1 }` | adds to a number (a missing record starts at 0) |
| `{ toggle: 'settings:lamp', field: 'on' }` | flips true/false |
| `{ set: 'water:today', field: 'glasses', value: 0 }` | writes a value |

Taps change only the Sidekick's own records, never `widget:`, `request:` or (except tick)
`reminder:`. They run in the app, so sync and notifications follow at once.

## Limits

150 pieces, 12 deep, 40 children per stack, 8 sources, 200 characters per text, 64 KB per record.
No scrolling, typing, web views or video in any widget (iOS). Smaller limits parked:
`docs/concerns/2026-10-13-glance-widget.md`.

## First user

`sidekicks/care-reminders/index.html`: "Meds today" (medicine list, Taken button, ring, ticks) and
"Next up" (next care reminder with a live relative time).
