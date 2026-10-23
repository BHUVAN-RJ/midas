# Date navigation (DP-NAV)

The navigation block is how a planner page moves between dates and scales: the week strip, the
pull-down to a bigger view, week and month views, the heat map, the DayTicker, zoom, and the way
back to today. It holds all 8 DP-NAV patterns from research `ANALYSIS.md` section 3.3. Sizes are
in pt (1 CSS px in the Sidekick's WKWebView). Colours are theme tokens (CSS custom properties,
defined in `recipe.md`); the value in brackets is the Structured preset value from
`structured-ui-teardown.md`. "Checklist N" is item N of `checklist.md` (the numbering of research
`ANALYSIS.md` section 6). Screenshot paths are relative to the shots folder named in
`ANALYSIS.md` section 8. Structured's glass menus and sheets are native iOS views; in a Sidekick
the page draws its own (CSS `backdrop-filter` for the glass look). Tests assume a fixed clock and
a seeded store.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-NAV-01 | Week strip with day dots | core | Structured strip with mini bubbles |
| DP-NAV-02 | Pull down for the bigger view | on request | Structured drag down to week, from the grabber |
| DP-NAV-03 | Week view shapes | core | Structured seven icon-only columns |
| DP-NAV-04 | Month view shapes | core | Structured month sheet with dots |
| DP-NAV-05 | Busyness heat map | on request | Timepage Heat Map |
| DP-NAV-06 | DayTicker | on request | Fantastical DayTicker |
| DP-NAV-07 | Zoom and pinch between scales | on request | Timepage pinch 7 / 3 / 1 days |
| DP-NAV-08 | Jump to today | core | Structured long-press month plus "Today" pill |

---

### DP-NAV-01 Week strip with day dots

**Tag:** core (checklist 17 names it). **Variations:** A, Structured: stacks of tiny coloured
bubbles with icons under each date (Full layout only); today in accent, selected in black. B,
NotePlan: dots plus "CW 4". C, TickTick: a blue dot. D, Tiimo, Routine, Akiflow, Routinery,
Apple: plain strips. E, Todoist Upcoming week picker. F, Readdle: strip at the bottom (until Sep
2026).
**Default variation:** A, Structured.

**What it is.** Seven dates above the day. Small marks under each date show which days hold
items and in what colours.

