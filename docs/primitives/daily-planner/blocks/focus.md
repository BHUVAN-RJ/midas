# Focus and timers (DP-FOC)

Focus is the running task given the whole screen: a countdown, extending and ending early,
sequences that run themselves, focus intervals with sound, and the alarm at the end of a task.
Five patterns, from research `ANALYSIS.md` section 3.7. "Timers that move you along" is loves #5.
Structured preset values come from `structured-ui-teardown.md` (T) section 1.7. Screenshot paths
are relative to the base folder in `ANALYSIS.md` section 8. Theme tokens are defined in
`recipe.md`.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-FOC-01 | Full-screen countdown for the current task | on request | Structured "Focus Now" draining capsule |
| DP-FOC-02 | Extend and overtime | core | Llama "−5 / +5" with overtime in red, plus "End Now" |
| DP-FOC-03 | Play a sequence | on request | Llama: focus moves to the next task when one ends |
| DP-FOC-04 | Intervals and ambient sound | on request | Structured Intervals, sounds made in code |
| DP-FOC-05 | End-of-task alarm | core | Structured "At end of tasks" alert; not held by the current `reminder:` format (`../records.md` 12) |

Page limits that apply to all five: a page's JavaScript stops when Midas goes to the background,
so in-page timers, sounds and voice run only while the page is open; time is always computed from
`Date.now()` and the task's `at` and `duration`, never from counting ticks, and is recomputed on
`visibilitychange`. Outside the page the shell's notification engine fires from the task's `reminder:` record;
a countdown outside the page is a Live Activity (`shell/live-activity.md`). No haptics (no API).

---

### DP-FOC-01 Full-screen countdown for the current task

**Tag:** on request (not a checklist item or leave reason; Structured focus ~25 mentions).
**Variations:**
- Structured: "◎ Focus Now" for the current task only; a draining capsule in the task colour; "2:10:33 REMAINING" (T 1.7).
- Tiimo: a ring around the icon; starts by itself at the task's time (A).
- Llama: big italic countdown or a 60-minute pie (A).
- Routinery: dark screen with a yellow ring (A).
- TickTick: Pomo ring (D). Ellie: floating focus bar (A).

**Default variation:** Structured "Focus Now".

**What it is.** The current task fills the screen with its time left.

**Anatomy.**
- Entry: in the editor header of the current task only, a translucent `--accent` capsule "◎ Focus Now", 36 pt tall, 15 pt semibold white.
- Background: the task colour as a vertical gradient, full colour at top to `color-mix(in srgb, var(--task) 75%, black)` at bottom.
- ✕ 30 pt translucent white circle at top left (inset from the left edge by 16 pt).
- Countdown: about 64 pt bold white, `font-variant-numeric: tabular-nums`, "2:10:33"; "REMAINING" under it, 13 pt semibold, letter-spacing 0.15em, white 70%.
- Centre capsule: about 200 × 450 pt (scaled to fit the screen height), 3 pt white outline, filled with the task colour from the top down to the share of time left, grey `--line-future` below; the task glyph 64 pt white in the middle; line stubs above and below.
- Bottom card: white 20% tint, 20 pt radius: "12:15–2:45 PM (2 hr, 30 min)" 13 pt, title 17 pt semibold, completion ring 23 pt, "☑ 0/3".
- Bottom pill: "Subtasks", "Notes", "Intervals" (Intervals only when DP-FOC-04 is built).

**States.** Running. Seconds hidden (tap the countdown). Ended (moves to DP-FOC-02 overtime).
Task done (closes to the timeline). Not the current task: no entry. Page reopened mid-task: the
countdown is correct at once because it is computed from the task's times.

**Interactions.**
- "Focus Now" opens the screen (300 ms rise).
- Tap the countdown: hide or show seconds.
- ✕ asks "Stop Focus" or "Minimize". Both return to the timeline; the countdown is not stored, so both look the same to the record.
- Ring on the bottom card: done, closes the screen.
- The capsule drains continuously; under reduced motion it updates once a minute.

