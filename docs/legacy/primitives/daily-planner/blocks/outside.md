# Outside the app (DP-OUT)

The seven patterns from midas-intel `docs/research/daily-planner/ANALYSIS.md` section 3.9: how the
day reaches the person when the planner page is not open. Template: `../README.md`. Records:
`../records.md`. Written 2026-10-12. Docs only; nothing here is approved to build.

A Sidekick page has no native API (PRODUCT.md 5, guideline 4.7.2). Everything below that lives
outside the page is drawn and run by the shell; the page reaches it only by writing records.

| ID | Name | Tag | Needs |
|---|---|---|---|
| DP-OUT-01 | Home Screen widgets | core | shell lacks it: `../shell/planner-widget.md` |
| DP-OUT-02 | Lock Screen and "Up Next" | core | shell lacks it: `../shell/planner-widget.md` |
| DP-OUT-03 | Live Activity and Dynamic Island for the current task | core | shell lacks it: `../shell/live-activity.md` |
| DP-OUT-04 | Apple Watch | core | shell lacks it; no brief in this set |
| DP-OUT-05 | Per-task notifications (before, start, end) | core | shell has it (notification engine); gaps: `../shell/local-time-alerts.md`, `../shell/repeat-exceptions.md` |
| DP-OUT-06 | Daily plan and review notifications | on request | shell has it (notification engine) |
| DP-OUT-07 | Siri, Shortcuts and quick-add surfaces | on request | shell lacks it; no brief in this set |

---

### DP-OUT-01 Home Screen widgets

**Tag:** core. Reason: no widget is a reason users leave (leave reason 9: Llama "dealbreaker",
Sunsama 309 votes, widget 235 negative hits) and checklist items 26 and 44 name it.
**Variations:**
- A. Now and next: the current task with its fill and the next one with "in 15 min" (Structured,
  Routinery next-up with ▶).
- B. Today list with check-off (Things Today, TickTick interactive Today).
- C. Upcoming plus a create button (Akiflow "Upcoming" and "Create").
- D. Week with progress rings (Readdle).
- E. Countdown and leave-by (Timepage).
- F. Many designs to pick from (Sorted³, 8).
**Default variation:** A for small; A plus the rest of today (B without check-off) for medium and
large.

**What it is.** A Home Screen widget that shows where the person is in the day: the task now,
how much of it is left, and what comes next. It stays correct through the day without the app
open.

**Anatomy.** Drawn by the shell in SwiftUI, not by the page (a widget cannot hold a web view).
Sizes on a 393 pt wide iPhone: small 158 × 158 pt, medium 338 × 158 pt, large 338 × 354 pt
[C, Apple HIG Widgets]. Small: the current task's icon in a 44 pt bubble filled bottom-up in
`task.colour` by elapsed share, title 15 pt semibold one line, time left 13 pt regular
`text.secondary` as self-updating text; under it "Next" 11 pt semibold and the next title 13 pt.
Medium: small's content on the left, the next 3 items on the right as rows (icon 20 pt, title 13
pt, start time 12 pt). Large: up to 8 rows. Colours: `task.colour` per item, `text.primary`,
`text.secondary`, `surface` (token names per `../recipe.md` theme). Light, dark, tinted and clear
looks, as the existing widgets do (`docs/briefs/widget-reminders.md`).

**States.**
- Current task running: fill, time left, next.
- Gap: "Free" with "until 11:00 AM" and the next task.
- Nothing left today: "All done" (as the Reminders widget).
- Empty day: "Nothing planned".
- Signed out or no planner Sidekick: "Open Midas".
- A task crossing midnight: shown on the next day too, as the same task with "since 11:00 PM"
  (checklist 26); never as a new task.
- Overlap: the earlier-starting task is "now"; the other is listed next with its start time.
- Stale data (the app has not run since the day changed): the widget still rolls to the next day
  from its own timeline entries.