**Anatomy.**
- Sits on `--bg-header` (#F2F2F5) under the date header, 16 pt side margins, seven equal columns.
- Weekday: 13 pt regular `--ink-2` (#8A8A8E), short form ("Mon").
- Date: 17 pt semibold, centred in a 34 pt circle.
  - Selected and today: circle `--accent` (#F49F99), number white.
  - Selected, not today: circle `--ink` (#000000), number white.
  - Today, not selected: no circle, number `--accent`.
  - Other: no circle, number `--ink`.
- Dots (Full layout only, DP-SET-04): up to 5 mini bubbles, 12 pt, overlapping by 4 pt, in the
  colours of that day's tasks in start order, each with a 7 pt white glyph. Done and undone both
  count.
- Strip height 72 pt with dots, 56 pt without.

**States.** No tasks on a day: no dots. More than 5: the first 5. Simplified and Minimal layouts:
no dots.

**Interactions.**
- Tap a date: shows that day (the timeline cross-fades, 150 ms).
- Swipe the strip horizontally: previous or next week (slide, 250 ms ease-out); the selected
  weekday stays the same.
- Long press a date: the whole-day menu (DP-RES-07, `rescheduling.md`).
- During a drag of a task (DP-RES-01), hovering a date for 500 ms switches to that day.

**Words.** Weekday short names from `Intl.DateTimeFormat` (`weekday: 'short'`) in the page's
locale.

**Data.** Reads `task:<id>` (day, colour, icon, repeat) for the seven days,
`exception:<taskId>:<date>`, `settings:planner` (week start, layout).

**Needs.** Page alone.

**Edge cases.**
- Checklist 17: the week starts on the day in `settings:planner`. The page cannot read the iOS
  first-weekday setting [U]; its default comes from the locale (`Intl.Locale` week info, where
  WebKit supports it [U]), else Monday.
- Checklist 26: a task crossing midnight puts a dot on both days.
- A repeat occurrence skipped by an exception adds no dot.

**Tests.**
- Given week start Monday, when the strip renders, then the first column is "Mon"; given Sunday,
  then "Sun".
- Given 12 Oct is today and 14 Oct is selected, then 14 has a `--ink` filled circle and 12 has
  `--accent` text and no circle.
- Given 3 tasks on 14 Oct in colours `--palette-2`, `--palette-5`, `--palette-7`, then 3 dots
  render under 14 in that order.
- Given the Simplified layout, then no dots render.
- Given a swipe left on the strip with Wednesday selected, then the next week's Wednesday is
  selected.

**Evidence.** DP-NAV-01 [C]. Loves: no direct praise. Complaints: Readdle users when the strip was
replaced (2 quotes, C, D). Teardown 1.1 "Week strip". Screenshots: `agent/lazyweb/lw_home.png`,
`d/ticktick/appstore_2.png`.

---

### DP-NAV-02 Pull down for the bigger view

**Tag:** on request (no checklist item or leave reason names it; checklist 46 is met by DP-NAV-03
and DP-NAV-04 through other entries). **Variations:** A, Structured: drag the timeline sheet down
to the week view; from the grabber only before 4.3, from anywhere since 4.3. B, Fantastical:
pull the DayTicker down to a month grid, then full screen.
**Default variation:** A, Structured, from the grabber and the top 24 pt of the sheet only (the
pre-4.3 behaviour; the 4.3 "anywhere" change drew an accidental-pull complaint).

**What it is.** Dragging the day down reveals the week view behind it.

**Anatomy.** The grabber (36 x 5 pt) at the top of the timeline sheet. While dragging, the sheet
moves with the finger and the week view (DP-NAV-03) shows above it.

**States.** Day: sheet up. Dragging: sheet follows, 1:1. Week: sheet down, week view shown.

**Interactions.**
- Drag down from the grabber zone more than 80 pt and release: the week view opens (spring,
  300 ms).
- Less than 80 pt: the sheet snaps back.
- In the week view, drag up: back to the day.
- A drag that starts inside the timeline scrolls the timeline; it never opens the week.
- The page sets `overscroll-behavior: none` so the WKWebView's own bounce does not compete.

**Words.** None.

**Data.** None.

**Needs.** Page alone.

**Edge cases.** None from the checklist. The Structured complaint (2025-10-14) is accidental pulls
while scrolling; the grabber-only zone prevents them.

**Tests.**
- Given the timeline scrolled to 300 pt, when a downward drag starts at the timeline's middle,
  then the timeline scrolls and the week view does not open.
- Given a drag from the grabber of 100 pt, when released, then the week view is shown.
- Given a drag from the grabber of 40 pt, when released, then the day view is shown.

**Evidence.** DP-NAV-02 [C]. Loves: none direct. Complaints: Structured accidental pulls
(2025-10-14, E). Teardown 0 (4.3 row), 1.2. Screenshots: `agent/help/3561154_2.png`,
`c/fantastical/hires_0.png`.

---

### DP-NAV-03 Week view shapes

**Tag:** core (checklist 46 names it). **Variations:** A, Structured: seven narrow icon-only
columns on a time axis, with energy and cycle rows above. B, Readdle: days as horizontal rows. C,
Apple: week in landscape only. D, Todoist: 3-day in portrait, week in landscape. E, Morgen:
work-week only. F, TickTick: 3-Day and Week. G, Notion: none.
**Default variation:** A, Structured.

**What it is.** Seven days side by side on a phone in portrait, each a thin column of icon
bubbles at their times.

**Anatomy.**
- Same header and week strip as the day view (DP-NAV-01).
- Above the grid: an all-day row per day (glyph only, 20 pt circles), and an energy pill per day
  when DP-TIME-06 variation E is on ("19 25", `--danger` when over).
- Gutter 36 pt, hour labels 11 pt `--ink-2` ("7 AM").
- Seven columns across the rest of the width (about 49 pt each on a 402 pt screen).
- Bubbles 24 pt wide, centred in the column, height proportional (40 pt per hour), joined by a
  2 pt line in the task colour. Glyph 14 pt.
- Past days: bubbles filled in the task colour, white glyph. Future: `--bubble-future`
  (#EBEBEB) with a coloured glyph. Today: as the day view (DP-TIME-02 fill).

**States.** Empty day column: blank. Many tasks: the grid scrolls vertically. Overlaps: bubbles
side by side within the column, each narrower.

**Interactions.**
- Tap a bubble: a bottom card slides up (250 ms) with that task's row (time or remaining, title,
  ring). Tap the card: the editor.
- Scroll vertically through the day. Swipe horizontally: previous or next week.
- Return to the day view: drag up (DP-NAV-02) or the view menu.
- Entry points: DP-NAV-02 if on; a view menu with "Day", "Week", "Month" (Structured opens it by
  long-pressing the Timeline tab; here the page draws it).

**Words.** Hour labels. Menu: "Day", "Week", "Month".

**Data.** Reads `task:<id>` (day, start, duration, colour, icon, done, allDay, energy) for seven
days, `exception:<taskId>:<date>`, `settings:planner` (week start, day start, day end).

**Needs.** Page alone. Events need `shell/calendar-access.md`.

**Edge cases.** Checklist 46: a week view exists on the phone, in portrait. Checklist 17: columns
start on the chosen weekday. Checklist 26: a midnight-crossing task shows in both columns.

**Tests.**
- Given week start Monday and a task on Wednesday 9:00 for 60 min, when the week renders, then
  its bubble is in column 3 at the 9:00 y and 40 pt tall.
- Given a past day's task, then its bubble background is the task colour; a future day's is
  `--bubble-future`.
- Given a tap on a bubble, then a card shows that task's title.
- Given portrait orientation, then seven columns render.

**Evidence.** DP-NAV-03 [C]. Loves: Readdle 2 ("I love the weekly view", C; "excellent view of the
week", D); Zapier "the most useful week view by far" (C). Complaints: Apple landscape only (1, C);
Notion no week (8+, C); Structured board Monthly/Weekly View 3.3k (E); Readdle row direction (1,
D); week or month view 140 negative hits (E). Teardown 1.2. Screenshots:
`agent/help/3561154_2.png`, `c/readdle/appstore_2.jpg`.

---

### DP-NAV-04 Month view shapes

**Tag:** core (checklist 46 names it). **Variations:** A, dots: Structured month sheet, Morgen,
Apple Compact. B, text chips: Readdle, TickTick, Apple Details, Google. C, month plus the day's
agenda below: Morgen, Timepage Heat Map. D, Apple: pinch between Compact, Stacked, Details.
**Default variation:** A, Structured month sheet.

**What it is.** A month grid. Each date carries marks for its items.

**Anatomy.**
- Opened by tapping the month and year in the header. A bottom sheet, `--bg-sheet`, radius
  32 pt, over the timeline dimmed by a 20% black overlay.
- Sheet header: month bold 20 pt `--ink`, year in `--accent`, then "›". At the right: a "Today"
  pill (DP-NAV-08) when the shown month or selected day is not today's, then a "•••" button and
  a ✕ button, each 30 pt round.
- Weekday labels 11 pt `--ink-2`, starting on the week start.
- Date cells: number 17 pt; today `--accent` filled circle, selected `--ink` filled circle.
  Under it up to 4 dots, 6 pt, in task colours.
- Variation B: up to 3 text chips per cell, 10 pt, task colour background, white text, one line,
  then "+{n}" for the rest.

**States.** Empty date: number only. Past dates: same as future (the research shows no change).

**Interactions.** Tap a date: selects that day and closes the sheet (250 ms). Swipe left or
right: next or previous month. ✕ or a swipe down: close. "•••": display options (Structured:
"Adjust appearance", and Tasks / Energy Levels / Cycle Seasons).

**Words.** "Today". Month and year via `Intl.DateTimeFormat`. Menu: "Adjust Appearance",
"Tasks", "Energy".

**Data.** Reads `task:<id>` (day, colour, repeat), `exception:<taskId>:<date>` for the month,
`settings:planner` (week start).

**Needs.** Page alone.

**Edge cases.** Checklist 46: a month view exists on the phone. Checklist 17: week start.
Repeats are expanded for every date shown, including dates from the next and previous months in
the grid.

**Tests.**
- Given a daily repeat from 1 Oct with an exception skipping 14 Oct, when October renders, then
  14 Oct has no dot from it and 15 Oct has one.
- Given week start Sunday, when October 2026 renders, then every date in the first column is a
  Sunday (4, 11, 18, 25 Oct).
- Given a tap on 20 Oct, then the sheet closes and the day view shows 20 Oct.
- Given 6 tasks on a date in variation B, then 3 chips and "+3" render.

**Evidence.** DP-NAV-04 [C]. Loves: Readdle month text 2 quotes plus "not satisfied with
[Apple's] week view just showing dots" (D). Complaints: Notion month picker shows no events (1,
C); Google wants vertical scroll (1, C); TickTick month and week need Premium (2, D). Teardown
1.3. Screenshots: `d/calendars/appstore_2.png`, `agent/help/3561154_3.png`.

---

### DP-NAV-05 Busyness heat map

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Timepage
Heat Map and widget. B, Fantastical Year. C, TickTick Year heatmap. D, Readdle widget week with
progress rings.
**Default variation:** A, Timepage.

**What it is.** Month cells shaded by how full each day is.

**Anatomy.** The DP-NAV-04 grid, each cell's circle filled with `--accent` at an opacity by
planned minutes over day length: 0, 0.15, 0.3, 0.5, 0.75 for under 10%, 10–30%, 30–50%, 50–75%,
over 75%.

**States.** No tasks: no fill. Today: ring in `--ink` around the shade.

**Interactions.** Tap a date: the day's agenda below the grid (variation C of DP-NAV-04).

**Words.** None beyond dates.

**Data.** Reads `task:<id>` (day, duration, repeat), `exception:<taskId>:<date>`,
`settings:planner` (day start, day end).

**Needs.** Page alone. The widget variation needs `shell/planner-widget.md`.

**Edge cases.** All-day tasks have no duration; they count 0 minutes.

**Tests.**
- Given a 14 h day and 8 h of tasks on 14 Oct, then 14's fill opacity is 0.5.
- Given only an all-day task on 15 Oct, then 15 has no fill.

**Evidence.** DP-NAV-05 [C]. Loves: 2 (Zapier on Timepage and Fantastical, C). Complaints: none.
Screenshots: `c/timepage/appstore_7.png`, `c/fantastical/appstore_2.jpg`.

---

### DP-NAV-06 DayTicker (time-placed pills in a week strip)

**Tag:** on request (no checklist item or leave reason names it). **Variations:** Fantastical
only: a horizontal strip of days where each event is a pill at the height of its time of day.
**Default variation:** Fantastical.

**What it is.** A week strip that is also a tiny timeline: each day column holds thin pills placed
by time.

**Anatomy.** Replaces the DP-NAV-01 dots. Strip 96 pt tall. Each day column: date on top
(DP-NAV-01 states), then a 64 pt area mapping day start to day end. Pills 6 pt wide, radius 3,
task colour, height by duration (minimum 3 pt), side by side when overlapping. A grabber under
the strip.

**States.** Empty day: blank area. Past part of today: pills at 50% opacity.

**Interactions.** Tap a day: selects it. Swipe: next or previous week. Pull the grabber down: the
month grid (DP-NAV-04).

**Words.** None.

**Data.** Reads `task:<id>` (day, start, duration, colour) for seven days, `settings:planner`.

**Needs.** Page alone.

**Edge cases.** All-day tasks are not drawn as pills.

**Tests.**
- Given day 8:00–22:00 and a task 15:00–16:00, then its pill's top is at 32 pt of the 64 pt area
  and its height is 4.6 pt (±0.5).
- Given a 1-minute task, then its pill is 3 pt tall.

**Evidence.** DP-NAV-06 [C]. Loves: 1 Zapier plus 1 review (C). Complaints: none. Screenshot:
`c/fantastical/hires_0.png`.

---

### DP-NAV-07 Zoom and pinch between scales

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Apple: tap
the back title, day → month → year. B, Timepage: pinch changes days shown 7 / 5 / 3. C, Sunsama,
Akiflow, Tiimo: pinch the calendar. D, TickTick: pinch the month.
**Default variation:** B, Timepage, as 7 / 3 / 1 days in the week view.

**What it is.** One gesture moves between scales.

**Anatomy.** No new parts. The week view (DP-NAV-03) redraws with 7, 3 or 1 columns.

**States.** 7 days, 3 days, 1 day.

**Interactions.**
- Pinch in (fingers together): more days (1 → 3 → 7). Pinch out: fewer.
- One step per gesture, applied when the scale passes 0.8 or 1.25; columns animate width (200 ms).
- The page must set the viewport to `user-scalable=no` and read two-finger touch events
  (`touchmove` with two touches, or WebKit `gesturechange`), or the WKWebView zooms the page.
- Apps give a haptic on each step; a Sidekick page has no haptics API.

**Words.** None.

**Data.** None stored. The current scale is page state.

**Needs.** Page alone.

**Edge cases.** Apple iOS 27 removed the "<" to month (1 complaint): every scale is also reachable
from the view menu.

**Tests.**
- Given the week view at 7 days, when a pinch out ends at scale 1.4, then 3 columns show.
- Given 3 columns, when a pinch ends at scale 1.1, then 3 columns still show.
- Given a pinch on the day view, then the page's zoom (`visualViewport.scale`) stays 1.

**Evidence.** DP-NAV-07 [C]. Loves: 1 (Zapier "It all makes sense", C). Complaints: Apple iOS 27
removed the "<" to month (1, C). Screenshots: `c/fantastical/appstore_2.jpg`,
`c/timepage/appstore_0.png`.

---

### DP-NAV-08 Jump to today

**Tag:** core (checklist 1 names it; its removal drew complaints in Google and Readdle).
**Variations:** A, Structured: long-press the month in the header; a "Today" pill in the month
sheet. B, Google: a calendar icon showing today's date. C, Notion: a date tile, red when today is
off screen. D, Akiflow: "Today Button". E, Apple: "Today" bottom-left.
**Default variation:** A, Structured.

**What it is.** One control back to today. The page also always opens on today.

**Anatomy.**
- Long-press target: the month and year in the header.
- "Today" pill in the month sheet header: 30 pt tall, radius 15, `--accent-tint` background,
  `--accent` text 15 pt semibold. Shown only when the shown month or selected day is not today's.

**States.** On today: pill hidden. Off today: pill shown.

**Interactions.**
- Long press the header month (500 ms): selects today and scrolls the timeline to now.
- Tap "Today": selects today, closes the month sheet.
- On page open, and on `visibilitychange` to visible after the day has changed: selects today if
  the person was on the previous today.

**Words.** "Today".

**Data.** Reads `settings:planner` (day end, for when "today" changes).

**Needs.** Page alone.

**Edge cases.** Checklist 1: the day opens on today. Checklist 27: "today" changes at the day end
set in `settings:planner`, not at midnight. The long press alone is hard to find; variations B to
E are visible controls.

**Tests.**
- Given the page opens at 9:00 on 12 Oct, then 12 Oct is selected and now is in view.
- Given 20 Oct selected, when the header month is long-pressed, then 12 Oct is selected.
- Given today selected at 23:59 with day end 00:00, when the page becomes visible at 00:05, then
  13 Oct is selected.
- Given day end 03:00 and the clock at 01:30 on 13 Oct, when the page opens, then 12 Oct is
  selected.
- Given the month sheet on October with today selected, then no "Today" pill is in the DOM.

**Evidence.** DP-NAV-08 [C]. Loves: none direct. Complaints when removed: Google July 2026 made it
two taps (several, C); Readdle "'Today' button now gone" (1, C). Teardown 1.1 header, 1.3.
Screenshots: `c/notioncal/appstore_0.png`, `agent/help/3561154_3.png`.
