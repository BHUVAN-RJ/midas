# Feedback (DP-FB)

Feedback is what the planner gives back: how checking a task off looks and sounds, rewards and
streaks, a look back at the day, and undo. Four patterns, from research `ANALYSIS.md` section
3.8. Structured preset values come from `structured-ui-teardown.md` (T) sections 1.1, 1.10, 1.12
and 3. Screenshot paths are relative to the base folder in `ANALYSIS.md` section 8. Theme tokens
are defined in `recipe.md`.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-FB-01 | Completion animation, sound and haptic | core | Structured fill and strike-through, sound made in code, no haptic |
| DP-FB-02 | Rewards and streaks | on request | Routinery streak counter with a plant |
| DP-FB-03 | Review and stats | on request | Llama Overview, planned against spent |
| DP-FB-04 | Undo | core | The page's own Undo control after each change |

---

### DP-FB-01 Completion animation, sound and haptic

**Tag:** core (checklist 8). **Variations:**
- Structured: fill, strike-through, a sound and a haptic, each toggleable; no confetti found [U] (T).
- Tiimo: purple confetti squiggles and sounds (A).
- Llama: confetti on by default (A).
- Sorted³: "ding" (A).
- Todoist: sound and haptic [R] (D).

**Default variation:** Structured fill and strike-through with a short sound made in code. No
haptic: a Sidekick page has no haptics API (listed as later native reach, `PRODUCT.md` section 5;
web vibration in iOS WebKit is unverified [U]).

**What it is.** What the check feels like, and how a done item looks afterwards.