**Interactions.** Tap anywhere: opens the planner Sidekick (`MidasLink.openSidekick`). No
scrolling (WidgetKit has no `ScrollView`). Check-off (variation B) is on request: it needs an App
Intent like the Reminders widget's `TickReminderIntent`. No haptics.

**Words.** "Now", "Next", "Free", "until 11:00 AM", "in 15 min", "15 min left", "All done",
"Nothing planned", "Open Midas". Gallery name and description: set by the shell brief.

**Data.** Reads `task:` (title, colour, icon, day, start, duration, allDay, done, repeat,
zone) and `exception:`, `settings:planner` (clock, dayStartsAt). How the widget gets them is
the open question of `../shell/planner-widget.md`.

**Needs.** Shell lacks it: `../shell/planner-widget.md`. The widget extension exists with the
Sidekicks folder widget and the Reminders widget only.

**Edge cases.** 26 (midnight on both days), 44 (current and next, correct all day), 16 (12/24
hour), 27 (day boundary), 30 (DST: entries computed in the phone's zone).

**Tests.**
- Given tasks at 9:00 to 10:00 and 10:30 to 11:00, when the timeline is built for 9:30, then the
  entry shows the 9:00 task as now with 30 min left and the 10:30 task as next.
- Given the same day, when the timeline is built, then it has an entry at 10:00 (now becomes
  "Free"), at 10:30 and at 11:00 ("All done"), and at the next day boundary.
- Given a task 23:00 to 01:00, when the widget's day is the next day at 00:30, then the task shows
  as now, once, with "since 11:00 PM".
- Given no tasks today, then the widget shows "Nothing planned", not "All done".
- Given no shared data, then the widget shows "Open Midas".

**Evidence.** ANALYSIS.md 3.9 DP-OUT-01; love 13 (Structured ~17, TickTick 3); leave reason 9;
checklist 26, 44. Screenshots: `hi5.jpg` (Structured widget and banner),
`d/ticktick/appstore_9.png`.

---

### DP-OUT-02 Lock Screen and "Up Next"

**Tag:** core. Reason: checklist 44 names it with DP-OUT-01 (current and next item outside the
app).
**Variations:**
- A. Rectangular "Up Next": next title and time-until (Akiflow "Morning workout, In 2 minutes",
  Morgen "UP NEXT", iOS 27 Up Next widget).
- B. Daily overview list (Tiimo).
- C. Titles hidden on the Lock Screen (Notion Calendar).
**Default variation:** A.

**What it is.** A Lock Screen accessory widget that shows the next item and the time until it.

**Anatomy.** Drawn by the shell. Accessory families: rectangular (title 15 pt semibold, one line;
"in 12 min" or "11:00 AM" 13 pt), circular (the current task's fill as a ring around its icon),
inline (one line above the clock: "Run · in 12 min"). The Lock Screen renders accessory widgets
monochrome or tinted; task colours do not show [C, WidgetKit rendering modes]. Exact accessory
sizes per device [U].

**States.** Next task today; current task with time left when there is no next; "All done";
"Nothing planned"; "Open Midas". Locked with previews hidden: titles hidden only if variation C is
chosen in settings.

**Interactions.** Tap: unlocks and opens the planner Sidekick. No buttons.

**Words.** "Next", "in 12 min", "Now", "All done", "Nothing planned", "Open Midas".

**Data.** As DP-OUT-01.

**Needs.** Shell lacks it: `../shell/planner-widget.md`. Lock Screen widgets are "recorded, not
worked on" (PRODUCT.md 6).

**Edge cases.** 44.

**Tests.**
- Given a task at 10:30, when the entry for 10:18 is built, then the rectangular view shows the
  task and a relative time that reads "in 12 min".
- Given the last task of the day ended, then the view shows "All done".

**Evidence.** ANALYSIS.md 3.9 DP-OUT-02 (no loves, no complaints found); checklist 44.
Screenshots: `b/appstore/akiflow_5.jpg`, `d/morgen/appstore_9.png`.

---

### DP-OUT-03 Live Activity and Dynamic Island for the current task

**Tag:** core. Reason: checklist 45; leave reason 9 names an unreliable Live Activity (Tiimo).
**Variations:**
- A. Mirrors the focus timer (Structured).
- B. Ring with an expanded "42:43" and pause; must be turned on by hand (Tiimo).
- C. Current item, cannot advance without opening the app (Akiflow).
- D. Pomodoro, landscape and StandBy (TickTick).
- E. Countdown in seconds (Timepage, Fantastical).
**Default variation:** A, started from the page's focus screen; minutes, not seconds (Timepage's
seconds called "unnerving").

**What it is.** The running task's countdown on the Lock Screen and in the Dynamic Island while
the page is closed.

**Anatomy.** Drawn by the shell from values the page gives. Lock Screen card 371 × 84 to 160 pt
with 14 pt margins: icon 32 pt in a bubble of `task.colour`, title 17 pt semibold, end time 13 pt,
time left as self-updating text 28 pt semibold, a progress bar (`ProgressView(timerInterval:)`)
4 pt in `task.colour`. Dynamic Island compact: icon leading, time left trailing, 52.33 × 36.67 pt
each. Minimal: the fill ring. Expanded: card content. The island background is always black.
Limits: 8 h active, up to 12 h on the Lock Screen, 4 KB of data, no network, no web content
[C, ios-notifications-reference L01 to L03].

**States.** Running; overtime ("5 min over", if the page allows overtime, DP-FOC-02); ended
(dismissed within minutes); stale (the end time passed and the app has not run); turned off by
the person in Settings (no card; the page still works).

**Interactions.** Tap: opens the planner Sidekick. Buttons (on request): "+5 min" and "Done" as
`LiveActivityIntent`, inactive while locked until unlock [C, L04]. No haptics from the page.

**Words.** "12 min left", "Ends 10:30 AM", "5 min over", "+5 min", "Done".

**Data.** Writes a request record (shape in `../shell/live-activity.md`) with taskId, title,
icon, colour, start, end. Reads back its status. Extending a timer rewrites `task:` (or the
occurrence's `exception:`) and the request.

**Needs.** Shell lacks it: `../shell/live-activity.md`. No `NSSupportsLiveActivities`, no
ActivityKit code in the shell today.

**Edge cases.** 45 (appears when expected, goes away after), 21 (extending updates it and the
alerts), 20 (finishing early ends it).

**Tests.**
- Given a focus started on a 10:00 to 10:30 task, when the page writes the start request, then
  the shell starts one activity with end 10:30 and the request's status becomes "running".
- Given the person extends by 5 minutes, then the same activity's end becomes 10:35 and no second
  activity exists.
- Given the task is marked done at 10:20, then the activity ends and is dismissed.
- Given 10:30 passes with no update, then the activity shows stale or ends; it never shows
  "0 min left" for more than a minute.

**Evidence.** ANALYSIS.md 3.9 DP-OUT-03; love 13 (Tiimo 2, inside Structured's ~17); Tiimo
"invisible 90% of the time" (E); checklist 45. Screenshots: `a/tiimo/site_dynamic_island.png`,
`a/tiimo/as_04.png`.

---

### DP-OUT-04 Apple Watch

**Tag:** core. Reason: no Watch is a reason users leave (leave reason 9: Sunsama 361 votes, its
top request; Llama). Not a checklist item.
**Variations:**
- A. Today list with "19m remaining" (Structured).
- B. Step timer "Make bed 3m 59s · 1 of 10 · End: 6:50am" (Routinery).
- C. Today only (TickTick, Things).
- D. Complication behind a paywall (Fantastical).
**Default variation:** A.

**What it is.** Today and the current task on the wrist.

**Anatomy.** Not specified here: Midas has no Watch target (ANALYSIS.md 7.2; PRODUCT.md lists
none). A Watch app or complication would be native code drawn from records, like a widget.

**States.** Not specified.

**Interactions.** Not specified. A Sidekick page cannot run on the Watch.

**Words.** Not specified.

**Data.** Would read `task:`, `exception:`, `settings:planner`.

**Needs.** Shell lacks it. No brief in this set: the five briefs follow the checklist items
ANALYSIS.md section 7.3 lists as not built, and no checklist item names the Watch.

**Edge cases.** None from the checklist.

**Tests.** None until a Watch target is specified.

**Evidence.** ANALYSIS.md 3.9 DP-OUT-04; Routinery widget or Watch 11 hits (A); leave reason 9.
Screenshots: `hi6.jpg`, `a/routinery/as_08.png`.

---

### DP-OUT-05 Per-task notifications (before, start, end)

**Tag:** core. Reason: leave reason 9 (no task notifications: Motion, FlowSavvy, Sunsama 333
votes); checklist 41, 42, 43, and 21, 28, 30, 31.
**Variations:**
- A. At start and at end by default, up to 3 alerts, at most 3 h before, 35+ sounds, Time
  Sensitive; banner "Starts in 5 min | 12:00 - 13:00 (1 hr)" (Structured).
- B. "Morning workout in 2 minutes" plus a daily overview (Akiflow).
- C. Time to Leave (Apple).
- D. Push or alarm per routine (Routinery).
- E. Fixed offsets (Timepage).
**Default variation:** A within what the engine does today: up to 3 alerts per task, at most
180 minutes before, default "at start" and "at end", the default sound, the Midas buttons.

**What it is.** Alerts tied to each task's times, delivered with the app closed.

**Anatomy.** A standard iOS notification drawn by iOS: Midas icon and name, `title`, `body`,
default sound, grouped per Sidekick (NOTIFICATIONS.md 5). In the page: an alerts list in the task
editor, one row per alert with a remove control, "Add Alert", and a sheet with hours and minutes
wheels (0 to 3 h) and chips 1, 5, 15 min (Structured's alerts sheet).

**States.**
- No permission: nothing is booked; the page still saves alerts (5.1.2(i): the planner works
  without notifications).
- Task done: its pending alerts removed (records.md 3.3).
- Task moved, resized, extended: alerts move.
- Task in the inbox or deleted: no alerts.
- Alert time already passed when saved: not written (records.md 3.3).
- All-day task: alerts from `allDayAlertTime` (08:00 default).
- Over the 48 booked: kept in Midas's queue; fires when its turn comes, or once as "missed" if
  Midas did not run (NOTIFICATIONS.md 7).

**Interactions.** From the notification (long-press): Done, Snooze 10 Minutes, Snooze 1 Hour,
Snooze Until Tomorrow (fixed for every Sidekick). Tap: opens the planner. Done marks the task done
when the page next opens (records.md 3.5). Per-Sidekick buttons ("Start", "+5 min") are not
built. Custom sounds and Time Sensitive are not built (NOTIFICATIONS.md 7).

**Words.** Notification title: the task's title. Body: "Starts at 9:30 AM" (before start),
"9:30–11:00 AM" (at start), "Ends at 11:00 AM" (at end). Absolute times, so a late delivery is
still true (Notion said "now" for a 15-minute alert, C). Editor: "Alerts", "At Start", "At End",
"5 min before", "Add Alert", "None".

**Data.** `task:` (alerts, day, start, duration, allDay, zone, repeat, done), `exception:`,
`settings:planner` (defaultAlerts, allDayAlertTime, clock); writes `reminder:<taskId>~<alertKey>`
and segments (records.md 3).

**Needs.** Shell has it: the notification engine (`reminder:` records). Not covered by the engine
as built: a floating one-time alert (`../shell/local-time-alerts.md`), per-occurrence exceptions
in a repeat (`../shell/repeat-exceptions.md`). The page covers both today with the workarounds in
records.md 3.6 and 3.8.

**Edge cases.** 21, 28, 30, 31, 41, 42, 43.

**Tests.**
- Given a task 9:30 to 11:00 with alerts start-5, start, end, when saved at 8:00, then three
  records `reminder:<id>~s5`, `~s0`, `~e0` exist with `at` 9:25, 9:30, 11:00 local.
- Given that task, when its start moves to 10:00, then the three records' `at` are 9:55, 10:00,
  11:30 and no other `reminder:<id>~` record exists.
- Given that task, when it is deleted, then `store.query('reminder:<id>~')` returns nothing.
- Given a task starting in 3 minutes with a 5-minute alert, when saved, then `~s5` is not written.
- Given `~s0` has `done: true` written by the shell, when the page opens, then the task is done
  and `~e0` is deleted.
- Given a running timer extended by 10 minutes, then `~e0` moves 10 minutes later.

**Evidence.** ANALYSIS.md 3.9 DP-OUT-05; Structured ~16 (RG-C); leave reason 9; notifications
failing 41 negative hits (E). Screenshots: `hi5.jpg`, `agent/help/1870914_3.png`.

---

### DP-OUT-06 Daily plan and review notifications

**Tag:** on request. Reason: not a checklist item and not a leave reason; the only complaint is
Tiimo prompting "after every single action". The rituals it starts (love 11) are DP-RES-02 and
DP-RES-03.
**Variations:**
- A. "Review your day" and "Plan your week" (Tiimo).
- B. Replan prompt Morning, Evening or at a time (Structured).
- C. Auto-prompt at a set time; plans tomorrow after 3 PM (Sunsama).
- D. Daily briefing (Timepage).
- E. Daily overview (Akiflow).
**Default variation:** B with fixed text.

**What it is.** A scheduled nudge to plan the day or close it.

**Anatomy.** A standard notification. In the page: two rows in settings, each a switch and a
time.

**States.** Off (default); on at a time; no notification permission (the rows still save).

**Interactions.** Tap: opens the planner on today (plan) or on the review (DP-RES-02). Done and
Snooze as for every reminder; Done on a daily repeat writes `lastDoneAt` only.

**Words.** Title "Plan Today" / "Review Today". No body.

**Data.** `settings:planner.planPrompt`, `reviewPrompt`; writes `reminder:planner~plan` and
`reminder:planner~review` as daily repeats with `timeZone`. Each is 1 slot (interval 1, no
`until`).

**Needs.** Shell has it: a daily `reminder:` repeat.

**Edge cases.** 30 (a daily repeat keeps its wall-clock time across DST).

**Tests.**
- Given plan prompt on at 08:00, then `reminder:planner~plan` has `repeat.every` `day` and `at`
  08:00 local.
- Given it is turned off, then the record is deleted.

**Evidence.** ANALYSIS.md 3.9 DP-OUT-06. Screenshot: `a/tiimo/site_notifications.png`.

---

### DP-OUT-07 Siri, Shortcuts and quick-add surfaces

**Tag:** on request. Reason: no loves counted, no complaints, not a checklist item.
**Variations:**
- A. Siri into a brain dump plus a quick-add widget (Ellie).
- B. Siri (Motion).
- C. Siri, Action Button, long-press icon (Akiflow).
- D. Siri and Shortcuts (Timepage).
- E. Siri AI (Structured 4.6).
**Default variation:** none set.

**What it is.** Adding a task or asking about the day without opening the page.

**Anatomy.** System surfaces (Siri, Shortcuts, Action button, Home Screen quick actions), all
native.

**States.** Not specified.

**Interactions.** Not specified.

**Words.** Siri phrases for App Shortcuts must contain the app name (PRODUCT.md 6, Xcode error per
forum reports).

**Data.** Would write `task:` with `inbox: true`.

**Needs.** Shell lacks it. App Shortcuts that open a Sidekick are planned for next week
(PRODUCT.md 6); adding an item by Siri is not named. No brief in this set.

**Edge cases.** 13 (an inbox task with no time).

**Tests.** None until the surface is specified.

**Evidence.** ANALYSIS.md 3.9 DP-OUT-07. Screenshot: `b/appstore/motion_9.jpg`.