**Words.** "Focus Now" · "REMAINING" · "Subtasks" · "Notes" · "Intervals" · "Stop Focus" ·
"Minimize" · "Cancel".

**Data.** Reads the task's `at`, `duration`, `colour`, `icon`, `subtasks`, `notes`. Writes the task's
`done`, `completedAt`, `subtasks` (`store.update`). No timer record.

**Needs.**
- Page alone while open.
- Shell lacks the Live Activity and Dynamic Island countdown outside the app (Structured mirrors its timer there): `shell/live-activity.md`.
- Keeping the screen awake: the Screen Wake Lock API inside WKWebView is unverified [U].

**Edge cases.** 2 (time left is visible), 20 (ending early, DP-FOC-02).

**Tests.**
- Given a task 14:00–15:00 and now 14:20:00, when the focus screen opens, then it reads "40:00" and the capsule is two-thirds filled.
- Given the focus screen open, when the page is hidden for 10 minutes and shown, then it reads 10 minutes less, not the value from before hiding.
- Given a task that is not current, when its editor opens, then no "Focus Now" shows.

**Evidence.** DP-FOC-01; Routinery "timer" 32 of 252 positive, Structured focus ~25 (RG-C), Tiimo 2,
Llama 2, TickTick 3; Sunsama full-screen request 143 votes; Tiimo music cannot be turned off 1.
Screenshots `agent/help/331010_1.png`, `a/routinery/as_04.png`.

---

### DP-FOC-02 Extend and overtime

**Tag:** core (checklist 20 and 21). **Variations:**
- Tiimo: "+1" (FAQ) and "+5" (art) (A).
- Llama: "−5 / +5", overtime counted in red (A).
- Routinery: "− 15m +" (A).

**Default variation:** Llama "−5 / +5" with overtime counted up in red, plus "End Now". Extending
pushes later flexible tasks only when they would now overlap.

**What it is.** Change the running task's length while it runs, end it early, or let it run
over.

**Anatomy.** Under the countdown (focus screen) and as a third line on the current timeline row:
two 44 pt translucent capsules "−5" and "+5", and "End Now". Overtime: the countdown turns red
#FF3B30 (literal) and reads "+3:12", "OVER" under it.

**States.** Running; less than 5 minutes left ("−5" inert); overtime; ended early.

**Interactions.**
- "+5": duration + 5. Any later flexible task today that now starts before the new end is pushed to the new end, and the ones after it in a chain, as DP-RES-04 does.
- "−5": duration − 5, never below the time already run.
- "End Now": duration becomes now − start, `done` true, `completedAt` now. The freed time shows as free (DP-TIME-04).
- Overtime: nothing moves by itself. The overtime line offers "Shift Later Tasks" (DP-RES-04).
- Each tap rewrites the changed tasks (`duration`; `at` of pushed tasks); the engine moves their notifications. No notification depends on the end (`../records.md` 12).

**Words.** "−5" · "+5" · "End Now" · "OVER" · "Shift Later Tasks".

**Data.** Writes the task's `duration`, `done`, `completedAt`; `at` of pushed tasks.

**Needs.** Page alone; the notification engine moves alerts when the records change (shell has
it).

**Edge cases.** 20, 21, 43 ("End Now" marks the task done, so none of its notifications fire).

**Tests.**
- Given a task 14:00–14:30 and a next task at 14:30, when "+5" is tapped, then duration is 35 and the next task's `at` is 14:35.
- Given the same, when "End Now" is tapped at 14:20, then duration is 20, `done` is true and `completedAt` is 14:20.
- Given a task ended at 14:30 and now 14:33:12, when the focus screen shows, then it reads "+3:12" in red and no task has moved.

**Evidence.** DP-FOC-02; counted inside DP-FOC-01 loves; Tiimo 3★ 2026-01-23 "extending does not
shift what follows, and old alerts still fire" (E); Structured board finish early 2.3k
(checklist 20). Screenshots `a/tiimo/as_06.png`, `a/llama/as_05.png`.

---

### DP-FOC-03 Play a sequence

