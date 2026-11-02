# Outside the page (TD-OUT)

How the to-do list reaches the person when the page is not open: notifications for timed to-dos,
a Home Screen widget, and adding from the Lock Screen or Control Center. Three patterns.

Sources:
- midas-intel `docs/research/todo/`: `look-group-a.md` 1.2 and 3.2 (Things and Reminders widgets,
  Lock Screen notification, New Reminder control), `look-group-b.md`, `look-group-c.md` and
  `look-group-d.md` 1.2 and Part 2 (P-new-29, 37), `group-d.md` (P3, P4, #45, #46, #48, #49, #57,
  and the imported DP-41 to DP-43).
- The engine as built: `docs/NOTIFICATIONS.md`.
- The widget builder as built: `docs/WIDGETS.md`.
- The one control that exists: `shell/MidasWidgets/VoiceReminderControl.swift`.

Template: `docs/primitives/daily-planner/README.md`. Records: `../records.md`. Values marked [U]
are proposals not found in the research. Written 2026-10-31.

A Sidekick page has no native API (PRODUCT.md 5, guideline 4.7.2). Everything here that lives
outside the page is drawn and run by the shell; the page reaches it only by writing records.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-OUT-01 | Notifications for timed items | core | Not set: whether a to-do *is* a `reminder:` or points to one is open (records.md 4). Tests are written for "points to one" (A). |
| TD-OUT-02 | Widget | core | Today list with ticks, small, medium and large, made with the shell's Sidekick widget (`widget:today`) |
| TD-OUT-03 | Lock Screen / Control Center add | on request | None set; proposal: a "New To-Do" control that opens the page on the add field |

| ID | Needs |
|---|---|
| TD-OUT-01 | shell has it (notification engine); gaps: floating one-time alerts (`../../daily-planner/shell/local-time-alerts.md`), repeat after completion (NOTIFICATIONS.md 7, not built) |
| TD-OUT-02 | shell has the widget builder; lacks a today source and a full tick for `todo:` records (no brief written) |
| TD-OUT-03 | shell lacks it (only "Ask jess" exists; Lock Screen widgets "later"); no brief written |

---

### TD-OUT-01 Notifications for timed items

**Tag:** core. Reasons:
- Imported checklist items DP-41 to DP-43 (alerts fire with the app closed, beyond the 64 cap,
  never for deleted items).
- #45 (floating time); P4 (a to-do finished on one device still alerting on another).
- records.md: "a timed to-do gets a notification".

**Variations.** How the record meets the engine (records.md 4, open):
- **A. The to-do points to a reminder.** The page writes a separate `reminder:todo-<todoId>` for
  each timed to-do and keeps it in step. records.md section 1 stays as written.
- **B. The to-do is a reminder.** The to-do is stored as `reminder:<id>` with its own `$type`, and
  the engine reads its `at`, `title` and `notes` directly. records.md's `when` + `time` would
  become `at` + `timeZone`. B makes TD-OUT-02 work with the widget builder as built (see there).

How apps show them:
- **Apple Reminders Lock Screen notification:** "From Reminders · Due 1 minute ago", a
  "Reschedule" button, and a big tappable circle to complete it there [C].
  - "I love that it keeps the reminder on my lock screen as a notification all day until I mark
    it as completed." [R]
  - The Urgent alarm is full screen with "Snooze" and slide to stop [C].
- **TickTick:** "Done" on the Lock Screen does not complete an overdue task [R, P3].
- **Google Tasks:** marked complete from a push, it does not sync [R, P4].
- **Due:** finished on an iPad, "keep reminding me on my iPhone" [R, P4].

