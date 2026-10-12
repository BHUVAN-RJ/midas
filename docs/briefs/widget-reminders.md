# Brief: widget-reminders (the Reminders widget)

Founder, 2026-10-11: "For reminders, let's also build a standalone widget which will show the three
today's reminders." Mockup: https://claude.ai/artifact/6BigRus6CmZAVKHdk5bbcK, second row
(`RemindersHome`, `RemindersStates`; sources in midas-intel `docs/prototypes/widgets/`). Reminders
rules: midas-intel `docs/prototypes/reminders-bhuvan/BRIEF.md` (what Today means, circle colours,
12-hour time) and the Sidekick itself, `sidekicks/reminders/index.html` (record shapes:
`reminder:<id>` with `at`, `title`, `list`, `repeat`, `done`, `allDay`, `timeZone`, `doneThrough`,
`lastDoneAt`; `list:<id>` with `name`, `color`). The Sidekick widget (`shell/MidasWidgets/FolderWidget.swift`)
and its contract (`shell/Shared/WidgetShared.swift`) are on main; follow their pattern.

## Build

1. **Today's reminders, computed by the app.** From the local record store, the reminders of the
   `reminders` Sidekick that are in Today as the Sidekick defines it: dated today, not done, past
   due today stays in Today until midnight; undated never. Repeats count with today's occurrence
   (reuse `ReminderSchedule` / `ReminderPlanner` where they fit). Each item: id, title, time, the
   circle colour (the list's colour; with no list, blue `#007AFF`), and whether its time has passed.
   Sorted by time, earliest first.
2. **Shared file.** The app writes them (all of today's, not just three) to a new file in the App
   Group container, versioned like `SharedSidekickList`, and reloads the Reminders widget whenever a
   `reminder:` or `list:` record changes and at launch. Add the file name, the struct and the widget
   kind to `shell/Shared/` (a new file; do not edit `WidgetShared.swift`).
3. **The widget**, kind `com.bhuvanrj.midas.reminders`, display name "Reminders", description
   "Today's reminders.", families small, medium and large, in `MidasWidgetsBundle`:
   - small: "Today" (blue, bold) and the count; the first 3 by time, each a circle in its colour,
     the title (one line) and the time under it;
   - medium: "Today" and a large count on the left; 3 rows on the right, title then time on one line;
   - a time that has passed is red (`#FF3B30`, dark `#FF453A`); 12-hour times ("6:00 PM");
   - nothing left today: "All done"; no file (signed out, or no Reminders Sidekick): "Open Midas";
   - light, dark, tinted and clear looks as in the mockup (accented mode keeps rows readable).
4. **Tick to mark done (changed by the founder, 2026-10-11, overrides the old "no ticking").**
   Each row's circle is an interactive `Toggle`/`Button` with an App Intent (iOS 17) that marks
   that reminder done exactly as the Sidekick does (a one-time reminder `done: true`; a repeat
   records today's occurrence done the way the Sidekick writes it: read `index.html`). The row
   leaves the widget at once. The change must reach the record store, its outbox (sync) and the
   notification engine (cancel that reminder's pending notifications). First find out from the
   SDK and Apple's docs whether a widget's intent can run in the app's process; if yes, use that;
   if not, the extension writes the tick to an App Group file the app applies at its next launch
   or background refresh, and the widget hides the row meanwhile. Say which you chose and why.
5. **More than fits: no scrolling.** WidgetKit does not support `ScrollView` (Apple's list of
   views that work in widgets has none). Add a **large** size (up to 8 rows). When today has more
   than the size shows, add up and down arrow buttons (App Intents changing a page index kept in
   the App Group) to page through today's reminders, as close to scrolling as widgets allow.
6. **Taps elsewhere:** the rest of the widget opens the Reminders Sidekick
   (`MidasLink.openSidekick(id: "reminders")`).
7. **Timeline:** entries at each reminder's time today (so a row turns red when its time passes)
   and at the next midnight (Today rolls over); reload after a tick or a page change.

Pure logic (which reminders are in Today, the order, the first three, the passed flag, the count)
goes in `shell/Shared/` so `MidasTests` can test it through the app module.

## Files you own

New files under `shell/Shared/`, `shell/Midas/` and `shell/MidasWidgets/`;
`shell/MidasWidgets/MidasWidgetsBundle.swift`; the app's wiring in `shell/Midas/ShellServices.swift`
and `shell/Midas/MidasApp.swift` if needed; new test files under `shell/MidasTests/`. Anything else
(including `shell/project.yml`): stop and ask the lead.

## Rules

- `docs/PARALLEL-AGENTS.md` rules for a worktree agent; `CLAUDE.md` for tests (existing tests change
  only through test-guardian). Style: `~/.claude/CLAUDE.md`. Words on screen: only "Reminders",
  "Today's reminders.", "Today", "All done", "Open Midas"; `docs/WRITING.md`.
- Signing: never change team, bundle id, signing style or entitlements to get past an error; stop
  and write the founder's steps.
- Tests (new files): Today membership (today, past due today, yesterday, tomorrow, undated, done,
  a daily repeat), order, first three, count, passed flag at a given now, list colour and the blue
  fallback, the file round trip, timeline entry dates (each time today plus midnight).
- The staging account "Test" on the iOS 27 iPhone 17 simulator has fake reminders for tonight
  (lists Personal and Midas). Use it to look at the widget; do not change its records.
- Done = all suites pass from the worktree root, work committed on `agent/widget-reminders`. Report
  results honestly, including failures.