**Tag:** on request (not a checklist item or leave reason). **Variations:**
- Routinery: play ▶ with a voice for each change and "NEXT Stretch" (A).
- Llama: auto-start next task (A).
- Tiimo: subtask "Now / Next" timers (A).

**Default variation:** Llama: when a task ends while the focus screen is open, the screen moves
to the next task in the day. A "Next" line shows it in advance.

**What it is.** Back-to-back tasks run one after another without the person opening each.

**Anatomy.** On the focus screen, under the bottom card: "NEXT" 11 pt letter-spaced white 70%,
then the next task's glyph and title 15 pt semibold. A ▶ "Play" button in the editor of a task
with subtasks starts the Routinery variation.

**States.** A next task exists; none (the line is hidden; the screen goes to overtime); a gap
before the next (the screen shows the gap's countdown, "Free" under it).

**Interactions.** At the end of a task: 400 ms cross-fade to the next. A short chime when sound
is on (DP-FB-01 setting). Routinery variation: spoken "Next: Stretch" through `speechSynthesis`
when available.

**Words.** "NEXT" · "Free" · "Play" · spoken "Next: <title>".

**Data.** Reads today's `reminder:` tasks in order. Routinery variation with per-step durations needs
durations on subtasks, a field records.md does not list yet.

**Needs.** Page alone while open. Spoken steps through `speechSynthesis` in WKWebView are
unverified [U]. With Midas in the background nothing advances or speaks; the next task's start
alert (DP-OUT-05) is the only signal. A step-by-step countdown outside the app is
`shell/live-activity.md`.

**Edge cases.** 2.

**Tests.**
- Given tasks 9:00–9:15 and 9:15–9:45 and the focus screen on the first, when the clock reaches 9:15:00, then the screen shows the second task with "30:00".
- Given a gap 9:15–9:30, when the first ends, then the screen shows "15:00" with "Free".

**Evidence.** DP-FOC-03; Routinery voice 9 hits, 3 quotes (A); complaints skipping crosses off
steps 1, robotic voice 2. Screenshots `a/routinery/as_04.png`, `a/tiimo/site_subtask_timers.webp`.

---

### DP-FOC-04 Intervals and ambient sound

**Tag:** on request (not a checklist item or leave reason). **Variations:**
- Structured Intervals (Pro): Pomodoro needs 45 min left, Deep Focus 90 (T).
- TickTick: Pomo, Stopwatch, white noise (D).
- Llama: chimes every N minutes and soundscapes (A).
- Tiimo: "Lo-fi beats" (A).

**Default variation:** Structured Intervals, with chimes and white noise made in code (Web Audio),
no sound files.

**What it is.** Focus and break cycles inside the running task, with optional background sound.

**Anatomy.** The "Intervals" tab of the focus screen's bottom pill opens a sheet: two option rows
"Pomodoro" (25 min focus, 5 min break) and "Deep Focus" (90 min focus); a row is inert when the
task has less time left than it needs. While running: an icon ◎ (focus) or ☕ (break) beside the
countdown; buttons "Skip Break" / "Skip Focus" and "Stop Intervals". A "Sound" row: "Off",
"Chime", "White Noise".

**States.** Off; focus; break; skipped; task ended (intervals stop).

**Interactions.** "Start Interval" begins; a chime at each change; "Skip" jumps to the next
phase; "Stop Intervals" returns to the plain countdown. Sound plays only after a tap (WebKit
needs a user gesture) and stops when the page is hidden.

**Words.** "Intervals" · "Pomodoro" · "Deep Focus" · "Start Interval" · "Skip Focus" · "Skip
Break" · "Stop Intervals" · "Sound" · "Off" · "Chime" · "White Noise".

**Data.** Interval start time in the task's `intervalsStartedAt` (`../records.md` 2.1; the kind is a
field records.md does not list yet), so the phase is recomputed after a reload. Optional: phase
changes announced with the app closed would need one notification per phase change; as extra
`reminder:` records they would be extra tasks, so this is not mapped (`../records.md` 12).

**Needs.** Page alone while open. Sound files are not used: a file larger than a record is not
built (`CONCERNS.md` concern 4) and bundle size rules apply; Web Audio makes the tones. Background
audio after Midas leaves the screen is not available to a page. Tiimo's music overriding other
audio does not apply: a page's Web Audio mixes with other audio [U].