**Default variation:** not set, the founder decides between A and B. The rest of this pattern is
written for A, which needs no change to records.md. The notification is the engine's standard one
(NOTIFICATIONS.md 5), Time Sensitive (`reminderType` absent). A choice of "normal" or "alarm" per
to-do is on request (Reminders' Urgent).

**What it is.** A to-do with a day and a time notifies at that time, with the page closed.

**Anatomy.** Drawn by iOS (NOTIFICATIONS.md 5, layout A):
- the Midas icon and name;
- title = the to-do's `title`;
- subtitle = the Sidekick's name;
- body = "9:00 AM · <notes>" (time only without notes);
- the default sound, grouped under the Sidekick.
- Long-press buttons, fixed for every Sidekick: Done, Snooze 10 min, Snooze 1 hour, Snooze until
  tomorrow.
- Nothing in the page: a time set in TD-ITEM-05 is the whole setting.

**The reminder record (A).**

`reminder:todo-<todoId>`:
- `at`: `when` + `time` read in the phone's zone, as an ISO instant (`Date.toISOString()`).
- `timeZone`: `Intl.DateTimeFormat().resolvedOptions().timeZone`.
- `title`: the to-do's title, with control characters removed (#57).
- `notes`: the to-do's notes.
- `todo`: `<todoId>`, the Sidekick's own field, kept by every writer.
- `$type`: a type the manifest declares, e.g. `todo.alert` [U].

When the page writes, changes or deletes it:

| To-do event | Reminder |
|---|---|
| gets `when` and `time`, not done, not someday | `store.set` the record |
| `title`, `notes`, `when` or `time` changes | rewrite (a new `at` moves the notification) |
| `time` or `when` cleared, someday set, or deleted | `store.delete` the reminder first, then the to-do change (DP-43) |
| ticked in the page | one-time: `store.delete`. Repeat with an engine repeat: set its `todo` to the new copy and leave the series running [U] |
| repeat `from: schedule` with `every` day, week or month | the reminder has `repeat { every: "day" / "week" / "month" }`; `weekday` gives `{ every: "week", weekdays: [1, 2, 3, 4, 5] }`. These are one iOS slot each (interval 1, no `until`) and keep firing without the page |
| repeat `from: done` | a one-time reminder per copy: the engine has no repeat after completion (NOTIFICATIONS.md 7, "Not built") |

**On page open** (reconcile what the shell wrote):
- A reminder with `done: true` (Done on the notification): the page ticks its to-do with
  `completedAt` = the reminder's `completedAt` (the real tick time, #43). For a repeat it writes
  the next copy (TD-ITEM-04), then deletes the reminder.
- A repeating reminder with `doneThrough` past the open copy's `when`: each occurrence through
  `doneThrough` is ticked with `completedAt` = `lastDoneAt`, the next copy is written, and the
  reminder's `todo` moves to that copy [U].
- A reminder whose `timeZone` differs from the phone's zone: `at` is rewritten so 09:00 stays
  09:00 (#45). Until the page opens, a one-time reminder fires at the old instant
  (`../../daily-planner/shell/local-time-alerts.md`).
- A reminder whose to-do is gone: deleted.

**States.**
- **No permission:** the shell asks the first time a `reminder:` is written (WRITING rule 9; the
  page asks nothing). If refused, nothing is booked and the to-do still works.
- **Over the 48 bookings shared by all Sidekicks:** kept in Midas's queue; fires in turn, or once
  as "missed" if Midas did not run (NOTIFICATIONS.md 6.2, 7).
- **Snoozed:** the shell writes `snoozedUntil`; the page ignores it.
- **Done on another device:** the reminder syncs with the account and the other phone's engine
  stops it [U, depends on account sync timing].
- **Untimed to-do:** no notification. A deadline notification and an all-day time are not mapped.

**Interactions.**
- Tap the notification: opens the Sidekick (shell). Opening onto the to-do's card is not built
  [U].
- Done and Snooze: fixed shell buttons (NOTIFICATIONS.md 5). Per-Sidekick buttons (Reminders'
  "Reschedule") are not built.

**Words.** Title: the to-do's title. Body: "<time> · <notes>", from the shell. No other words.

**Data.**
- Reads `todo:` `title`, `notes`, `when`, `time`, `done`, `someday`, `repeat`.
- Writes and deletes `reminder:todo-<id>` (`at`, `timeZone`, `title`, `notes`, `repeat`, `todo`).
- Reads back `done`, `completedAt`, `lastDoneAt`, `doneThrough`.

**Needs.** Shell has it: the notification engine (`reminder:` records, Done and Snooze, the
missed-notice ledger, wall-clock repeats). Not covered:
- a floating one-time alert (`../../daily-planner/shell/local-time-alerts.md`);
- repeat after completion (NOTIFICATIONS.md 7);
- a deadline alert (records.md 4);
- a per-Sidekick "Reschedule" button.

**Edge cases.**
- **DP-41:** with the page closed, the engine fires it.
- **DP-42:** beyond the 64 cap, the shell's queue handles it.
- **DP-43:** deleted means the reminder is deleted first.
- **#43:** the real done time comes from the reminder.
- **#45:** `at` is rewritten after a zone change.
- **#46:** repeats are wall-clock, one-time `at` is rebuilt from day strings.
- **#48:** only one open copy, so one reminder.
- **#49:** a mis-tick from the Lock Screen shows the to-do done in the page, and its checkbox
  reopens it (TD-DONE-06), which rewrites the reminder.
- **#57:** control characters stripped from the title.
- **P4:** Done writes the shared record.

**Tests** (A).
- Given the phone in America/New_York and a to-do with `when` 2026-11-02 and `time` "09:00", when
  it is saved, then `reminder:todo-<id>` has:
  - `at` "2026-11-02T14:00:00.000Z";
  - `timeZone` "America/New_York";
  - its title.
- Given that to-do, when `time` changes to "10:30", then `at` is "2026-11-02T15:30:00.000Z".
- When the to-do is deleted, then `store.get('reminder:todo-<id>')` is null.
- Given a to-do with `when` and no `time`, then no `reminder:todo-<id>` exists.
- Given the shell wrote `done: true` and `completedAt` "2026-11-02T14:05:00.000Z" to the reminder,
  when the page opens on 2026-11-03, then:
  - the to-do has `done: true` and `completedAt` "2026-11-02T14:05:00.000Z";
  - the reminder is gone.
- Given a to-do with `repeat { every: "weekday", from: "schedule" }` and `time` "08:00", then its
  reminder has `repeat { every: "week", weekdays: [1, 2, 3, 4, 5] }`.
- Given a to-do with `repeat { every: "day", from: "done" }`, then its reminder has no `repeat`.
- Given a title "Pay\u001b[31m rent", then the reminder's title has no U+001B character.
- Given the reminder's `timeZone` "America/New_York" and the phone now in America/Los_Angeles,
  when the page opens, then `at` is rewritten to 09:00 Los Angeles time and `timeZone` to
  "America/Los_Angeles".

**Evidence.**
- look-group-a 3.2 (Lock Screen notification and Urgent alarm [C]), 3.4 (love 6 [R]).
- group-d P3, P4, #43, #45, #46, #48, #49, #57, and the DP-41 to DP-43 import.
- NOTIFICATIONS.md 4.2 to 4.4, 5, 6.2, 6.5, 7; records.md 4.
- No screenshot in `shots/` (`reminders_iphone_5` is in look-group-a).

---

### TD-OUT-02 Widget

**Tag:** core. Reasons:
- P-new-37: the widget renders in iOS 26 tinted and clear modes. Microsoft To Do has 14 reviews
  of "a big white box".
- Superlist: "Finally Found my List App! Just Needs Widgets!" [R].
- P3: TickTick widget rows "too close together", leading to wrong check-offs [R].

**Variations:**
- **Things:** a Home Screen card "★ Today 1 7" with checkboxes. A Lock Screen widget with three
  to-dos and round ✓ and + buttons [C, `things_iphone_8`].
- **Apple Reminders:** an extra-large widget, "15 / Family Tasks", sections by person, circle
  checkboxes, repeat glyphs [C].
- **Tweek:** a dark "Today" card with a struck-through done line, coloured pills and "2 more"; a
  Lock Screen progress ring and a "+" mascot [C].
- **Any.do:** a week strip with today boxed in blue and "New Event | New Task" [C].
- **TickTick:** Today list, Matrix, habit ring and timer widgets [C].
- **Complaints** [R]:
  - Google Tasks shows three rows and "so much wasted space"; "borderline useless".
  - Microsoft To Do's large font "cuts off a large amount of the tasks".

**Default variation:**
- A Today list with a tick on each row: small, medium and large.
- Made with the shell's Sidekick widget: one `widget:today` record, as the Reminders Sidekick's
  widget (PRODUCT.md 2026-10-26), with a "+N more" line in place of paging.

**What it is.** Today's open to-dos on the Home Screen, tickable without opening Midas.

**Anatomy.**
- Drawn by the shell from the `widget:today` record (WIDGETS.md pieces).
- Header: "Today" (headline) and the open count (`number`) [U].
- Rows (`list` piece), each: a `tick` circle in the accent, the title (`body`, 1 line in small and
  medium, 2 lines in large) [U], and the time at the right when set (`caption`, `secondary`).
- Rows are spaced at least 8 pt apart [U] (P3).
- Under the rows: "+3 more" (`more`).
- Sizes: small shows 2 rows, medium 3, large 7 [U].
- `background` follows the page's look in light and dark pairs [U].
- In tinted and clear modes, the builder draws the tick in the primary colour
  (`widgetRenderingMode == .accented`, `SidekickWidgetViews.swift`). A full check of every piece
  in clear mode on a phone is not done [U].

**States.**
- Open to-dos: the rows.
- None open, some done today: "All done" (the builder's `empty`, WIDGETS.md example).
- Tapped tick, app not yet run: the row shows ticked at once (`SidekickWidgetTapPreview`).
- New day without the app: the builder reloads at midnight (`SidekickWidgetProvider` timeline).
  Whether the to-do list's rows follow TD-DAY-01 then depends on the source (see Needs).
- No record or signed out: the shell's own placeholder ("Open Midas", daily-planner precedent).

**Interactions.**
- Tap a row: opens the Sidekick (`open`).
- Tap a tick: the builder's `tick` tap, queued with `tappedAt` and written by the app when it next
  runs (WIDGETS.md).
- No typing and no scrolling (iOS).

**Words.** "Today" · "All done" · "+3 more". No other words.

**Data.**
- Writes `widget:today` (`midas.widget` type, checked on write; at most 150 pieces, 8 sources,
  64 KB).
- The ticks change `todo:` records.
- The page rewrites the widget record only when its layout changes, not on every to-do change [U].

**Needs.** Shell has the widget builder (WIDGETS.md, built 2026-10-13 and later). It lacks two
things for `todo:` records, and no shell brief is written:
1. **A today source.** `{ records: 'reminder:', when: 'today' }` is the only source that picks a
   day's items. `where` matches equal values only, so it cannot pick `when` ≤ today, deadlines or
   `inToday`.
2. **A full tick.** A tick on a record that is not a `reminder:` writes only `done: true`: no
   `completedAt` and no next repeat copy. The page fills these in when it next opens, but cannot
   know the tap time, so `completedAt` would be the open time, against #43.

Ways out, for the founder:
- (a) Shell adds a `todo:` today source and a tick that writes `completedAt` from `tappedAt`.
- (b) The page writes one summary record of today's rows for the widget to list. Whether a `list`
  piece can read an array field of a single record is not checked [U], and it goes stale at
  midnight without the page.
- (c) TD-OUT-01 option B (a to-do is a `reminder:`): the built `when: 'today'` source and the
  reminder tick (`done` + `completedAt`, like the notification's Done) then work as built. Only
  the `carry`/`stay` model of showing past days is unknown [U].

**Edge cases.**
- **P-new-37:** tinted and clear modes.
- **P-new-29:** long titles keep 1 to 2 lines, never cut to a fragment with no ellipsis.
- **P3:** rows spaced against mis-ticks.
- **#49:** a mis-tick from the widget is undone in the page (TD-DONE-06); the widget has no Undo.
- **#43:** see Needs 2.
- **#42:** the midnight reload.

**Tests.**
- Given the page with `widget:today` written, then `store.set('widget:today', …)` resolves (the
  shell's `midas.widget` check passes).
- Given 5 open to-dos today and the medium layout, then the drawn widget (builder test with a
  sample file) shows 3 rows and "+2 more".
- Given 0 open and 2 done today, then the widget shows "All done".
- Given a tick tapped on a to-do in the widget and the app run later, when the page opens, then:
  - the to-do has `done: true` and a `completedAt`;
  - a repeating one has its next copy.
  This is a page test with a record holding `done: true` and `completedAt` absent.
- Given the widget in tinted mode (`widgetRenderingMode` accented), then the tick draws in the
  primary colour (shell snapshot test).

**Evidence.**
- look-group-a 1.2 (Things widgets [C]), 3.2 (Reminders extra-large [C]); look-group-c 2.2 (Any.do
  [C]), 4.2 (Tweek [C]); look-group-b 2.2 (TickTick [C]), 4.4 (Google Tasks [R]).
- look-group-d 1.7 (widget gap, density) and P-new-37; group-a 5 (Superlist [R]); group-d P3.
- WIDGETS.md; PRODUCT.md 2026-10-26 (Reminders widget made with the builder).
- Screenshot: `tweek_8.jpg` (look-group-c; not in `shots/`).

---

### TD-OUT-03 Lock Screen / Control Center add

**Tag:** on request. It is not a checklist item or a leave reason. One love: "I very much
appreciate the 'quick add' feature that was recently added in the Control Center" (Reminders 5★,
2026-10-18) [R].

**Variations:**
- **Apple Reminders iOS 26:** a "New Reminder" control for Control Center, the Action button and
  the Lock Screen [R]. A glass card over the Home Screen with a "Reminders ⌄" list picker, the
  title with the cursor, Notes, "Tomorrow, 09:00", an icon row (calendar, location, flag) and a
  blue ✓ [C, `reminders_iphone_9`].
- **Things:** the Lock Screen widget's round + [C].
- **Tweek:** a "+" quick-add mascot on the Lock Screen [C].
- **Tiimo:** a "Review Today" Lock Screen widget [C].

**Default variation:** none set. Proposal [U]: a "New To-Do" control (Control Center, Action
button, Lock Screen) that opens Midas onto this Sidekick with the add field focused (TD-ADD).

**What it is.** Starting a new to-do without finding the app first.

**Anatomy.** Drawn by iOS from a shell `ControlWidget`: a glyph and the label "New To-Do" [U].
Midas facts:
- One control exists, "Ask jess" (`VoiceReminderControl`, kind `com.bhuvanrj.midas.new-reminder`,
  iOS 18). It runs the App Shortcut that opens the Listening screen.
- There is no per-Sidekick control.
- Lock Screen widgets are "later" (WIDGETS.md).
- A control cannot hold a text field. The Reminders card is Apple's own; whether a third-party
  control can show one is not checked [U].

**States.** Not specified until the shell piece exists. Page side: opened with an "add" reason
[U], the add field is focused with the keyboard up.

**Interactions.** Tap the control: Midas opens on the Sidekick's add field. Whether "Ask jess" can
add a to-do to this Sidekick needs a jess tool for it, which is not specified [U].

**Words.** "New To-Do" [U]. App Shortcut phrases must contain the app name (PRODUCT.md 6, per the
daily-planner note).

**Data.** Writes a `todo:` through the page, as TD-ADD (`list: "inbox"` unless parsed).

**Needs.** Shell lacks it: a new control and a way to open a Sidekick with a reason. No brief is
written. Every shell change is a new build (PRODUCT.md).

**Edge cases.** P5 (capture fast): the add field is ready on first paint, with no wait on the
store.

**Tests.** None for the control until it is specified. Page side, once the open reason is
defined: given the page opened with the add reason, then the add field has focus within the first
render and no other sheet is open.

**Evidence.**
- look-group-a 3.2 (`reminders_iphone_9` [C], iOS 26 [R]); look-group-d 1.2 (Control Center love
  [R]); group-a 6 (Reminders iOS 26 [R]); look-group-c 3.2 and 4.2 (Tiimo, Tweek [C]).
- `shell/MidasWidgets/VoiceReminderControl.swift`; WIDGETS.md.
- Screenshot: `reminders_iphone_9` (look-group-a; not in `shots/`).
