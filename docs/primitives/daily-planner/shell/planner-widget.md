# Brief: a planner widget (Home Screen and Lock Screen), 2026-10-12

**Status:** Draft, not approved to build. The founder decides whether and when.

Labels: [C] confirmed on a primary source (Apple docs as cited in midas-intel research) or read in
this repo's code; [R] reported; [U] not verified.

## How you work

The four steps of `docs/briefs/notification-engine.md`: say the idea back; ask; propose a plan
and wait for "approved"; then build with tests (`CLAUDE.md`). Model brief for a widget:
`docs/briefs/widget-reminders.md`.

## Goal

A widget that shows a planner Sidekick's current and next task and stays correct through the day
(checklist 44), shows a task that crosses midnight on both days without duplicating it (26), and
a Lock Screen "Up Next" form. Patterns DP-OUT-01, DP-OUT-02 (`../blocks/outside.md`). Leave reason
9 (no widgets: Llama "dealbreaker", widget 235 negative hits); love 13.

## What is already decided (with sources)

- Native reach now: notifications and widgets (PRODUCT.md 5, 2026-10-07). "A calendar widget
  comes with the calendar Sidekick" (same).
- Widgets as folders ("Sidekicks") and the Reminders widget are built and live on TestFlight
  build 0.1.0 (2) (PRODUCT.md 6, 2026-10-11 and 2026-10-12).
- Lock Screen widgets: "Recorded, not worked on" (PRODUCT.md 6).
- The Reminders widget's mechanics, built (`docs/briefs/widget-reminders.md`, code in
  `shell/Midas/RemindersWidgetPublisher.swift`, `shell/Shared/RemindersWidget*.swift`,
  `shell/MidasWidgets/RemindersWidget.swift`):
  - the app computes the widget's data from the local record store and writes a versioned file
    into the App Group `group.com.bhuvanrj.midas`, then reloads the widget's timelines;
  - it is hard-wired to the `reminders` Sidekick and to that Sidekick's record shapes;
  - ticks run in the app's process through a `LiveActivityIntent` (`TickReminderIntent`), with an
    App Group queue as fallback;
  - no scrolling; arrow buttons page through more rows;
  - timeline entries at each reminder's time and at midnight.
- The Sidekicks folder widget is configurable (`AppIntentConfiguration`): the person picks
  Sidekicks in its settings.
- Words: `docs/WRITING.md`. Gallery names avoid Apple Home Screen feature names (PRODUCT.md 6,
  "Sidekicks", not "Folder").

## What exists today

- Widget extension `shell/MidasWidgets/` with two widgets, families small, medium, large only.
  No accessory (Lock Screen) families.
- Nothing knows the planner's own fields (`duration`, `colour`, `icon`, `exception:`). The
  shell's widget code reads `reminder:` records (`TodayReminderPlanner.swift`), so a planner's
  tasks are already readable as reminders, without their end times. Every planner Sidekick is generated or hand-written
  per person, so record shapes are a per-Sidekick choice unless `../records.md` is treated as a
  contract.

## Platform facts

WidgetKit [C, Apple docs via category-and-completeness.md 2.6 and
ios-notifications-reference.md]:
- "For a widget the user frequently views, a daily budget typically includes from 40 to 70
  refreshes" (every 15 to 60 minutes).
- Timeline entries "at least about 5 minutes apart".
- Reloads do not count while the app is in the foreground or when the widget runs an App Intent.
- Self-updating text and progress (`Text(timerInterval:)`, relative dates,
  `ProgressView(timerInterval:)`) keep a countdown and a fill moving with no reloads.
- No `ScrollView` in widgets. No web views: a Sidekick's HTML cannot render in a widget.
- Lock Screen accessory families (circular, rectangular, inline) render monochrome or tinted;
  colours from the task do not show [C, WidgetKit rendering modes].
- Sizes on a 393 pt wide phone: small 158 × 158, medium 338 × 158, large 338 × 354 pt [C, Apple
  HIG]. Accessory sizes per device [U].

Apps [C, ANALYSIS.md 3.9]: Structured's bubble fills with colour, "in 15 min / Designing";
staleness complaints: Timepage freezes on iOS 27, Notion shows the wrong day, Google's widget
shows an event that ends after midnight as a new event on the next day (1★, 2026-03-05).

## Ways the widget could get a planner's data (to discuss)

| Option | How | Facts |
|---|---|---|
| A. Shell reads the planner's records | The app computes today from the `reminder:` tasks (`planner.item`), `exception:` and `settings:self` in `../records.md`, as the Reminders widget does from `reminder:` and `list:`. | Correct while the app has not run, for as long as the timeline covers. Ties every planner Sidekick to one record format. |
| B. Page writes a snapshot record | The page writes, say, `widget:today` with the next N days of items already expanded (title, icon, colour, start, end, done). The app publishes it as is. | No format contract beyond the snapshot. Goes stale after N days without the page opening, and after any edit made outside the page (a Done from a notification). |
| C. A shared "glance" format | Any Sidekick writes the same snapshot shape; one configurable widget shows the picked Sidekick's glance. | Serves Sidekicks beyond planners. Same staleness as B. |

## Open questions for the founder

1. A, B or C.
2. One planner widget kind with a Sidekick picker (as the folder widget), or one per Sidekick.
3. Check-off from the widget (as the Reminders widget) in the first version, or view only.
4. Lock Screen accessory families now or later ("recorded, not worked on").
5. What "4.7.3 consent in each instance" means when the person adds a widget and picks a Sidekick
   (see App Review).

## App Review

- **4.7.2** [C] The widget is the shell's own SwiftUI drawing data from records; no native API is
  exposed to the page.
- **4.7.3** [C] Data stays inside the Sidekick that owns it. Showing it on the Home Screen is the
  shell displaying it, as the Reminders widget does; no other Sidekick reads it.
- **5.1.1** [C] No permission prompt; no new data collected.
- **2.5.18** (no ads in widgets) [C, ios-notifications-reference.md] applies to the content.
- **2.5.8** applies to the folder widget, not to a planner widget showing one Sidekick's data
  (PRODUCT.md 6 names it for the folder).

## How a Sidekick reaches it (records only)

Option A: nothing beyond writing its `reminder:` tasks. Options B and C: the page also writes the
snapshot record after every change and on every open. The widget's taps open the Sidekick
(`MidasLink.openSidekick`). No bridge.

## Tests that can fail for their reason

Pure logic in `shell/Shared/` (as the Reminders widget), tested through `MidasTests`:
- Current and next at a given instant: tasks 9:00 to 10:00 and 10:30 to 11:00 at 9:30 give
  current = first, 30 min left, next = second.
- Timeline entry dates: each start and end today, plus the day boundary
  (`settings:self.dayStartsAt`), none closer than 5 minutes apart (merged when closer).
- A task 23:00 to 01:00: on the next day at 00:30 it is current, listed once, flagged as started
  the day before (checklist 26).
- A repeating task with a `skip` exception today: not listed today; listed tomorrow.
- A done task is not current.
- A pinned task (`zone` set): its local start after a zone change.
- The App Group file round trip, and "Open Midas" when there is no file.
- Option B or C: a snapshot older than its last covered day shows "Open Midas", not a wrong day.

## Done when

The founder approves a plan; the widget on the iPhone shows the right current and next task
across a full day, including after midnight, with Midas not opened; the full suite passes; results
reported honestly.