**Edge cases.** 41 (phase changes with the app closed: not mapped, see Data).

**Tests.**
- Given 40 min left, when the Intervals sheet opens, then "Pomodoro" is inert; given 50 min left, it is active.
- Given Pomodoro started at 10:00, when the page reloads at 10:27, then the screen shows break with 3:00 left.
- Given Pomodoro started at 10:00 for a task ending 11:00, then the task's `intervalsStartedAt` is 10:00 and no `reminder:` record other than the task exists.

**Evidence.** DP-FOC-04; no separate love count; Tiimo music overrides other audio 1. Screenshots
`d/ticktick/appstore_6.png`, `a/llama/as_09.png`.

---

### DP-FOC-05 End-of-task alarm

**Tag:** core (checklist 41). **Variations:**
- Llama: Visual, Continuous (5 min) and Nag (every minute) alarms (A).
- Routinery: "Push | Alarm" per routine (A).
- Structured: "At end of tasks" alert (T).

**Default variation:** Structured "At end of tasks": a notification at the task's end, default
sound, the engine's Done and Snooze buttons. In the open page, a chime and the focus screen's
overtime state. The current `reminder:` format cannot hold an alert measured from the end
(`../records.md` 12), so only the in-page part is mapped.

**What it is.** A notification when the task's time is up, delivered with the app closed.

**Anatomy.** Notification (not mapped): Midas icon, title = task title, text "Ends 2:45 PM". In-page: the
countdown turns to overtime (DP-FOC-02).

**States.** Alert set (Structured's default is at start and at end; `settings:self.defaultAlerts` holds early alerts only);
removed; task done early (no alert); permission denied (shell's state; nothing booked).

**Interactions.** Done on a notification of the task writes `done: true` and `completedAt` into the
task itself (`../records.md` 3.5). Tapping opens the planner.

**Words.** Notification title: the task title. Text: "Ends 2:45 PM" (not mapped). Alert row in the
editor: "At End".

**Data.** Reads the task's `at` and `duration` for the in-page overtime. An end alert (`at` plus
`duration`) has no rule in the task's `alerts` (`before`, `morningOf`, `daysBefore` count back
from `at`): not mapped, `../records.md` 12. Reads `done`, `completedAt`, `lastDoneAt` and
`doneThrough` back.

**Needs.** Shell has the notification engine: one-time and repeating alerts, the shared queue past
iOS's 64, missed notifications. Shell lacks:
- Nag and continuous alarms (Llama, Routinery alarm), Time Sensitive and AlarmKit levels, custom sounds: not built in the engine (`NOTIFICATIONS.md` section 7); no brief in `shell/` yet.
- A floating one-time alert that keeps 7:00 after travel (checklist 28): `shell/local-time-alerts.md`.
- An alert measured from the end of a task: not in the engine's alert rules (`../records.md` 12).
- A repeat whose one occurrence was ended early or moved: `shell/repeat-exceptions.md`.

**Edge cases.** 21 (extend moves the alert), 41, 42 (engine queue), 43 (done, deleted or moved
tasks never alert at the old time), 30 and 31 (engine handles DST for repeats).

**Tests.**
- Given a task 14:00–14:45 with the default alerts, when saved, then `reminder:<id>` has `at` 14:00 and no rule in `alerts` (no end alert can be written), and no other `reminder:` record exists for it.
- Given that task marked done at 14:30, then it has `done: true` and `completedAt` 14:30.
- Given a task 14:00–14:45 open in focus at 14:46, then the overtime state shows and a chime plays (sound on).
- Given Done tapped on the task's notification (shell writes `done: true`, `completedAt`), when the planner opens, then the task shows done.

**Evidence.** DP-FOC-05; Routinery alarm (1★ about losing it); Llama alarm did not sound 1,
Routinery sound-only 1, ignores Do Not Disturb 1; notifications failing 41 negative hits (E).
Screenshots `a/routinery/as_06.png`, `agent/help/1870914_3.png`.