**Anatomy.**
- Ring at the row's right: 23 pt, 2 pt stroke in the task colour. Done: filled with the task colour, white ✓ 13 pt.
- Bubble: done is filled with the task colour, white glyph (DP-DAY-01 states).
- Title: struck through, colour `--ink-2` [#8A8A8E].
- All-day bubble done: stays filled, label struck through.
- Sound: a two-tone tick, about 120 ms, made with Web Audio (two sine notes, a fast fade). No file.

**States.** To do; done; done then undone; sound off (setting); reduced motion (no animation).

**Interactions.**
- Tap the ring: fill grows from the centre in 200 ms ease-out, strike-through draws left to right in 200 ms, the sound plays. Reduced motion: instant.
- Tap a done ring: back to to do, no sound.
- The tap is a user gesture, so WebKit lets the sound play.
- Confetti variation (Tiimo, Llama): a burst of 12 to 20 squiggles in the task colour from the ring, 700 ms, `<canvas>`; off under reduced motion.

**Words.** None on screen. Setting row: "In-App Sound" (DP-SET-05).

**Data.**
- One-time task: writes `task:` done, doneAt.
- One occurrence of a repeat: writes `exception:<taskId>:<date>` with done and doneAt.
- Marks the task's derived `reminder:` records done, so later alerts for it do not fire.
- Reads the sound toggle from `settings:planner` (a field records.md does not list yet, `sound`).

**Needs.** Page alone. Haptic: not available. The done state of one repeat occurrence silencing
that occurrence's later alerts (its end alert) needs `shell/repeat-exceptions.md`; until then the
end alert of a done occurrence still fires.

**Edge cases.** 8, 23 (`doneAt` is the real moment), 43.

**Tests.**
- Given a to-do task, when its ring is tapped, then `done` is true, `doneAt` is now, and the title has `text-decoration: line-through`.
- Given a done task, when its ring is tapped, then `done` is false and the title has no strike-through.
- Given a task with an end alert, when it is done before the end, then its end `reminder:` is done or deleted.
- Given a daily task, when the 12 Oct occurrence is done, then `exception:<id>:2026-10-12` has done true and the 13 Oct occurrence shows to do.
- Given sound off, when a ring is tapped, then no AudioContext node is started.

**Evidence.** DP-FB-01; Tiimo 4 hits plus 2 quotes, Sorted³ "a little dopamine hit" 1, Structured
calm and dopamine ~15 (RG-C; loves #12). Screenshot `a/tiimo/site_plan_today.png`.

---

### DP-FB-02 Rewards and streaks

**Tag:** on request (not a checklist item or leave reason). **Variations:**
- Tiimo: rewards orbs and streaks (A).
- Routinery: a plant per streak day (A).
- Ellie: unlockable app icons (A).
- Todoist: Karma [R] (D).

**Default variation:** Routinery streak counter: "🌱 8" in the header.

**What it is.** A count of days in a row with every task done.

**Anatomy.** In the header, right of the date: a capsule, `--accent` 15% tint, 28 pt tall, "🌱 8"
15 pt semibold `--accent`. Tapping it opens a month grid where each streak day has a dot in
`--palette-4` [#91BE6C].

**States.** Streak 0: the capsule is hidden. Running streak. Today not finished yet: the count
shows yesterday's streak. Broken: back to 0 the next day.

**Interactions.** Tap: month grid sheet. No pop-ups, no prompts.

**Words.** "🌱 8" · sheet title "Streak".

**Data.** Computed from `task:` records (and `exception:` done flags) per day; a day counts when
it had at least one task and all were done by the `settings:planner` day end. No new record.

**Needs.** Page alone.

**Edge cases.** 27 (the day end decides which day a late task belongs to).

**Tests.**
- Given 3 past days each with all tasks done, then the capsule reads "🌱 3".
- Given yesterday had one unfinished task, then the streak is 0 and the capsule is hidden.
- Given a day with no tasks between two full days, then the streak does not break (a day with no tasks is skipped).

**Evidence.** DP-FB-02; Routinery plant 13 hits, Tiimo 1 quote (A). Screenshots
`a/tiimo/as_06.png`, `a/routinery/as_03.png`.

---

### DP-FB-03 Review and stats

**Tag:** on request (not a checklist item or leave reason). **Variations:**
- Llama: Overview, planned against spent (A).
- Akiflow: "Rate your Day" and weekly "Stats" (B).
- Tiimo: Insights tab and mood log (A).
- Routinery: yellow-dot summary calendar (A).

**Default variation:** Llama Overview: planned time against spent time for a day.

**What it is.** A look back at one day.

**Anatomy.** A sheet from the date header's menu: title "Overview" 28 pt bold; two numbers
"Planned 6h 30m" and "Spent 4h 10m", 22 pt semibold, labels 13 pt `--ink-2`; "Done 5 of 8"; a row
per task with planned and spent, overtime in red #FF3B30.

**States.** No tasks: "No Tasks". No focus time recorded: "Spent" shows the planned time of done
tasks.

**Interactions.** Tap a row: the task's editor. Left and right arrows: previous or next day.

**Words.** "Overview" · "Planned" · "Spent" · "Done 5 of 8" · "No Tasks".

**Data.** Reads `task:` duration, done. Spent time comes from DP-FOC-01 and DP-FOC-02 (time the
focus screen ran, and overtime), kept in a `task:` field records.md does not list yet
(`spentMin`).

**Needs.** Page alone.

**Edge cases.** 27.

**Tests.**
- Given 2 done tasks of 30 and 60 min and 1 unfinished of 45, then "Planned 2h 15m" and "Done 2 of 3".
- Given a 30-min task ended at +10 overtime, then its row shows spent 40m in red.

**Evidence.** DP-FB-03; weak (Routinery 1, A). Screenshot `a/llama/as_08.png`.

---

### DP-FB-04 Undo

**Tag:** core (checklist 34 and 54). **Variations:**
- Structured: shake for the iOS Undo/Redo alert (T 1.12).
- Sorted³: users asked for undo after Auto Schedule (A).

**Default variation:** the page's own Undo control shown after each change (the care-reminders
Sidekick has Undo on list delete). Shake is not used: shake detection needs device motion, which
in WKWebView needs a permission prompt [U], and a Sidekick has no native API.

**What it is.** Reversing the last change: a delete, a move, a bulk change, an edit to all
occurrences of a repeat.

**Anatomy.** A floating toast above the tab bar: `--ink` at 90% fill, 14 pt radius, 48 pt tall,
16 pt side margins. Left: the result, 15 pt white ("Deleted", "Moved", "Shifted 4"). Right:
"Undo", 15 pt semibold `--accent`.

**States.** Hidden; shown for 6 seconds after a change; replaced by the next change's toast;
offline (works, local store).

**Interactions.** Tap "Undo": restores every record the change touched, then shows "Undone" for
2 seconds. The toast swipes down to dismiss. The page keeps the last 20 changes in memory; a
second "Undo" from the date header's "•••" menu goes one further back. The stack is lost when the
page reloads (no localStorage or IndexedDB; `PRODUCT.md` section 5).

**Words.** "Deleted" · "Moved" · "Moved 4" · "Shifted 4" · "Cleared 5" · "Updated All" · "Undo" ·
"Undone".

**Data.** Before each change the page snapshots the old value (or absence) of every key it will
write: `task:`, `reminder:`, `exception:` records. Undo writes those values back and deletes keys
that did not exist. One user action is one undo step, however many records it touched.

**Needs.** Page alone. The shell's op log is append-only and replayable, but for operator recovery
only; there is no user-facing rollback in the shell.

**Edge cases.** 34 (an "All Tasks" edit of a repeat, including the series split of DP-ADD-01, is one
step), 54 (every delete and move), 43 (restored alerts are restored records, so they fire again;
removed ones stay removed).

**Tests.**
- Given a task deleted, when "Undo" is tapped, then its `task:` and `reminder:` records equal the values before the delete.
- Given "All Future Tasks" changed a daily task's title from 14 Oct, when "Undo" is tapped, then one `task:` exists with the old title, no `repeat.until`, and the split-off record is gone.
- Given "Move to Today" moved 4 tasks, when "Undo" is tapped, then all 4 have their old day.
- Given a task created (not deleted), when "Undo" is tapped, then the `task:` key no longer exists.

**Evidence.** DP-FB-04; Things "No undo option :: Deal breaker" 1, Notion events lost with no undo
2, Google "all events" no undo 1; undo 17 negative hits (E). No screenshot saved (T 1.12
describes it).
